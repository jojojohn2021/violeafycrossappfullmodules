/// Centralized Application Exception Classes
abstract class AppException implements Exception {
  final String message;
  final int? statusCode;

  const AppException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.statusCode});
}

class AuthException extends AppException {
  const AuthException(super.message, {super.statusCode});
}

class ServerException extends AppException {
  const ServerException(super.message, {super.statusCode});
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.statusCode});
}
