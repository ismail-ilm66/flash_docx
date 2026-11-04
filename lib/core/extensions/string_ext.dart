extension StringX on String {
  String get fileSafe => replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  bool get isBlank => trim().isEmpty;
}
