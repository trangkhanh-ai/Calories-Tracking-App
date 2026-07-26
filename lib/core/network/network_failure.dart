import 'package:dio/dio.dart';

/// Structured, user-presentable failure model shared by every API call.
///
/// Replaces the previous pattern of surfacing `e.toString()` or a bare
/// `Exception('Lỗi: $e')`, which leaked backend internals into the UI and made
/// failures impossible to branch on.
sealed class NetworkFailure implements Exception {
  const NetworkFailure({
    required this.message,
    this.status,
    this.title,
    this.detail,
    this.traceId,
    this.retryAfter,
  });

  /// Vietnamese, user-facing. Safe to render directly.
  final String message;

  /// HTTP status when the server answered; null for transport failures.
  final int? status;

  /// RFC 7807 `title`, retained for diagnostics rather than display.
  final String? title;

  /// RFC 7807 `detail`. Never rendered raw — [message] is what the UI shows.
  final String? detail;

  /// RFC 7807 `traceId`, so a user report can be matched to a server log.
  final String? traceId;

  /// Parsed `Retry-After`, when the server supplied one.
  final Duration? retryAfter;

  /// Whether an automatic retry could plausibly succeed. Used by the retry
  /// interceptor; deliberately false for every 4xx.
  bool get isRetryable => false;

  @override
  String toString() => 'NetworkFailure($status): $message';

  /// Builds the right subtype from a Dio error, parsing ProblemDetails when the
  /// backend supplied one.
  factory NetworkFailure.fromDioException(DioException error) {
    final problem = ProblemDetails.tryParse(error.response?.data);
    final status = error.response?.statusCode;
    final retryAfter = _parseRetryAfter(error.response?.headers.value('retry-after'));

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return TimeoutFailure(problem: problem);

      case DioExceptionType.cancel:
        return const CancelledFailure();

      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (status == null) {
          return NetworkUnreachableFailure(problem: problem);
        }
        break;

      case DioExceptionType.badCertificate:
        return NetworkUnreachableFailure(problem: problem);

      case DioExceptionType.badResponse:
        break;
    }

    return NetworkFailure.fromStatus(status, problem: problem, retryAfter: retryAfter);
  }

  /// Maps a status code onto the failure hierarchy.
  factory NetworkFailure.fromStatus(
    int? status, {
    ProblemDetails? problem,
    Duration? retryAfter,
  }) {
    switch (status) {
      case 400:
        return ValidationFailure(problem: problem);
      case 401:
        return UnauthorizedFailure(problem: problem);
      case 403:
        return ForbiddenFailure(problem: problem);
      case 409:
        return ConflictFailure(problem: problem);
      case 413:
        return PayloadTooLargeFailure(problem: problem);
      case 415:
        return UnsupportedMediaFailure(problem: problem);
      case 429:
        return RateLimitFailure(problem: problem, retryAfter: retryAfter);
      case 502:
      case 503:
      case 504:
        return ColdStartFailure(status: status, problem: problem);
      default:
        if (status != null && status >= 500) {
          return ServerFailure(status: status, problem: problem);
        }
        return UnknownFailure(status: status, problem: problem);
    }
  }

  static Duration? _parseRetryAfter(String? raw) {
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }
}

/// Connect/receive/send deadline elapsed.
class TimeoutFailure extends NetworkFailure {
  TimeoutFailure({ProblemDetails? problem})
      : super(
          message: 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.',
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );

  @override
  bool get isRetryable => true;
}

/// No route to the server at all — offline, DNS failure, TLS failure.
class NetworkUnreachableFailure extends NetworkFailure {
  NetworkUnreachableFailure({ProblemDetails? problem})
      : super(
          message: 'Không có kết nối mạng. Vui lòng kiểm tra và thử lại.',
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );

  @override
  bool get isRetryable => true;
}

/// 502/503/504 — typically a Render instance waking from sleep.
class ColdStartFailure extends NetworkFailure {
  ColdStartFailure({super.status, ProblemDetails? problem})
      : super(
          message: 'Máy chủ đang khởi động. Vui lòng chờ khoảng 1 phút rồi thử lại.',
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );

  @override
  bool get isRetryable => true;
}

/// 401 — the session is gone. Never retried; the caller must re-authenticate.
class UnauthorizedFailure extends NetworkFailure {
  UnauthorizedFailure({ProblemDetails? problem})
      : super(
          message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          status: 401,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 403 — authenticated but not permitted.
class ForbiddenFailure extends NetworkFailure {
  ForbiddenFailure({ProblemDetails? problem})
      : super(
          message: 'Bạn không có quyền thực hiện thao tác này.',
          status: 403,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 400 — the request violated the contract. Shows the server's detail when it
/// is present, because backend validation messages are written for end users.
class ValidationFailure extends NetworkFailure {
  ValidationFailure({ProblemDetails? problem})
      : super(
          message: problem?.detail ?? 'Dữ liệu không hợp lệ. Vui lòng kiểm tra lại.',
          status: 400,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 409 — a uniqueness conflict.
class ConflictFailure extends NetworkFailure {
  ConflictFailure({ProblemDetails? problem})
      : super(
          message: problem?.detail ?? 'Dữ liệu đã tồn tại.',
          status: 409,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 413 — decoded payload above the server's 5 MB budget.
class PayloadTooLargeFailure extends NetworkFailure {
  PayloadTooLargeFailure({ProblemDetails? problem})
      : super(
          message: 'Ảnh quá lớn (giới hạn 5 MB sau khi giải mã). '
              'Vui lòng chọn hoặc chụp ảnh nhỏ hơn.',
          status: 413,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 415 — media type outside the JPEG/PNG/WebP allow-list.
class UnsupportedMediaFailure extends NetworkFailure {
  UnsupportedMediaFailure({ProblemDetails? problem})
      : super(
          message: 'Định dạng ảnh không được hỗ trợ. Chỉ chấp nhận JPEG, PNG hoặc WebP.',
          status: 415,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 429 — rate limited. Never retried automatically; that would deepen the hole.
class RateLimitFailure extends NetworkFailure {
  RateLimitFailure({ProblemDetails? problem, super.retryAfter})
      : super(
          message: retryAfter == null
              ? 'Bạn thao tác quá nhanh. Vui lòng chờ một lát rồi thử lại.'
              : 'Bạn thao tác quá nhanh. Vui lòng chờ ${retryAfter.inSeconds} giây rồi thử lại.',
          status: 429,
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// 5xx other than the cold-start trio.
class ServerFailure extends NetworkFailure {
  ServerFailure({super.status, ProblemDetails? problem})
      : super(
          message: 'Máy chủ gặp sự cố. Vui lòng thử lại sau.',
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// The request was cancelled by the caller — not an error to report.
class CancelledFailure extends NetworkFailure {
  const CancelledFailure() : super(message: 'Yêu cầu đã bị huỷ.');
}

/// Anything unclassified. The raw server text is deliberately not surfaced.
class UnknownFailure extends NetworkFailure {
  UnknownFailure({super.status, ProblemDetails? problem})
      : super(
          message: 'Đã xảy ra lỗi không xác định. Vui lòng thử lại.',
          title: problem?.title,
          detail: problem?.detail,
          traceId: problem?.traceId,
        );
}

/// Parsed RFC 7807 body. Exposed for construction only; the UI renders
/// [NetworkFailure.message], never these fields.
class ProblemDetails {
  const ProblemDetails({this.title, this.detail, this.traceId});

  final String? title;
  final String? detail;
  final String? traceId;

  static ProblemDetails? tryParse(dynamic data) {
    if (data is! Map) return null;

    String? asString(Object? value) => value is String && value.isNotEmpty ? value : null;

    return ProblemDetails(
      title: asString(data['title']),
      // Older endpoints used `message` or `error`; accept both so the model
      // works against a partially migrated backend.
      detail: asString(data['detail']) ?? asString(data['message']) ?? asString(data['error']),
      traceId: asString(data['traceId']),
    );
  }
}
