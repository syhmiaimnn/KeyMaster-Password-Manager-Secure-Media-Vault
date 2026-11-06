import 'package:client/metadata_analysis.dart';
import 'package:client/metadata_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

// What the EXIF reader typically returns for a phone photo (name -> text).
const Map<String, String> phoneTags = <String, String>{
  'Image Make': 'vivo',
  'Image Model': 'vivo 1901',
  'Image Software': 'PD1901',
  'Image DateTime': '2026:10:21 14:03:22',
  'Image Orientation': 'Horizontal (normal)',
  'Image ExifOffset': '230',
  'Image GPSInfo': '600',
  'GPS GPSLatitudeRef': 'N',
  'GPS GPSLatitude': '[3, 8, 2043/100]',
  'GPS GPSLongitudeRef': 'E',
  'GPS GPSLongitude': '[101, 41, 7]',
  'GPS GPSAltitude': '45',
  'EXIF ExposureTime': '1/120',
  'EXIF FNumber': '9/5',
  'EXIF ISOSpeedRatings': '100',
  'EXIF DateTimeOriginal': '2026:10:21 14:03:22',
  'EXIF ExifVersion': '0220',
  'EXIF MakerNote': '',
  'Thumbnail Compression': 'JPEG (old-style)',
  'JPEGThumbnail': '',
};

const FileScan cleanScan = FileScan(
  format: ImageFormat.jpeg,
  blocks: <HiddenBlock>[],
  understood: true,
);

FileScan scanWith(List<HiddenBlock> blocks) {
  return FileScan(format: ImageFormat.jpeg, blocks: blocks, understood: true);
}

HiddenBlock block(String label, int bytes, {bool sensitive = true}) {
  return HiddenBlock(label: label, bytes: bytes, sensitive: sensitive);
}

MetadataAnalysis build(Map<String, String> tags, [FileScan scan = cleanScan]) {
  return MetadataAnalysis.build(tags, scan);
}

void main() {
  group('categoryOf', () {
    test('puts each field in the right kind', () {
      const expected = <String, MetaCategory>{
        'GPS GPSLatitude': MetaCategory.location,
        'GPS GPSVersionID': MetaCategory.location,
        'Image Make': MetaCategory.device,
        'Image Model': MetaCategory.device,
        'Image Software': MetaCategory.device,
        'EXIF LensModel': MetaCategory.device,
        'EXIF MakerNote': MetaCategory.device,
        'MakerNote Tag 0x0001': MetaCategory.device,
        'Image DateTime': MetaCategory.time,
        'EXIF DateTimeOriginal': MetaCategory.time,
        'EXIF SubSecTimeOriginal': MetaCategory.time,
        'EXIF OffsetTime': MetaCategory.time,
        'Image Artist': MetaCategory.owner,
        'Image Copyright': MetaCategory.owner,
        'Image ImageDescription': MetaCategory.owner,
        'EXIF UserComment': MetaCategory.owner,
        'EXIF BodySerialNumber': MetaCategory.owner,
        'EXIF LensSerialNumber': MetaCategory.owner,
        'EXIF CameraOwnerName': MetaCategory.owner,
        'EXIF ImageUniqueID': MetaCategory.owner,
        'Image XPTitle': MetaCategory.owner,
        'Thumbnail Compression': MetaCategory.thumbnail,
        'Thumbnail DateTime': MetaCategory.thumbnail,
        'JPEGThumbnail': MetaCategory.thumbnail,
        'EXIF ExposureTime': MetaCategory.settings,
        'EXIF FNumber': MetaCategory.settings,
        'EXIF ISOSpeedRatings': MetaCategory.settings,
        'EXIF Flash': MetaCategory.settings,
        'EXIF FocalLength': MetaCategory.settings,
        'EXIF WhiteBalance': MetaCategory.settings,
        'Image Orientation': MetaCategory.image,
        'EXIF ExifImageWidth': MetaCategory.image,
        'EXIF ColorSpace': MetaCategory.image,
        'EXIF FlashPixVersion': MetaCategory.image,
        'EXIF ExifVersion': MetaCategory.image,
        'Image XResolution': MetaCategory.image,
        'Interoperability InteroperabilityIndex': MetaCategory.image,
        'Image XPosition': MetaCategory.other,
        'EXIF Tag 0xA431': MetaCategory.other,
        '#XMP': MetaCategory.other,
        '#EXIF': MetaCategory.other,
        '#Embedded thumbnail': MetaCategory.thumbnail,
      };
      expected.forEach((tag, category) {
        expect(MetadataAnalysis.categoryOf(tag), category, reason: tag);
      });
    });

    test('settings and image details are harmless, everything else is not', () {
      expect(MetadataAnalysis.isSensitive(MetaCategory.settings), isFalse);
      expect(MetadataAnalysis.isSensitive(MetaCategory.image), isFalse);
      for (final category in [
        MetaCategory.location,
        MetaCategory.owner,
        MetaCategory.time,
        MetaCategory.device,
        MetaCategory.thumbnail,
        MetaCategory.other,
      ]) {
        expect(MetadataAnalysis.isSensitive(category), isTrue, reason: '$category');
      }
    });

    test('pointer fields are not data', () {
      for (final tag in [
        'Image ExifOffset',
        'Image GPSInfo',
        'EXIF InteroperabilityOffset',
        'Thumbnail JPEGInterchangeFormat',
        'Thumbnail JPEGInterchangeFormatLength',
      ]) {
        expect(MetadataAnalysis.isStructural(tag), isTrue, reason: tag);
      }
      expect(MetadataAnalysis.isStructural('Image Make'), isFalse);
      expect(MetadataAnalysis.isStructural('GPS GPSLatitude'), isFalse);
    });

    test('titles and risk levels', () {
      expect(MetadataAnalysis.titleOf(MetaCategory.location), 'Location');
      expect(MetadataAnalysis.titleOf(MetaCategory.owner), 'Identity and notes');
      expect(MetadataAnalysis.riskOf(MetaCategory.location), ExposureLevel.high);
      expect(MetadataAnalysis.riskOf(MetaCategory.time), ExposureLevel.medium);
      expect(MetadataAnalysis.riskOf(MetaCategory.settings), ExposureLevel.low);
      expect(MetadataAnalysis.riskOf(MetaCategory.image), ExposureLevel.none);
    });
  });

  group('labels and values', () {
    test('labelOf gives readable names', () {
      expect(MetadataAnalysis.labelOf('GPS GPSLatitude'), 'Latitude');
      expect(MetadataAnalysis.labelOf('Image Make'), 'Camera make');
      expect(MetadataAnalysis.labelOf('EXIF DateTimeOriginal'), 'Date taken');
      expect(MetadataAnalysis.labelOf('EXIF ShutterSpeedValue'), 'Shutter Speed Value');
      expect(MetadataAnalysis.labelOf('Thumbnail XResolution'), 'Thumbnail: Horizontal resolution');
      expect(MetadataAnalysis.labelOf('MakerNote Tag 0x0001'), 'Maker note: Tag 0x0001');
      expect(MetadataAnalysis.labelOf('JPEGThumbnail'), 'Thumbnail picture');
      expect(MetadataAnalysis.labelOf('#XMP'), 'XMP');
    });

    test('displayValue', () {
      expect(MetadataAnalysis.displayValue(''), '(binary data)');
      expect(MetadataAnalysis.displayValue('   '), '(binary data)');
      expect(MetadataAnalysis.displayValue('1/120'), '1/120');
      expect(MetadataAnalysis.displayValue('2026:10:21 14:03:22'), '2026-10-21 14:03:22');
      expect(MetadataAnalysis.displayValue('2026:10:21'), '2026-10-21');
      expect(MetadataAnalysis.displayValue('Hello\u0000World'), 'Hello World');
      final long = MetadataAnalysis.displayValue('x' * 200);
      expect(long.length, 120);
      expect(long.endsWith('...'), isTrue);
    });
  });

  group('decodeCoordinates', () {
    test('turns degrees, minutes and seconds into decimal degrees', () {
      expect(
        MetadataAnalysis.decodeCoordinates(phoneTags),
        '3.1390° N, 101.6853° E',
      );
    });

    test('S and W give the other sides, in any letter case', () {
      expect(
        MetadataAnalysis.decodeCoordinates(const {
          'GPS GPSLatitude': '[3, 8, 2043/100]',
          'GPS GPSLatitudeRef': 's',
          'GPS GPSLongitude': '[101, 41, 7]',
          'GPS GPSLongitudeRef': 'W',
        }),
        '3.1390° S, 101.6853° W',
      );
    });

    test('accepts one, two or three parts', () {
      expect(
        MetadataAnalysis.decodeCoordinates(const {
          'GPS GPSLatitude': '12.5',
          'GPS GPSLatitudeRef': 'N',
          'GPS GPSLongitude': '[3, 30]',
          'GPS GPSLongitudeRef': 'E',
        }),
        '12.5000° N, 3.5000° E',
      );
    });

    test('returns null for missing, broken or impossible values', () {
      expect(MetadataAnalysis.decodeCoordinates(const {}), isNull);
      expect(
        MetadataAnalysis.decodeCoordinates(const {
          'GPS GPSLatitude': '[3, 8, 2043/100]',
          'GPS GPSLatitudeRef': 'N',
        }),
        isNull,
      );
      expect(
        MetadataAnalysis.decodeCoordinates(const {
          'GPS GPSLatitude': 'abc',
          'GPS GPSLatitudeRef': 'N',
          'GPS GPSLongitude': '[1, 2, 3]',
          'GPS GPSLongitudeRef': 'E',
        }),
        isNull,
      );
      expect(
        MetadataAnalysis.decodeCoordinates(const {
          'GPS GPSLatitude': '[95, 0, 0]',
          'GPS GPSLatitudeRef': 'N',
          'GPS GPSLongitude': '[1, 2, 3]',
          'GPS GPSLongitudeRef': 'E',
        }),
        isNull,
      );
      expect(
        MetadataAnalysis.decodeCoordinates(const {
          'GPS GPSLatitude': '[3, 8, 5/0]',
          'GPS GPSLatitudeRef': 'N',
          'GPS GPSLongitude': '[1, 2, 3]',
          'GPS GPSLongitudeRef': 'E',
        }),
        isNull,
      );
    });
  });

  group('a phone photo before cleaning', () {
    final analysis = build(phoneTags, scanWith([block(BlockLabel.exif, 3000)]));

    test('lists the fields by kind and skips pointer fields', () {
      expect(analysis.hiddenFieldCount, 18);
      expect(analysis.countIn(MetaCategory.location), 5);
      expect(analysis.countIn(MetaCategory.device), 4);
      expect(analysis.countIn(MetaCategory.time), 2);
      expect(analysis.countIn(MetaCategory.image), 2);
      expect(analysis.countIn(MetaCategory.settings), 3);
      expect(analysis.countIn(MetaCategory.thumbnail), 2);
      expect(analysis.countIn(MetaCategory.owner), 0);
      expect(analysis.countIn(MetaCategory.other), 0);
      expect(analysis.findings.any((f) => f.tag == 'Image GPSInfo'), isFalse);
      expect(analysis.sensitiveCount, 13);
      expect(analysis.categoriesPresent, [
        MetaCategory.location,
        MetaCategory.time,
        MetaCategory.device,
        MetaCategory.thumbnail,
        MetaCategory.settings,
        MetaCategory.image,
      ]);
    });

    test('flags and score', () {
      expect(analysis.hasLocation, isTrue);
      expect(analysis.hasDevice, isTrue);
      expect(analysis.hasTime, isTrue);
      expect(analysis.hasThumbnail, isTrue);
      expect(analysis.hasOwner, isFalse);
      expect(analysis.isClean, isFalse);
      expect(analysis.exposureScore, 80); // 45 + 15 + 12 + 8
      expect(analysis.privacyScore, 20);
      expect(analysis.level, ExposureLevel.high);
      expect(analysis.coordinates, '3.1390° N, 101.6853° E');
      expect(analysis.format, ImageFormat.jpeg);
      expect(analysis.structureChecked, isTrue);
    });

    test('summaries', () {
      expect(analysis.summaryFor(MetaCategory.location), '3.1390° N, 101.6853° E');
      expect(analysis.summaryFor(MetaCategory.time), 'Taken 2026-10-21 14:03:22');
      expect(analysis.summaryFor(MetaCategory.device), 'vivo · vivo 1901 · PD1901');
      expect(analysis.summaryFor(MetaCategory.thumbnail), startsWith('A small copy'));
      expect(
        analysis.summaryFor(MetaCategory.settings),
        '3 camera settings such as exposure, ISO and focal length.',
      );
      expect(
        analysis.summaryFor(MetaCategory.image),
        '2 technical fields such as size and orientation.',
      );
      expect(analysis.summaryFor(MetaCategory.owner), '');
    });

    test('the location summary falls back when the position cannot be decoded', () {
      final odd = build(const {'GPS GPSLatitudeRef': 'N'});
      expect(odd.coordinates, isNull);
      expect(odd.summaryFor(MetaCategory.location), 'GPS location data is stored in the file.');
    });

    test('the stored names hold no values and no duplicates', () {
      final names = analysis.storedNames();
      expect(names.length, 18);
      expect(names, contains('GPS GPSLatitude'));
      expect(names, isNot(contains('Image GPSInfo')));
      expect(names.any((n) => n.contains('101')), isFalse);
      expect(analysis.storedNames(limit: 5).length, 5);

      final twice = build(const {}, scanWith([block(BlockLabel.xmp, 10), block(BlockLabel.xmp, 20)]));
      expect(twice.findings.length, 2);
      expect(twice.storedNames(), ['#XMP']);
    });

    test('groupStored builds the Privacy report lists', () {
      final grouped = MetadataAnalysis.groupStored(const [
        'GPS GPSLatitude',
        'GPS GPSLongitude',
        'GPS GPSLatitude',
        'Image Make',
        '#XMP',
        '#Embedded thumbnail',
        'EXIF ExposureTime',
      ]);
      expect(grouped[MetaCategory.location], ['Latitude', 'Longitude']);
      expect(grouped[MetaCategory.device], ['Camera make']);
      expect(grouped[MetaCategory.other], ['XMP']);
      expect(grouped[MetaCategory.thumbnail], ['Embedded thumbnail']);
      expect(grouped[MetaCategory.settings], ['Exposure time']);
      expect(grouped.length, 5);
      expect(MetadataAnalysis.groupStored(const <String>[]), isEmpty);
    });
  });

  group('the saved copy after cleaning', () {
    test('nothing left means a perfect score', () {
      final after = build(const {});
      expect(after.isClean, isTrue);
      expect(after.hiddenFieldCount, 0);
      expect(after.exposureScore, 0);
      expect(after.privacyScore, 100);
      expect(after.level, ExposureLevel.none);
      expect(after.categoriesPresent, isEmpty);
      expect(after.coordinates, isNull);
      expect(MetadataAnalysis.empty.isClean, isTrue);
    });

    test('harmless technical fields do not make it unclean', () {
      final after = build(const {
        'Image Orientation': 'Horizontal (normal)',
        'EXIF ColorSpace': 'sRGB',
      });
      expect(after.isClean, isTrue);
      expect(after.hiddenFieldCount, 2);
      expect(after.exposureScore, 0);
      expect(after.residualText, '');
    });

    test('a GPS field left behind makes it unclean', () {
      final after = build(const {'GPS GPSLatitudeRef': 'N'});
      expect(after.isClean, isFalse);
      expect(after.hasLocation, isTrue);
      expect(after.residualText, 'a GPS location');
    });

    test('other fields left behind are counted', () {
      final after = build(const {'Image Make': 'vivo', 'Image Model': 'x'});
      expect(after.isClean, isFalse);
      expect(after.residualText, '2 hidden fields');
    });

    test('a block left behind makes it unclean', () {
      final after = build(const {}, scanWith([block(BlockLabel.xmp, 300)]));
      expect(after.isClean, isFalse);
      expect(after.residualText, 'XMP');
      expect(after.exposureScore, 5);
      expect(after.privacyScore, 95);
      expect(after.level, ExposureLevel.low);
      expect(after.summaryFor(MetaCategory.other), 'XMP');
    });

    test('an EXIF block that cannot be read is treated as unclean', () {
      final after = build(const {}, scanWith([block(BlockLabel.exif, 200)]));
      expect(after.isClean, isFalse);
      expect(after.residualText, 'Unreadable EXIF data');
      // A tiny EXIF header with nothing in it is fine.
      expect(build(const {}, scanWith([block(BlockLabel.exif, 16)])).isClean, isTrue);
      // An EXIF block whose fields were read is judged by those fields.
      expect(
        build(const {'Image ExifOffset': '8'}, scanWith([block(BlockLabel.exif, 200)])).isClean,
        isTrue,
      );
    });

    test('an embedded thumbnail block counts as a thumbnail', () {
      final after = build(const {}, scanWith([block(BlockLabel.thumbnail, 400)]));
      expect(after.hasThumbnail, isTrue);
      expect(after.exposureScore, 8);
      expect(after.isClean, isFalse);
    });

    test('blocks marked harmless are ignored', () {
      final after = build(const {}, scanWith([block('ICC', 500, sensitive: false)]));
      expect(after.isClean, isTrue);
      expect(after.hiddenFieldCount, 0);
    });

    test('data after the picture is other hidden data', () {
      final after = build(const {}, scanWith([block(BlockLabel.trailing, 5000)]));
      expect(after.isClean, isFalse);
      expect(after.countIn(MetaCategory.other), 1);
    });
  });

  group('score and level', () {
    int exposure(Map<String, String> tags) => build(tags).exposureScore;

    test('each kind adds its own weight', () {
      expect(exposure(const {'GPS GPSLatitudeRef': 'N'}), 45);
      expect(exposure(const {'Image Artist': 'x'}), 15);
      expect(exposure(const {'Image DateTime': '2026:01:01 00:00:00'}), 15);
      expect(exposure(const {'Image Make': 'a'}), 12);
      expect(exposure(const {'JPEGThumbnail': ''}), 8);
      expect(exposure(const {'EXIF Tag 0xA431': '1'}), 5);
      expect(exposure(const {'EXIF ExposureTime': '1/50'}), 0);
    });

    test('many fields of one kind count once', () {
      expect(
        exposure(const {
          'GPS GPSLatitudeRef': 'N',
          'GPS GPSLatitude': '[1, 2, 3]',
          'GPS GPSAltitude': '4',
        }),
        45,
      );
    });

    test('everything at once is 100', () {
      final all = build(const {
        'GPS GPSLatitudeRef': 'N',
        'Image Artist': 'x',
        'Image DateTime': '2026:01:01 00:00:00',
        'Image Make': 'a',
        'JPEGThumbnail': '',
        'EXIF Tag 0xA431': '1',
      });
      expect(all.exposureScore, 100);
      expect(all.privacyScore, 0);
      expect(all.level, ExposureLevel.high);
    });

    test('level boundaries', () {
      ExposureLevel levelOf(Map<String, String> tags) => build(tags).level;
      const device = {'Image Make': 'a'};
      expect(levelOf(const {}), ExposureLevel.none);
      expect(levelOf(device), ExposureLevel.low); // 12
      expect(levelOf({...device, 'JPEGThumbnail': ''}), ExposureLevel.low); // 20
      expect(
        levelOf({...device, 'JPEGThumbnail': '', 'EXIF Tag 0xA431': '1'}),
        ExposureLevel.medium, // 25
      );
      expect(
        levelOf(const {'GPS GPSLatitudeRef': 'N', 'Image Make': 'a'}),
        ExposureLevel.medium, // 57
      );
      expect(
        levelOf(const {'GPS GPSLatitudeRef': 'N', 'Image Artist': 'x'}),
        ExposureLevel.high, // 60
      );
    });
  });
}
