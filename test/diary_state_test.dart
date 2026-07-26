import 'package:flutter_application_1/core/network/network_failure.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';
import 'package:flutter_application_1/features/diary/providers/diary_provider.dart';
import 'package:flutter_test/flutter_test.dart';

DailyDiaryDto emptyDiary(DateTime date) => DailyDiaryDto(
      date: date,
      totalCaloriesConsumed: 0,
      targetCalories: 2000,
      breakfast: const [],
      lunch: const [],
      dinner: const [],
      snacks: const [],
    );

void main() {
  final date = DateTime.utc(2026, 7, 26);

  group('failure to status mapping', () {
    test('401 maps to unauthorized regardless of cache', () {
      expect(
        diaryStatusFor(UnauthorizedFailure(), hasCache: true),
        DiaryStatus.unauthorized,
      );
      expect(
        diaryStatusFor(UnauthorizedFailure(), hasCache: false),
        DiaryStatus.unauthorized,
      );
    });

    test('429 maps to rateLimited', () {
      expect(
        diaryStatusFor(RateLimitFailure(), hasCache: true),
        DiaryStatus.rateLimited,
      );
    });

    test('a timeout maps to timeout, not offline', () {
      expect(
        diaryStatusFor(TimeoutFailure(), hasCache: true),
        DiaryStatus.timeout,
      );
    });

    test('a connectivity failure maps to cachedOffline only when a cache exists', () {
      expect(
        diaryStatusFor(NetworkUnreachableFailure(), hasCache: true),
        DiaryStatus.cachedOffline,
      );

      // Claiming "offline, showing saved data" with nothing saved would be a lie.
      expect(
        diaryStatusFor(NetworkUnreachableFailure(), hasCache: false),
        DiaryStatus.serverError,
      );
    });

    test('5xx maps to serverError even when a cache exists', () {
      // The critical case: a backend outage must never be reported as "offline".
      expect(
        diaryStatusFor(ServerFailure(status: 500), hasCache: true),
        DiaryStatus.serverError,
      );
      expect(
        diaryStatusFor(ColdStartFailure(status: 503), hasCache: true),
        DiaryStatus.serverError,
      );
    });
  });

  group('DiaryState semantics', () {
    test('a successful empty response is success-like and carries no message', () {
      final state = DiaryState<DailyDiaryDto>(
        status: DiaryStatus.empty,
        data: emptyDiary(date),
      );

      expect(state.isSuccess, isTrue);
      expect(state.isShowingStaleData, isFalse);
      expect(state.message, isNull);
      expect(state.canRetry, isFalse);
    });

    test('an empty server response does not fall back to stale cache', () {
      final cached = DailyDiaryDto(
        date: date,
        totalCaloriesConsumed: 500,
        targetCalories: 2000,
        breakfast: [
          MealItemDto(
            id: 1,
            foodId: 1,
            foodName: 'Phở',
            quantity: 1,
            calories: 500,
            mealType: 'Breakfast',
          ),
        ],
        lunch: const [],
        dinner: const [],
        snacks: const [],
      );

      final state = DiaryState<DailyDiaryDto>(
        status: DiaryStatus.empty,
        data: emptyDiary(date),
        cachedData: cached,
      );

      // displayData prefers fresh data, so deleted meals do not reappear.
      expect(state.displayData!.totalCaloriesConsumed, 0);
      expect(state.isShowingStaleData, isFalse);
    });

    test('a server error carries the cache separately and admits it is stale', () {
      final state = DiaryState<DailyDiaryDto>(
        status: DiaryStatus.serverError,
        cachedData: emptyDiary(date),
        failure: ServerFailure(status: 500),
      );

      expect(state.isSuccess, isFalse);
      expect(state.isShowingStaleData, isTrue);
      expect(state.displayData, isNotNull);
      expect(state.message, contains('Máy chủ đang gặp sự cố'));
      // Explicitly not the offline wording.
      expect(state.message, isNot(contains('ngoại tuyến')));
    });

    test('offline wording is used only for a genuine connectivity failure', () {
      final state = DiaryState<DailyDiaryDto>(
        status: DiaryStatus.cachedOffline,
        cachedData: emptyDiary(date),
        failure: NetworkUnreachableFailure(),
      );

      expect(state.message, contains('Không có kết nối'));
      expect(state.isShowingStaleData, isTrue);
    });

    test('unauthorized offers no retry', () {
      final state = DiaryState<DailyDiaryDto>(
        status: DiaryStatus.unauthorized,
        failure: UnauthorizedFailure(),
      );

      // Retrying without re-authenticating just loops.
      expect(state.canRetry, isFalse);
      expect(state.message, contains('đăng nhập lại'));
    });

    test('recoverable statuses offer a retry', () {
      for (final status in [
        DiaryStatus.cachedOffline,
        DiaryStatus.timeout,
        DiaryStatus.rateLimited,
        DiaryStatus.serverError,
      ]) {
        final state = DiaryState<DailyDiaryDto>(status: status);
        expect(state.canRetry, isTrue, reason: '$status should be retryable');
      }
    });

    test('timeout wording distinguishes with-cache from without-cache', () {
      final withCache = DiaryState<DailyDiaryDto>(
        status: DiaryStatus.timeout,
        cachedData: emptyDiary(date),
      );
      final withoutCache = DiaryState<DailyDiaryDto>(status: DiaryStatus.timeout);

      expect(withCache.message, contains('Đang hiển thị dữ liệu đã lưu'));
      expect(withoutCache.message, contains('Vui lòng thử lại'));
    });

    test('weekly stats states behave identically', () {
      final state = DiaryState<List<DailyStatDto>>(
        status: DiaryStatus.serverError,
        cachedData: [DailyStatDto(date: date, caloriesConsumed: 100)],
        failure: ServerFailure(status: 502),
      );

      expect(state.isShowingStaleData, isTrue);
      expect(state.displayData, hasLength(1));
      expect(state.canRetry, isTrue);
    });
  });
}
