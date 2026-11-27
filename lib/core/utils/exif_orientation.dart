import 'dart:io';
import 'dart:typed_data';

/// Reads the EXIF orientation tag (0x0112) of a JPEG, looking only at the
/// first 64 KB. Returns 1 (upright) when the file isn't a JPEG, has no EXIF,
/// or the tag is missing or out of range (round 4, P0-1).
///
/// 1 normal · 2 mirror H · 3 rotate 180 · 4 mirror V · 5 transpose ·
/// 6 rotate 90 CW · 7 transverse · 8 rotate 90 CCW
int readJpegOrientation(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    return jpegOrientationFromBytes(f.readSync(64 * 1024));
  } catch (_) {
    return 1;
  } finally {
    f?.closeSync();
  }
}

/// As [readJpegOrientation], from the start of a JPEG file.
int jpegOrientationFromBytes(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return 1;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return 1;
    final marker = b[i + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return 1; // image data: no EXIF before it
    final len = (b[i + 2] << 8) | b[i + 3];
    final start = i + 4;
    if (marker == 0xE1 && start + 6 <= b.length && _isExifHeader(b, start)) {
      return _orientationFromTiff(b, start + 6, start + len - 2);
    }
    i += 2 + len;
  }
  return 1;
}

bool _isExifHeader(Uint8List b, int at) =>
    b[at] == 0x45 && b[at + 1] == 0x78 && b[at + 2] == 0x69 && b[at + 3] == 0x66 && b[at + 4] == 0 && b[at + 5] == 0;

int _orientationFromTiff(Uint8List b, int tiff, int end) {
  if (tiff + 8 > b.length) return 1;
  final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
  final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
  if (!little && !big) return 1;
  int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  int u32(int o) => little
      ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
      : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > b.length) return 1;
  final count = u16(ifd);
  for (var e = 0; e < count; e++) {
    final entry = ifd + 2 + e * 12;
    if (entry + 12 > b.length || entry + 12 > end + 2) return 1;
    if (u16(entry) == 0x0112) {
      final v = u16(entry + 8);
      return v >= 1 && v <= 8 ? v : 1;
    }
  }
  return 1;
}

/// Orientations 5–8 swap width and height.
bool orientationSwapsAxes(int o) => o >= 5 && o <= 8;

/// Round 11c, B2: sets the EXIF orientation tag of the JPEG at [path]
/// without decoding it: the value is changed in place when the tag is
/// there; otherwise a minimal EXIF block holding only the tag is put in
/// front (the file is copied, never re-encoded). Readers take the first
/// EXIF block. False when [path] isn't a JPEG.
bool writeJpegOrientation(String path, int orientation) {
  assert(orientation >= 1 && orientation <= 8, 'EXIF orientation is 1..8');
  final file = File(path);
  final raf = file.openSync(mode: FileMode.append);
  try {
    raf.setPositionSync(0);
    final head = raf.readSync(64 * 1024);
    final at = _orientationValueOffset(head);
    if (at == -2) return false;
    if (at >= 0) {
      raf
        ..setPositionSync(at)
        ..writeFromSync(_tiffLittle(head, at) ? [orientation, 0] : [0, orientation]);
      return true;
    }
  } finally {
    raf.closeSync();
  }
  // No tag: a new APP1 "Exif" block in front (TIFF little-endian, IFD0
  // with one SHORT entry), the rest of the file unchanged.
  final bytes = file.readAsBytesSync();
  final tiff = <int>[
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // header, IFD0 at 8
    0x01, 0x00, // 1 entry
    0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, orientation, 0x00, 0x00, 0x00, // 0x0112 SHORT ×1
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  final payload = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff];
  final len = payload.length + 2;
  final out = BytesBuilder(copy: false)
    ..add(const [0xFF, 0xD8, 0xFF, 0xE1])
    ..add([len >> 8, len & 0xFF])
    ..add(payload)
    ..add(Uint8List.sublistView(bytes, 2));
  final tmp = File('$path.exif.part')..writeAsBytesSync(out.takeBytes(), flush: true);
  tmp.renameSync(path);
  return true;
}

/// Where the orientation tag's value sits in [b] (a JPEG's start), or −1
/// when there is no tag, −2 when [b] isn't a JPEG.
int _orientationValueOffset(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return -2;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return -1;
    final marker = b[i + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return -1;
    final len = (b[i + 2] << 8) | b[i + 3];
    final start = i + 4;
    if (marker == 0xE1 && start + 6 <= b.length && _isExifHeader(b, start)) {
      final tiff = start + 6;
      if (tiff + 8 > b.length) return -1;
      final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
      final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
      if (!little && !big) return -1;
      int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
      int u32(int o) => little
          ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
          : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      final ifd = tiff + u32(tiff + 4);
      if (ifd + 2 > b.length) return -1;
      for (var e = 0; e < u16(ifd); e++) {
        final entry = ifd + 2 + e * 12;
        if (entry + 12 > b.length) return -1;
        if (u16(entry) == 0x0112 && u16(entry + 2) == 3) return entry + 8;
      }
      return -1;
    }
    i += 2 + len;
  }
  return -1;
}

/// The byte order of the TIFF block that holds offset [at].
bool _tiffLittle(Uint8List b, int at) {
  var i = 2;
  while (i + 4 <= b.length) {
    final len = (b[i + 2] << 8) | b[i + 3];
    if (b[i + 1] == 0xE1 && _isExifHeader(b, i + 4) && at < i + 2 + len) return b[i + 10] == 0x49;
    i += 2 + len;
  }
  return true;
}
