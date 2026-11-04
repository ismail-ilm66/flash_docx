import 'package:flash_dox/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

abstract interface class UseCase<T, P> {
  Future<Either<Failure, T>> call(P params);
}

abstract interface class StreamUseCase<T, P> {
  Stream<T> call(P params);
}

/// Marker for use cases without parameters.
class NoParams {
  const NoParams();
}
