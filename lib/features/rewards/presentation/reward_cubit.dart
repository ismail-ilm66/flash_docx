import 'package:equatable/equatable.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

enum RewardStatus { idle, loading, granted, cancelled, offline }

class RewardState extends Equatable {
  const RewardState({this.status = RewardStatus.idle, this.feature});
  final RewardStatus status;
  final PremiumFeature? feature;

  @override
  List<Object?> get props => [status, feature];
}

@injectable
class RewardCubit extends Cubit<RewardState> {
  RewardCubit(this._gate) : super(const RewardState());

  final RewardGate _gate;

  void preload() => _gate.preload();

  Future<RewardResult> unlock(PremiumFeature f) async {
    emit(RewardState(status: RewardStatus.loading, feature: f));
    final r = await _gate.unlock(f);
    emit(
      RewardState(
        status: switch (r) {
          RewardResult.granted => RewardStatus.granted,
          RewardResult.cancelled => RewardStatus.cancelled,
          RewardResult.offline => RewardStatus.offline,
        },
        feature: f,
      ),
    );
    return r;
  }

  void reset() => emit(const RewardState());
}
