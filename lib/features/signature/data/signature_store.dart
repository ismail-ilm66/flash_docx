import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// My signature (feature 4): one transparent PNG in app storage. It never
/// leaves the phone. Placing it copies it into the document, so deleting it
/// here doesn't change pages already signed.
@lazySingleton
class SignatureStore {
  SignatureStore(this._files, this._prefs) {
    saved.value = File(path).existsSync();
  }

  final FileStore _files;
  final PrefsService _prefs;

  /// Whether a signature is saved; Settings and Sign listen to it.
  final ValueNotifier<bool> saved = ValueNotifier(false);

  String get path => p.join(_files.root.path, 'signature', 'signature.png');

  InkColor get defaultInk => InkColor.values.where((i) => i.name == _prefs.signatureInk).firstOrNull ?? InkColor.blue;

  Future<void> save(Uint8List png, {required InkColor ink}) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(png, flush: true);
    await _prefs.setSignatureInk(ink.name);
    saved.value = true;
  }

  Future<void> delete() async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
    saved.value = false;
  }

  /// A copy of the signature (or [png] bytes, for a date stamp) inside the
  /// document's folder, for a new overlay.
  Future<String> adoptInto(String documentId, {Uint8List? png}) async {
    final out = p.join(_files.docDir(documentId).path, 'overlays', '${newId()}.png');
    await Directory(p.dirname(out)).create(recursive: true);
    if (png != null) {
      await File(out).writeAsBytes(png, flush: true);
    } else {
      await File(path).copy(out);
    }
    return out;
  }
}
