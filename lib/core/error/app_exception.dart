import 'package:flash_dox/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

/// Wraps an async call and converts thrown errors into a [Failure].
Future<Either<Failure, T>> guard<T>(
  Future<T> Function() body, {
  Failure Function(Object error, StackTrace stack)? onError,
}) async {
  try {
    return Right(await body());
  } catch (e, s) {
    return Left(onError?.call(e, s) ?? UnknownFailure(e.toString()));
  }
}
