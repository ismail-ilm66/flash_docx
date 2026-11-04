import 'package:equatable/equatable.dart';

/// Every recoverable error in the app is modelled as a [Failure] and carried
/// through `Either<Failure, T>` so blocs can show the right message without
/// try/catch in the presentation layer.
sealed class Failure extends Equatable {
  const Failure([this.message]);

  final String? message;

  @override
  List<Object?> get props => [message];
}

class StorageFailure extends Failure {
  const StorageFailure([super.message]);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure([super.message]);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message]);
}

class ImageProcessingFailure extends Failure {
  const ImageProcessingFailure([super.message]);
}

class OcrFailure extends Failure {
  const OcrFailure([super.message]);
}

class PdfFailure extends Failure {
  const PdfFailure([super.message]);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message]);
}

class CancelledFailure extends Failure {
  const CancelledFailure([super.message]);
}

class OfflineFailure extends Failure {
  const OfflineFailure([super.message]);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message]);
}
