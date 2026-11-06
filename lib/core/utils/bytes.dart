/// "438 KB", "1.2 MB". Decimal units, like upload forms; KB rounds down so
/// a file never reads as bigger than the limit it fits under.
String formatBytes(int bytes) {
  if (bytes >= 1000000) {
    final mb = (bytes / 1e6).toStringAsFixed(1);
    return '${mb.endsWith('.0') ? mb.substring(0, mb.length - 2) : mb} MB';
  }
  return '${bytes ~/ 1000} KB';
}
