import 'metadata_scanner.dart';

// Turns what was found in a photo into a privacy report: which kinds of hidden
// data it carries, how risky each kind is, and one score for the whole photo.
//
// No Flutter code here, so it can be unit tested. The service reads the EXIF
// fields (name -> printable text) and runs the scanner, then calls
// [MetadataAnalysis.build].

/// The kinds of hidden data, in the order they are shown (most risky first).
enum MetaCategory {
  location,
  owner,
  time,
  device,
  thumbnail,
  other,
  settings,
  image,
}

/// How much a kind of data gives away.
enum ExposureLevel { none, low, medium, high }

/// One hidden field (an EXIF tag) or one hidden block (XMP, IPTC, ...).
class MetaFinding {
  /// The raw name. EXIF tags look like `GPS GPSLatitude`. Blocks start with
  /// `#`, for example `#XMP`.
  final String tag;

  /// A readable name, such as "Latitude".
  final String label;

  /// A short readable value. Long values are cut off.
  final String value;

  final MetaCategory category;

  /// False for harmless technical fields (camera settings, image size).
  final bool sensitive;

  const MetaFinding({
    required this.tag,
    required this.label,
    required this.value,
    required this.category,
    required this.sensitive,
  });
}

class MetadataAnalysis {
  final List<MetaFinding> findings;

  /// The picture format that was detected.
  final ImageFormat format;

  /// False when the file structure could not be read to the end, so the
  /// list may be incomplete.
  final bool structureChecked;

  /// GPS position as text, for example "3.1390° N, 101.6869° E". Null when
  /// there is none or it could not be decoded.
  final String? coordinates;

  const MetadataAnalysis._({
    required this.findings,
    required this.format,
    required this.structureChecked,
    required this.coordinates,
  });

  static const MetadataAnalysis empty = MetadataAnalysis._(
    findings: <MetaFinding>[],
    format: ImageFormat.unknown,
    structureChecked: false,
    coordinates: null,
  );

  // ---------------------------------------------------------------
  // Building
  // ---------------------------------------------------------------

  /// [tags] holds every EXIF field as name -> printable text.
  factory MetadataAnalysis.build(Map<String, String> tags, FileScan scan) {
    final findings = <MetaFinding>[];

    for (final entry in tags.entries) {
      final name = entry.key;
      if (isStructural(name)) continue;
      final category = categoryOf(name);
      findings.add(MetaFinding(
        tag: name,
        label: labelOf(name),
        value: displayValue(entry.value),
        category: category,
        sensitive: isSensitive(category),
      ));
    }

    // Blocks other than EXIF. The EXIF fields are listed one by one above.
    for (final block in scan.blocks) {
      if (!block.sensitive || block.label == BlockLabel.exif) continue;
      final tag = '#${block.label}';
      findings.add(MetaFinding(
        tag: tag,
        label: block.label,
        value: _sizeText(block.bytes),
        category: categoryOf(tag),
        sensitive: true,
      ));
    }

    // An EXIF block we could not read may hide anything.
    if (scan.has(BlockLabel.exif) && tags.isEmpty && scan.bytesOf(BlockLabel.exif) > 16) {
      findings.add(const MetaFinding(
        tag: '#EXIF',
        label: 'Unreadable EXIF data',
        value: '',
        category: MetaCategory.other,
        sensitive: true,
      ));
    }

    return MetadataAnalysis._(
      findings: List<MetaFinding>.unmodifiable(findings),
      format: scan.format,
      structureChecked: scan.understood,
      coordinates: decodeCoordinates(tags),
    );
  }

  // ---------------------------------------------------------------
  // Questions about the result
  // ---------------------------------------------------------------

  List<MetaFinding> findingsIn(MetaCategory category) {
    return findings.where((f) => f.category == category).toList();
  }

  int countIn(MetaCategory category) {
    var count = 0;
    for (final finding in findings) {
      if (finding.category == category) count++;
    }
    return count;
  }

  /// Categories that have at least one finding, most risky first.
  List<MetaCategory> get categoriesPresent {
    return [
      for (final category in MetaCategory.values)
        if (countIn(category) > 0) category,
    ];
  }

  bool get hasLocation => countIn(MetaCategory.location) > 0;
  bool get hasOwner => countIn(MetaCategory.owner) > 0;
  bool get hasTime => countIn(MetaCategory.time) > 0;
  bool get hasDevice => countIn(MetaCategory.device) > 0;
  bool get hasThumbnail => countIn(MetaCategory.thumbnail) > 0;

  /// Every hidden field and block, harmless ones too.
  int get hiddenFieldCount => findings.length;

  /// Only the fields that can identify the owner, the place or the time.
  int get sensitiveCount => findings.where((f) => f.sensitive).length;

  /// True when nothing that could identify the owner, the place or the time
  /// is left. Harmless technical fields (settings, size) do not count.
  bool get isClean => sensitiveCount == 0;

  /// 0 means nothing sensitive, 100 means everything is in the file.
  int get exposureScore {
    var score = 0;
    if (hasLocation) score += 45;
    if (hasOwner) score += 15;
    if (hasTime) score += 15;
    if (hasDevice) score += 12;
    if (hasThumbnail) score += 8;
    if (countIn(MetaCategory.other) > 0) score += 5;
    return score > 100 ? 100 : score;
  }

  /// 100 minus the exposure. Higher is better, like the Security Center score.
  int get privacyScore => 100 - exposureScore;

  ExposureLevel get level {
    final score = exposureScore;
    if (score == 0) return ExposureLevel.none;
    if (score < 25) return ExposureLevel.low;
    if (score < 60) return ExposureLevel.medium;
    return ExposureLevel.high;
  }

  /// What is left, in words. Used in the message when a photo is refused.
  String get residualText {
    final parts = <String>[];
    if (hasLocation) parts.add('a GPS location');
    final fields = findings
        .where((f) => f.sensitive && f.tag.isNotEmpty && !f.tag.startsWith('#') && f.category != MetaCategory.location)
        .length;
    if (fields > 0) parts.add(fields == 1 ? '1 hidden field' : '$fields hidden fields');
    final blocks = <String>[];
    for (final finding in findings) {
      if (finding.sensitive && finding.tag.startsWith('#') && !blocks.contains(finding.label)) {
        blocks.add(finding.label);
      }
    }
    parts.addAll(blocks);
    return parts.join(', ');
  }

  /// A short text for one kind of data, shown on its card.
  String summaryFor(MetaCategory category) {
    final items = findingsIn(category);
    if (items.isEmpty) return '';

    if (category == MetaCategory.location) {
      return coordinates ?? 'GPS location data is stored in the file.';
    }

    if (category == MetaCategory.time) {
      for (final name in const ['DateTimeOriginal', 'DateTimeDigitized', 'DateTime']) {
        final hit = _firstNamed(items, name);
        if (hit != null && hit.value.isNotEmpty) return 'Taken ${hit.value}';
      }
      return items.length == 1 ? '1 time stamp' : '${items.length} time stamps';
    }

    if (category == MetaCategory.device) {
      final names = <String>[];
      for (final name in const ['Make', 'Model', 'Software']) {
        final hit = _firstNamed(items, name);
        if (hit != null && hit.value.isNotEmpty && !names.contains(hit.value)) {
          names.add(hit.value);
        }
      }
      if (names.isEmpty) {
        return items.length == 1 ? '1 camera detail' : '${items.length} camera details';
      }
      return names.join(' · ');
    }

    if (category == MetaCategory.owner) return _labelList(items, 3);

    if (category == MetaCategory.thumbnail) {
      return 'A small copy of the picture is stored inside the file. It can '
          'show the original, uncropped photo.';
    }

    if (category == MetaCategory.other) return _labelList(items, 4);

    if (category == MetaCategory.settings) {
      return items.length == 1
          ? '1 camera setting (exposure, ISO, focal length).'
          : '${items.length} camera settings such as exposure, ISO and focal length.';
    }

    return items.length == 1
        ? '1 technical field (size, orientation).'
        : '${items.length} technical fields such as size and orientation.';
  }

  /// The names to keep with the photo, so the Privacy report can be shown
  /// later. Names only. No values are kept (no coordinates, no dates).
  List<String> storedNames({int limit = 60}) {
    final seen = <String>{};
    final out = <String>[];
    for (final finding in findings) {
      if (finding.tag.isEmpty || !seen.add(finding.tag)) continue;
      out.add(finding.tag);
      if (out.length >= limit) break;
    }
    return out;
  }

  static MetaFinding? _firstNamed(List<MetaFinding> items, String name) {
    for (final item in items) {
      if (_nameOf(item.tag) == name) return item;
    }
    return null;
  }

  static String _labelList(List<MetaFinding> items, int max) {
    final labels = <String>[];
    for (final item in items) {
      if (!labels.contains(item.label)) labels.add(item.label);
    }
    if (labels.length <= max) return labels.join(', ');
    final rest = labels.length - max;
    return '${labels.take(max).join(', ')} and $rest more';
  }

  // ---------------------------------------------------------------
  // The stored names, grouped again for the Privacy report
  // ---------------------------------------------------------------

  /// Groups names from [storedNames] by kind, as readable labels.
  static Map<MetaCategory, List<String>> groupStored(Iterable<String> stored) {
    final out = <MetaCategory, List<String>>{};
    for (final tag in stored) {
      final category = categoryOf(tag);
      final label = labelOf(tag);
      final list = out.putIfAbsent(category, () => <String>[]);
      if (!list.contains(label)) list.add(label);
    }
    return out;
  }

  // ---------------------------------------------------------------
  // Names, kinds and labels
  // ---------------------------------------------------------------

  /// A field with this name is not data. It only points to another table.
  static bool isStructural(String tag) {
    final name = _nameOf(tag);
    return name == 'ExifOffset' ||
        name == 'GPSInfo' ||
        name == 'InteroperabilityOffset' ||
        name == 'JPEGInterchangeFormat' ||
        name == 'JPEGInterchangeFormatLength';
  }

  static bool isSensitive(MetaCategory category) {
    return category != MetaCategory.settings && category != MetaCategory.image;
  }

  static String titleOf(MetaCategory category) {
    return switch (category) {
      MetaCategory.location => 'Location',
      MetaCategory.owner => 'Identity and notes',
      MetaCategory.time => 'Date and time',
      MetaCategory.device => 'Camera and phone',
      MetaCategory.thumbnail => 'Embedded thumbnail',
      MetaCategory.other => 'Other hidden data',
      MetaCategory.settings => 'Camera settings',
      MetaCategory.image => 'Image details',
    };
  }

  static ExposureLevel riskOf(MetaCategory category) {
    return switch (category) {
      MetaCategory.location => ExposureLevel.high,
      MetaCategory.owner => ExposureLevel.high,
      MetaCategory.time => ExposureLevel.medium,
      MetaCategory.device => ExposureLevel.medium,
      MetaCategory.thumbnail => ExposureLevel.medium,
      MetaCategory.other => ExposureLevel.medium,
      MetaCategory.settings => ExposureLevel.low,
      MetaCategory.image => ExposureLevel.none,
    };
  }

  static const Set<String> _ownerNames = <String>{
    'Artist',
    'Copyright',
    'ImageDescription',
    'UserComment',
    'CameraOwnerName',
    'OwnerName',
    'BodySerialNumber',
    'SerialNumber',
    'LensSerialNumber',
    'CameraSerialNumber',
    'ImageUniqueID',
    'HostComputer',
    'DocumentName',
    'PageName',
    'Photographer',
    'Creator',
    'XPTitle',
    'XPComment',
    'XPAuthor',
    'XPKeywords',
    'XPSubject',
  };

  static const Set<String> _timeNames = <String>{
    'DateTime',
    'DateTimeOriginal',
    'DateTimeDigitized',
    'SubSecTime',
    'SubSecTimeOriginal',
    'SubSecTimeDigitized',
    'OffsetTime',
    'OffsetTimeOriginal',
    'OffsetTimeDigitized',
    'TimeZoneOffset',
  };

  static const Set<String> _deviceNames = <String>{
    'Make',
    'Model',
    'Software',
    'ProcessingSoftware',
    'PrintIM',
    'DeviceSettingDescription',
    'FirmwareVersion',
    'UniqueCameraModel',
  };

  static const Set<String> _imageNames = <String>{
    'ImageWidth',
    'ImageLength',
    'ExifImageWidth',
    'ExifImageLength',
    'PixelXDimension',
    'PixelYDimension',
    'Orientation',
    'XResolution',
    'YResolution',
    'ResolutionUnit',
    'ColorSpace',
    'YCbCrPositioning',
    'YCbCrSubSampling',
    'YCbCrCoefficients',
    'ComponentsConfiguration',
    'CompressedBitsPerPixel',
    'BitsPerSample',
    'Compression',
    'PhotometricInterpretation',
    'SamplesPerPixel',
    'PlanarConfiguration',
    'ExifVersion',
    'FlashPixVersion',
    'InteroperabilityIndex',
    'InteroperabilityVersion',
    'RelatedImageWidth',
    'RelatedImageLength',
    'StripOffsets',
    'RowsPerStrip',
    'StripByteCounts',
    'TransferFunction',
    'WhitePoint',
    'PrimaryChromaticities',
    'ReferenceBlackWhite',
    'FileSource',
    'SceneType',
  };

  static const List<String> _settingWords = <String>[
    'Exposure',
    'ISO',
    'FNumber',
    'Aperture',
    'Focal',
    'Flash',
    'Metering',
    'WhiteBalance',
    'Zoom',
    'Shutter',
    'Brightness',
    'Contrast',
    'Saturation',
    'Sharpness',
    'Gain',
    'SceneCapture',
    'Sensing',
    'LightSource',
    'Subject',
    'Sensitivity',
    'CustomRendered',
    'CompositeImage',
  ];

  /// Which kind of data an EXIF field (or a `#block`) belongs to.
  static MetaCategory categoryOf(String tag) {
    if (tag.startsWith('#')) {
      return tag.substring(1) == BlockLabel.thumbnail
          ? MetaCategory.thumbnail
          : MetaCategory.other;
    }
    final group = _groupOf(tag);
    final name = _nameOf(tag);

    if (group == 'GPS' || name.startsWith('GPS')) return MetaCategory.location;
    if (group == 'Thumbnail' || name == 'JPEGThumbnail' || name == 'TIFFThumbnail') {
      return MetaCategory.thumbnail;
    }
    if (group == 'MakerNote' || name == 'MakerNote') return MetaCategory.device;
    if (_ownerNames.contains(name)) return MetaCategory.owner;
    if (_timeNames.contains(name)) return MetaCategory.time;
    if (_deviceNames.contains(name) || name.startsWith('Lens')) {
      return MetaCategory.device;
    }
    if (_imageNames.contains(name)) return MetaCategory.image;
    for (final word in _settingWords) {
      if (name.contains(word)) return MetaCategory.settings;
    }
    return MetaCategory.other;
  }

  static const Map<String, String> _labels = <String, String>{
    'Make': 'Camera make',
    'Model': 'Camera model',
    'Software': 'Software',
    'ProcessingSoftware': 'Processing software',
    'LensModel': 'Lens model',
    'LensMake': 'Lens make',
    'LensSpecification': 'Lens details',
    'LensSerialNumber': 'Lens serial number',
    'BodySerialNumber': 'Camera serial number',
    'CameraSerialNumber': 'Camera serial number',
    'SerialNumber': 'Serial number',
    'CameraOwnerName': 'Camera owner',
    'OwnerName': 'Owner name',
    'Artist': 'Artist',
    'Copyright': 'Copyright',
    'ImageDescription': 'Description',
    'UserComment': 'User comment',
    'ImageUniqueID': 'Unique image ID',
    'HostComputer': 'Host computer',
    'XPTitle': 'Title (Windows)',
    'XPComment': 'Comment (Windows)',
    'XPAuthor': 'Author (Windows)',
    'XPKeywords': 'Keywords (Windows)',
    'XPSubject': 'Subject (Windows)',
    'DateTime': 'File date and time',
    'DateTimeOriginal': 'Date taken',
    'DateTimeDigitized': 'Date digitised',
    'SubSecTime': 'Fraction of a second',
    'SubSecTimeOriginal': 'Fraction of a second (taken)',
    'SubSecTimeDigitized': 'Fraction of a second (digitised)',
    'OffsetTime': 'Time zone',
    'OffsetTimeOriginal': 'Time zone (taken)',
    'OffsetTimeDigitized': 'Time zone (digitised)',
    'GPSLatitude': 'Latitude',
    'GPSLatitudeRef': 'Latitude side',
    'GPSLongitude': 'Longitude',
    'GPSLongitudeRef': 'Longitude side',
    'GPSAltitude': 'Altitude',
    'GPSAltitudeRef': 'Altitude reference',
    'GPSTimeStamp': 'GPS time',
    'GPSDate': 'GPS date',
    'GPSSpeed': 'Speed',
    'GPSSpeedRef': 'Speed unit',
    'GPSImgDirection': 'Direction the camera faced',
    'GPSImgDirectionRef': 'Direction reference',
    'GPSProcessingMethod': 'How the location was found',
    'GPSVersionID': 'GPS version',
    'GPSMapDatum': 'Map datum',
    'MakerNote': 'Manufacturer notes',
    'JPEGThumbnail': 'Thumbnail picture',
    'TIFFThumbnail': 'Thumbnail picture',
    'ExposureTime': 'Exposure time',
    'FNumber': 'Aperture (f-number)',
    'ISOSpeedRatings': 'ISO',
    'PhotographicSensitivity': 'ISO',
    'FocalLength': 'Focal length',
    'FocalLengthIn35mmFilm': 'Focal length (35 mm)',
    'ExposureProgram': 'Exposure program',
    'ExposureMode': 'Exposure mode',
    'ExposureBiasValue': 'Exposure bias',
    'MeteringMode': 'Metering mode',
    'WhiteBalance': 'White balance',
    'DigitalZoomRatio': 'Digital zoom',
    'SceneCaptureType': 'Scene type',
    'ExifImageWidth': 'Width',
    'ExifImageLength': 'Height',
    'PixelXDimension': 'Width',
    'PixelYDimension': 'Height',
    'ImageWidth': 'Width',
    'ImageLength': 'Height',
    'ColorSpace': 'Colour space',
    'XResolution': 'Horizontal resolution',
    'YResolution': 'Vertical resolution',
    'ResolutionUnit': 'Resolution unit',
  };

  /// A readable name for a field, for example "Latitude".
  static String labelOf(String tag) {
    if (tag.startsWith('#')) return tag.substring(1);
    final group = _groupOf(tag);
    final name = _nameOf(tag);
    final base = _labels[name] ?? _humanize(name);
    if (group == 'Thumbnail' && name != 'JPEGThumbnail') return 'Thumbnail: $base';
    if (group == 'MakerNote') return 'Maker note: $base';
    if (group == 'Interoperability') return 'Interop: $base';
    return base;
  }

  /// The text of a value, made safe to show: no control characters, a date
  /// written the usual way, and cut off when very long.
  static String displayValue(String raw) {
    var text = raw.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
    if (text.isEmpty) return '(binary data)';
    if (RegExp(r'^\d{4}:\d{2}:\d{2}( |$)').hasMatch(text)) {
      text = text.replaceFirst(':', '-').replaceFirst(':', '-');
    }
    if (text.length > 120) text = '${text.substring(0, 117)}...';
    return text;
  }

  // ---------------------------------------------------------------
  // GPS
  // ---------------------------------------------------------------

  /// Reads the GPS fields and returns "3.1390° N, 101.6869° E". Returns null
  /// when the fields are missing or cannot be decoded.
  static String? decodeCoordinates(Map<String, String> tags) {
    final lat = _degrees(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef'], 'S');
    final lon = _degrees(tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef'], 'W');
    if (lat == null || lon == null) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    final latSide = lat < 0 ? 'S' : 'N';
    final lonSide = lon < 0 ? 'W' : 'E';
    return '${lat.abs().toStringAsFixed(4)}° $latSide, '
        '${lon.abs().toStringAsFixed(4)}° $lonSide';
  }

  // "[3, 8, 2043/100]" and "S" -> -3.1339...
  static double? _degrees(String? value, String? ref, String negativeSide) {
    if (value == null) return null;
    var text = value.trim();
    if (text.startsWith('[')) text = text.substring(1);
    if (text.endsWith(']')) text = text.substring(0, text.length - 1);
    final parts = text.split(',');
    if (parts.isEmpty || parts.length > 3) return null;

    var total = 0.0;
    var divisor = 1.0;
    for (final part in parts) {
      final number = _number(part.trim());
      if (number == null) return null;
      total += number / divisor;
      divisor *= 60;
    }
    if (total.isNaN || total.isInfinite) return null;

    final side = (ref ?? '').trim().toUpperCase();
    return side.startsWith(negativeSide) ? -total : total;
  }

  // "12", "2043/100" or "3.5"
  static double? _number(String text) {
    if (text.isEmpty) return null;
    final slash = text.indexOf('/');
    if (slash < 0) return double.tryParse(text);
    final top = double.tryParse(text.substring(0, slash));
    final bottom = double.tryParse(text.substring(slash + 1));
    if (top == null || bottom == null || bottom == 0) return null;
    return top / bottom;
  }

  // ---------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------

  // "Image Make" -> "Image", "GPS GPSLatitude" -> "GPS", "JPEGThumbnail" -> ""
  static String _groupOf(String tag) {
    final space = tag.indexOf(' ');
    return space < 0 ? '' : tag.substring(0, space);
  }

  // "Image Make" -> "Make", "JPEGThumbnail" -> "JPEGThumbnail"
  static String _nameOf(String tag) {
    final space = tag.indexOf(' ');
    return space < 0 ? tag : tag.substring(space + 1);
  }

  // "ExposureBiasValue" -> "Exposure Bias Value"
  static String _humanize(String name) {
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final ch = name[i];
      if (i > 0 && _isUpper(ch)) {
        final prev = name[i - 1];
        if (_isLower(prev) || _isDigit(prev)) buffer.write(' ');
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  static bool _isUpper(String ch) => ch.toUpperCase() == ch && ch.toLowerCase() != ch;
  static bool _isLower(String ch) => ch.toLowerCase() == ch && ch.toUpperCase() != ch;
  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
    return '${kb.toStringAsFixed(1)} KB';
  }
}
