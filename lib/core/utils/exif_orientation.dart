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
