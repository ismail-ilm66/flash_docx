import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ConnectivityService {
  ConnectivityService(this._connectivity);

  final Connectivity _connectivity;

  Future<bool> get isOnline async {
    final r = await _connectivity.checkConnectivity();
    return r.any((c) => c != ConnectivityResult.none);
  }
}
