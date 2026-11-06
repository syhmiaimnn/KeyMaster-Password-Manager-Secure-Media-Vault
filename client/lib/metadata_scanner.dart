import 'dart:typed_data';

// Reads the structure of an image file and lists the blocks of hidden data
// in it (EXIF, XMP, IPTC, comments, embedded thumbnails and so on).
//
// No Flutter code here, so it can be unit tested and run in a background
// isolate. It only looks at the file layout. It never decodes the picture.
// The EXIF fields themselves are read by the `exif` package, and
// `metadata_analysis.dart` puts both results together.

/// The picture formats this scanner knows.
enum ImageFormat { jpeg, png, webp, gif, heic, unknown }

/// The names of the blocks, shared by the scanner and the report screens.
class BlockLabel {
  static const String exif = 'EXIF';
  static const String xmp = 'XMP';
  static const String iptc = 'IPTC';
  static const String comment = 'Comment';
  static const String credentials = 'Content Credentials';
  static const String thumbnail = 'Embedded thumbnail';
  static const String extraImages = 'Extra embedded images';
  static const String textNote = 'Text note';
  static const String timeStamp = 'Time stamp';
  static const String trailing = 'Data after the picture';
  static const String other = 'Other hidden data';
}

/// One block of hidden data found inside a file.
class HiddenBlock {
  /// One of the [BlockLabel] names.
  final String label;

  /// Size of the block in bytes.
  final int bytes;

  /// True when the block can identify the owner, the place or the time.
  final bool sensitive;

  const HiddenBlock({
    required this.label,
    required this.bytes,
    required this.sensitive,
  });
}

/// What the scanner found in one file.
class FileScan {
  final ImageFormat format;

  /// Every block that is not part of the picture itself. Harmless parts such
  /// as the JFIF header or a colour profile are not listed.
  final List<HiddenBlock> blocks;

  /// False when the file could not be read from start to end, or when this
  /// format is not understood. The list of blocks may then be incomplete.
  final bool understood;

  const FileScan({
    required this.format,
    required this.blocks,
    required this.understood,
  });

  static const FileScan unknown = FileScan(
    format: ImageFormat.unknown,
    blocks: <HiddenBlock>[],
    understood: false,
  );

  bool get hasSensitive => blocks.any((block) => block.sensitive);

  /// Total size of all blocks with this label.
  int bytesOf(String label) {
    var total = 0;
    for (final block in blocks) {
      if (block.label == label) total += block.bytes;
    }
    return total;
  }

  bool has(String label) => blocks.any((block) => block.label == label);
}

class MetadataScanner {
  const MetadataScanner._();

  // Identifiers that start the data of a segment or chunk.
  static final List<int> _jfif = 'JFIF\x00'.codeUnits;
  static final List<int> _jfxx = 'JFXX\x00'.codeUnits;
  static final List<int> _exifId = 'Exif\x00\x00'.codeUnits;
  static final List<int> _xmpId = 'http://ns.adobe.com/xap/1.0/\x00'.codeUnits;
  static final List<int> _xmpExtId =
      'http://ns.adobe.com/xmp/extension/\x00'.codeUnits;
  static final List<int> _iccId = 'ICC_PROFILE\x00'.codeUnits;
  static final List<int> _mpfId = 'MPF\x00'.codeUnits;
  static final List<int> _photoshopId = 'Photoshop 3.0\x00'.codeUnits;
  static final List<int> _adobeId = 'Adobe'.codeUnits;
  static final List<int> _jumbfId = 'JP'.codeUnits;
  static final List<int> _pngKeywordXmp = 'XML:com.adobe.xmp'.codeUnits;

  // A few stray bytes after the end of a JPEG are not a hidden block.
  static const int _trailingTolerance = 16;

  /// Looks at the start of [bytes] to find the format, then lists its hidden
  /// blocks. Never throws: a file it cannot read gives `understood: false`.
  static FileScan scan(Uint8List bytes) {
    try {
      final format = detectFormat(bytes);
      if (format == ImageFormat.jpeg) return _scanJpeg(bytes);
      if (format == ImageFormat.png) return _scanPng(bytes);
      if (format == ImageFormat.webp) return _scanWebp(bytes);
      if (format == ImageFormat.gif || format == ImageFormat.heic) {
        // Not read here. The photo is still re-encoded before it is saved.
        return FileScan(
          format: format,
          blocks: const <HiddenBlock>[],
          understood: false,
        );
      }
      return FileScan.unknown;
    } catch (_) {
      return FileScan.unknown;
    }
  }

  static ImageFormat detectFormat(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return ImageFormat.jpeg;
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return ImageFormat.png;
    }
    if (b.length >= 12 &&
        _matches(b, 0, 'RIFF'.codeUnits, b.length) &&
        _matches(b, 8, 'WEBP'.codeUnits, b.length)) {
      return ImageFormat.webp;
    }
    if (b.length >= 6 && _matches(b, 0, 'GIF8'.codeUnits, b.length)) {
      return ImageFormat.gif;
    }
    if (b.length >= 12 && _matches(b, 4, 'ftyp'.codeUnits, b.length)) {
      return ImageFormat.heic;
    }
    return ImageFormat.unknown;
  }

  // ---------------------------------------------------------------
  // JPEG
  // ---------------------------------------------------------------

  static FileScan _scanJpeg(Uint8List b) {
    final blocks = <HiddenBlock>[];
    final length = b.length;
    var understood = true;
    var pos = 2; // after the start marker FF D8

    while (pos + 1 < length) {
      if (b[pos] != 0xFF) {
        // Picture data (between two markers). Skip to the next 0xFF.
        pos++;
        continue;
      }
      final marker = b[pos + 1];
      if (marker == 0xFF) {
        pos++; // padding byte
        continue;
      }
      if (marker == 0x00 ||
          marker == 0x01 ||
          marker == 0xD8 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        pos += 2; // stuffed byte, restart marker or other marker without data
        continue;
      }
      if (marker == 0xD9) {
        // End of the picture. Anything after this is extra data.
        final trailing = length - (pos + 2);
        if (trailing > _trailingTolerance) {
          blocks.add(HiddenBlock(
            label: BlockLabel.trailing,
            bytes: trailing,
            sensitive: true,
          ));
        }
        return FileScan(
          format: ImageFormat.jpeg,
          blocks: blocks,
          understood: understood,
        );
      }

      // A segment with a length
      if (pos + 4 > length) {
        understood = false;
        break;
      }
      final segmentLength = (b[pos + 2] << 8) | b[pos + 3];
      if (segmentLength < 2) {
        understood = false;
        break;
      }
      final dataStart = pos + 4;
      var dataEnd = pos + 2 + segmentLength;
      if (dataEnd > length) {
        dataEnd = length;
        understood = false;
      }
      _classifyJpegSegment(marker, b, dataStart, dataEnd, blocks);
      if (!understood) break;
      pos += 2 + segmentLength;
    }

    // The loop ended without an end marker: the file is cut off or damaged.
    return FileScan(
      format: ImageFormat.jpeg,
      blocks: blocks,
      understood: false,
    );
  }

  static void _classifyJpegSegment(
    int marker,
    Uint8List b,
    int start,
    int end,
    List<HiddenBlock> out,
  ) {
    final size = end - start;
    void add(String label, {bool sensitive = true}) {
      out.add(HiddenBlock(label: label, bytes: size, sensitive: sensitive));
    }

    switch (marker) {
      case 0xE0: // APP0
        if (_matches(b, start, _jfif, end)) return; // plain header
        if (_matches(b, start, _jfxx, end)) {
          add(BlockLabel.thumbnail);
          return;
        }
        add(BlockLabel.other);
      case 0xE1: // APP1
        if (_matches(b, start, _exifId, end)) {
          add(BlockLabel.exif);
        } else if (_matches(b, start, _xmpId, end) ||
            _matches(b, start, _xmpExtId, end)) {
          add(BlockLabel.xmp);
        } else {
          add(BlockLabel.other);
        }
      case 0xE2: // APP2
        if (_matches(b, start, _iccId, end)) return; // colour profile
        if (_matches(b, start, _mpfId, end)) {
          add(BlockLabel.extraImages);
        } else {
          add(BlockLabel.other);
        }
      case 0xEB: // APP11
        if (_matches(b, start, _jumbfId, end)) {
          add(BlockLabel.credentials);
        } else {
          add(BlockLabel.other);
        }
      case 0xED: // APP13
        if (_matches(b, start, _photoshopId, end)) {
          add(BlockLabel.iptc);
        } else {
          add(BlockLabel.other);
        }
      case 0xEE: // APP14
        if (_matches(b, start, _adobeId, end)) return; // colour transform flag
        add(BlockLabel.other);
      case 0xFE: // COM
        add(BlockLabel.comment);
      default:
        // APP3 to APP10, APP12 and APP15 are all vendor data.
        if (marker >= 0xE3 && marker <= 0xEF) add(BlockLabel.other);
      // Every other marker is part of the picture (tables, size, scan).
    }
  }

  // ---------------------------------------------------------------
  // PNG
  // ---------------------------------------------------------------

  // Chunks that only describe how to draw the picture.
  static const Set<String> _pngHarmless = <String>{
    'IHDR',
    'PLTE',
    'IDAT',
    'IEND',
    'tRNS',
    'gAMA',
    'cHRM',
    'sRGB',
    'iCCP',
    'sBIT',
    'bKGD',
    'hIST',
    'pHYs',
    'sPLT',
    'cICP',
    'mDCV',
    'cLLI',
    'acTL',
    'fcTL',
    'fdAT',
    'oFFs',
    'sTER',
  };

  static FileScan _scanPng(Uint8List b) {
    final blocks = <HiddenBlock>[];
    final length = b.length;
    var pos = 8; // after the signature

    while (pos + 8 <= length) {
      final size = _u32be(b, pos);
      final type = String.fromCharCodes(b.sublist(pos + 4, pos + 8));
      final dataStart = pos + 8;
      final dataEnd = dataStart + size;
      if (dataEnd + 4 > length) {
        // The chunk runs past the end of the file.
        return FileScan(format: ImageFormat.png, blocks: blocks, understood: false);
      }

      if (type == 'IEND') {
        return FileScan(format: ImageFormat.png, blocks: blocks, understood: true);
      }
      if (type == 'eXIf') {
        blocks.add(HiddenBlock(
          label: BlockLabel.exif,
          bytes: size,
          sensitive: true,
        ));
      } else if (type == 'tEXt' || type == 'zTXt' || type == 'iTXt') {
        final isXmp = _matches(b, dataStart, _pngKeywordXmp, dataEnd);
        blocks.add(HiddenBlock(
          label: isXmp ? BlockLabel.xmp : BlockLabel.textNote,
          bytes: size,
          sensitive: true,
        ));
      } else if (type == 'tIME') {
        blocks.add(HiddenBlock(
          label: BlockLabel.timeStamp,
          bytes: size,
          sensitive: true,
        ));
      } else if (type == 'caBX') {
        blocks.add(HiddenBlock(
          label: BlockLabel.credentials,
          bytes: size,
          sensitive: true,
        ));
      } else if (!_pngHarmless.contains(type)) {
        blocks.add(HiddenBlock(
          label: BlockLabel.other,
          bytes: size,
          sensitive: true,
        ));
      }
      pos = dataEnd + 4; // skip the checksum
    }

    // No IEND chunk: cut off or damaged.
    return FileScan(format: ImageFormat.png, blocks: blocks, understood: false);
  }

  // ---------------------------------------------------------------
  // WebP
  // ---------------------------------------------------------------

  static const Set<String> _webpHarmless = <String>{
    'VP8 ',
    'VP8L',
    'VP8X',
    'ALPH',
    'ANIM',
    'ANMF',
    'ICCP',
  };

  static FileScan _scanWebp(Uint8List b) {
    final blocks = <HiddenBlock>[];
    final length = b.length;
    var pos = 12; // after "RIFF", the size and "WEBP"

    while (pos + 8 <= length) {
      final type = String.fromCharCodes(b.sublist(pos, pos + 4));
      final size = _u32le(b, pos + 4);
      final dataStart = pos + 8;
      final dataEnd = dataStart + size;
      if (dataEnd > length) {
        return FileScan(format: ImageFormat.webp, blocks: blocks, understood: false);
      }

      if (type == 'EXIF') {
        blocks.add(HiddenBlock(
          label: BlockLabel.exif,
          bytes: size,
          sensitive: true,
        ));
      } else if (type == 'XMP ') {
        blocks.add(HiddenBlock(
          label: BlockLabel.xmp,
          bytes: size,
          sensitive: true,
        ));
      } else if (!_webpHarmless.contains(type)) {
        blocks.add(HiddenBlock(
          label: BlockLabel.other,
          bytes: size,
          sensitive: true,
        ));
      }
      pos = dataEnd + (size.isOdd ? 1 : 0); // chunks are padded to even sizes
    }

    return FileScan(format: ImageFormat.webp, blocks: blocks, understood: true);
  }

  // ---------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------

  /// True when [b] holds [pattern] at [start] and the pattern ends before [end].
  static bool _matches(Uint8List b, int start, List<int> pattern, int end) {
    if (start < 0 || start + pattern.length > end || end > b.length) {
      return false;
    }
    for (var i = 0; i < pattern.length; i++) {
      if (b[start + i] != pattern[i]) return false;
    }
    return true;
  }

  static int _u32be(Uint8List b, int pos) {
    return (b[pos] << 24) | (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
  }

  static int _u32le(Uint8List b, int pos) {
    return b[pos] | (b[pos + 1] << 8) | (b[pos + 2] << 16) | (b[pos + 3] << 24);
  }
}
