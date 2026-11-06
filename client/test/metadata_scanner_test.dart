import 'dart:typed_data';

import 'package:client/metadata_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------
// Helpers that build tiny image files byte by byte
// ---------------------------------------------------------------

List<int> ascii(String text) => text.codeUnits;

/// A JPEG segment: FF, marker, length (2 bytes, counts itself), data.
List<int> segment(int marker, List<int> data) {
  final length = data.length + 2;
  return [0xFF, marker, length >> 8, length & 0xFF, ...data];
}

List<int> jfif() => segment(0xE0, [...ascii('JFIF\x00'), 1, 1, 0, 0, 1, 0, 1, 0, 0]);

List<int> exif(int payload) =>
    segment(0xE1, [...ascii('Exif\x00\x00'), ...List<int>.filled(payload, 7)]);

List<int> xmp(int payload) => segment(0xE1, [
      ...ascii('http://ns.adobe.com/xap/1.0/\x00'),
      ...List<int>.filled(payload, 60),
    ]);

List<int> icc() =>
    segment(0xE2, [...ascii('ICC_PROFILE\x00'), 1, 1, ...List<int>.filled(20, 9)]);

List<int> comment(String text) => segment(0xFE, ascii(text));

List<int> iptc() =>
    segment(0xED, [...ascii('Photoshop 3.0\x00'), ...ascii('8BIM'), 4, 4]);

List<int> mpf() => segment(0xE2, [...ascii('MPF\x00'), 1, 2, 3, 4, 5]);

List<int> credentials() => segment(0xEB, [...ascii('JP'), 0, 0, 1, 2, 3]);

List<int> jfxx() => segment(0xE0, [...ascii('JFXX\x00'), 0x10, 1, 2, 3]);

List<int> vendor(int marker) => segment(marker, [1, 2, 3]);

List<int> quantTable() => segment(0xDB, List<int>.filled(65, 1));

/// Start of scan, then a little picture data with a stuffed byte (FF 00), a
/// restart marker (FF D0) and a padding byte before another restart marker.
List<int> scanData() => [
      0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 0, 63, 0, // scan header
      0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD0, 0x78, 0xFF, 0xFF, 0xD1, 0x9A,
    ];

Uint8List jpeg(List<List<int>> segments, {List<int> tail = const []}) {
  return Uint8List.fromList([
    0xFF, 0xD8, // start of image
    for (final s in segments) ...s,
    ...scanData(),
    0xFF, 0xD9, // end of image
    ...tail,
  ]);
}

List<int> u32be(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> u32le(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> pngChunk(String type, List<int> data) =>
    [...u32be(data.length), ...ascii(type), ...data, 0, 0, 0, 0];

Uint8List png(List<List<int>> chunks, {bool end = true}) {
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...pngChunk('IHDR', List<int>.filled(13, 1)),
    for (final c in chunks) ...c,
    ...pngChunk('IDAT', [1, 2, 3, 4]),
    if (end) ...pngChunk('IEND', const <int>[]),
  ]);
}

List<int> webpChunk(String type, List<int> data) => [
      ...ascii(type),
      ...u32le(data.length),
      ...data,
      if (data.length.isOdd) 0, // padding
    ];

Uint8List webp(List<List<int>> chunks) {
  final body = [
    ...ascii('WEBP'),
    for (final c in chunks) ...c,
  ];
  return Uint8List.fromList([...ascii('RIFF'), ...u32le(body.length), ...body]);
}

List<String> labels(FileScan scan) => scan.blocks.map((b) => b.label).toList();

void main() {
  group('detectFormat', () {
    test('recognises each format by its first bytes', () {
      expect(MetadataScanner.detectFormat(jpeg([jfif()])), ImageFormat.jpeg);
      expect(MetadataScanner.detectFormat(png([])), ImageFormat.png);
      expect(MetadataScanner.detectFormat(webp([webpChunk('VP8 ', [1, 2])])), ImageFormat.webp);
      expect(
        MetadataScanner.detectFormat(Uint8List.fromList([...ascii('GIF89a'), 1, 0, 1, 0])),
        ImageFormat.gif,
      );
      expect(
        MetadataScanner.detectFormat(
          Uint8List.fromList([0, 0, 0, 24, ...ascii('ftypheic'), 0, 0, 0, 0]),
        ),
        ImageFormat.heic,
      );
      expect(MetadataScanner.detectFormat(Uint8List.fromList([1, 2, 3, 4, 5])), ImageFormat.unknown);
      expect(MetadataScanner.detectFormat(Uint8List(0)), ImageFormat.unknown);
    });
  });

  group('JPEG', () {
    test('a plain file (JFIF header, colour profile, tables) has nothing hidden', () {
      final scan = MetadataScanner.scan(jpeg([jfif(), icc(), quantTable()]));
      expect(scan.format, ImageFormat.jpeg);
      expect(scan.blocks, isEmpty);
      expect(scan.understood, isTrue);
      expect(scan.hasSensitive, isFalse);
    });

    test('finds EXIF and reports its size', () {
      final scan = MetadataScanner.scan(jpeg([jfif(), exif(100)]));
      expect(labels(scan), [BlockLabel.exif]);
      expect(scan.blocks.single.bytes, 106); // 6 bytes of "Exif" + 100
      expect(scan.blocks.single.sensitive, isTrue);
      expect(scan.bytesOf(BlockLabel.exif), 106);
      expect(scan.has(BlockLabel.xmp), isFalse);
    });

    test('finds every kind of hidden block, in file order', () {
      final scan = MetadataScanner.scan(jpeg([
        jfif(),
        exif(10),
        xmp(20),
        mpf(),
        credentials(),
        iptc(),
        comment('shot by Luqman'),
        jfxx(),
        vendor(0xE5),
        icc(),
        quantTable(),
      ]));
      expect(labels(scan), [
        BlockLabel.exif,
        BlockLabel.xmp,
        BlockLabel.extraImages,
        BlockLabel.credentials,
        BlockLabel.iptc,
        BlockLabel.comment,
        BlockLabel.thumbnail,
        BlockLabel.other,
      ]);
      expect(scan.blocks.every((b) => b.sensitive), isTrue);
      expect(scan.blocks[5].bytes, 'shot by Luqman'.length);
      expect(scan.understood, isTrue);
    });

    test('an extended XMP segment counts as XMP', () {
      final extended = segment(0xE1, [
        ...ascii('http://ns.adobe.com/xmp/extension/\x00'),
        1,
        2,
        3,
      ]);
      final scan = MetadataScanner.scan(jpeg([extended]));
      expect(labels(scan), [BlockLabel.xmp]);
    });

    test('an unknown APP1 segment is other hidden data', () {
      final scan = MetadataScanner.scan(jpeg([segment(0xE1, [...ascii('Mystery'), 1])]));
      expect(labels(scan), [BlockLabel.other]);
    });

    test('Adobe colour flag is harmless, other APP14 data is not', () {
      expect(MetadataScanner.scan(jpeg([segment(0xEE, [...ascii('Adobe'), 0, 100, 0, 0, 0, 0, 1])])).blocks, isEmpty);
      expect(labels(MetadataScanner.scan(jpeg([segment(0xEE, [1, 2, 3])]))), [BlockLabel.other]);
    });

    test('stuffed bytes, restart markers and padding in the picture data do not confuse it', () {
      // scanData() contains FF 00, FF D0 and FF FF D1. A COM segment after the
      // picture data (as in progressive files) must still be found.
      final bytes = Uint8List.fromList([
        0xFF, 0xD8,
        ...jfif(),
        ...scanData(),
        ...comment('late'),
        0xFF, 0xD9,
      ]);
      final scan = MetadataScanner.scan(bytes);
      expect(labels(scan), [BlockLabel.comment]);
      expect(scan.understood, isTrue);
    });

    test('a few stray bytes after the end are ignored, a lot of data is not', () {
      final small = MetadataScanner.scan(jpeg([jfif()], tail: List<int>.filled(16, 0)));
      expect(small.blocks, isEmpty);
      final big = MetadataScanner.scan(jpeg([jfif()], tail: List<int>.filled(500, 1)));
      expect(labels(big), [BlockLabel.trailing]);
      expect(big.blocks.single.bytes, 500);
    });

    test('a file cut off in the middle is reported as not fully understood', () {
      final whole = jpeg([jfif(), exif(100)]);
      final cut = Uint8List.sublistView(whole, 0, 60);
      final scan = MetadataScanner.scan(cut);
      expect(scan.understood, isFalse);
      expect(labels(scan), [BlockLabel.exif]); // what was visible is still reported
    });

    test('a file with no end marker is reported as not fully understood', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, ...jfif(), ...quantTable()]);
      final scan = MetadataScanner.scan(bytes);
      expect(scan.understood, isFalse);
      expect(scan.blocks, isEmpty);
    });

    test('a segment length below 2 stops the scan without an exception', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x01, 9, 9, 9]);
      final scan = MetadataScanner.scan(bytes);
      expect(scan.understood, isFalse);
    });
  });

  group('PNG', () {
    test('a plain file has nothing hidden', () {
      final scan = MetadataScanner.scan(png([
        pngChunk('gAMA', [0, 0, 0xB1, 0x8F]),
        pngChunk('pHYs', List<int>.filled(9, 1)),
        pngChunk('iCCP', [...ascii('icc'), 0, 0, 1, 2]),
      ]));
      expect(scan.format, ImageFormat.png);
      expect(scan.blocks, isEmpty);
      expect(scan.understood, isTrue);
    });

    test('finds EXIF, text notes, XMP, a time stamp and unknown chunks', () {
      final scan = MetadataScanner.scan(png([
        pngChunk('eXIf', List<int>.filled(30, 1)),
        pngChunk('tEXt', [...ascii('Software'), 0, ...ascii('Phone')]),
        pngChunk('iTXt', [...ascii('XML:com.adobe.xmp'), 0, 0, 0, 0, 0, 60, 60]),
        pngChunk('tIME', [7, 234, 10, 21, 14, 3, 22]),
        pngChunk('caBX', [1, 2, 3]),
        pngChunk('zzZz', [1]),
      ]));
      expect(labels(scan), [
        BlockLabel.exif,
        BlockLabel.textNote,
        BlockLabel.xmp,
        BlockLabel.timeStamp,
        BlockLabel.credentials,
        BlockLabel.other,
      ]);
      expect(scan.blocks.first.bytes, 30);
      expect(scan.understood, isTrue);
    });

    test('a file with no IEND chunk is not fully understood', () {
      final scan = MetadataScanner.scan(png([pngChunk('tEXt', [...ascii('A'), 0, 66])], end: false));
      expect(scan.understood, isFalse);
      expect(labels(scan), [BlockLabel.textNote]);
    });

    test('a chunk longer than the file does not crash', () {
      final bytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...u32be(5000), ...ascii('tEXt'), 1, 2, 3,
      ]);
      final scan = MetadataScanner.scan(bytes);
      expect(scan.understood, isFalse);
    });
  });

  group('WebP', () {
    test('a plain file has nothing hidden', () {
      final scan = MetadataScanner.scan(webp([
        webpChunk('VP8X', List<int>.filled(10, 0)),
        webpChunk('ICCP', [1, 2, 3]),
        webpChunk('VP8 ', [1, 2, 3, 4]),
      ]));
      expect(scan.format, ImageFormat.webp);
      expect(scan.blocks, isEmpty);
      expect(scan.understood, isTrue);
    });

    test('finds EXIF and XMP, including after an odd-sized chunk', () {
      final scan = MetadataScanner.scan(webp([
        webpChunk('VP8X', List<int>.filled(10, 0)),
        webpChunk('VP8 ', [1, 2, 3, 4, 5]), // odd size, padded to even
        webpChunk('EXIF', List<int>.filled(20, 1)),
        webpChunk('XMP ', List<int>.filled(7, 2)),
        webpChunk('ABCD', [1]),
      ]));
      expect(labels(scan), [BlockLabel.exif, BlockLabel.xmp, BlockLabel.other]);
      expect(scan.blocks[0].bytes, 20);
      expect(scan.blocks[1].bytes, 7);
      expect(scan.understood, isTrue);
    });

    test('a chunk longer than the file is not fully understood', () {
      final bytes = Uint8List.fromList([
        ...ascii('RIFF'), ...u32le(20), ...ascii('WEBP'),
        ...ascii('EXIF'), ...u32le(9999), 1, 2,
      ]);
      expect(MetadataScanner.scan(bytes).understood, isFalse);
    });
  });

  group('other input', () {
    test('GIF and HEIC are not read, but are not an error', () {
      final gif = MetadataScanner.scan(Uint8List.fromList([...ascii('GIF89a'), 1, 0, 1, 0, 0, 0]));
      expect(gif.format, ImageFormat.gif);
      expect(gif.understood, isFalse);
      expect(gif.blocks, isEmpty);

      final heic = MetadataScanner.scan(
        Uint8List.fromList([0, 0, 0, 24, ...ascii('ftypheic'), 0, 0, 0, 0]),
      );
      expect(heic.format, ImageFormat.heic);
      expect(heic.understood, isFalse);
    });

    test('random or empty bytes never throw', () {
      expect(MetadataScanner.scan(Uint8List(0)).format, ImageFormat.unknown);
      expect(MetadataScanner.scan(Uint8List.fromList([0xFF])).format, ImageFormat.unknown);
      expect(MetadataScanner.scan(Uint8List.fromList([0xFF, 0xD8, 0xFF])).understood, isFalse);
      final noise = Uint8List.fromList(List<int>.generate(300, (i) => (i * 37 + 11) & 0xFF));
      expect(() => MetadataScanner.scan(noise), returnsNormally);
    });
  });
}
