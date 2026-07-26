import 'package:dio/dio.dart';
import 'package:flutter_application_1/core/network/network_failure.dart';
import 'package:flutter_application_1/features/diary/models/diary_dto.dart';
import 'package:flutter_application_1/features/diary/models/food_entry.dart';
import 'package:flutter_application_1/features/diary/services/diary_api_service.dart';
import 'package:flutter_application_1/features/diary/services/local_storage_service.dart';
import 'package:flutter_application_1/features/diary/services/meal_logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and can fail with a chosen status.
class FakeDiaryApi implements DiaryApiService {
  FakeDiaryApi({this.failWithStatus, this.failWithType});

  final int? failWithStatus;
  final DioExceptionType? failWithType;

  int logMealCallCount = 0;

  @override
  Future<DailyDiaryDto?> logMeal(LogMealRequest request) async {
    logMealCallCount++;

    if (failWithStatus != null || failWithType != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/diary'),
        type: failWithType ?? DioExceptionType.badResponse,
        response: failWithStatus == null
            ? null
            : Response(
                requestOptions: RequestOptions(path: '/diary'),
                statusCode: failWithStatus,
              ),
      );
    }

    return DailyDiaryDto(
      date: request.date,
      totalCaloriesConsumed: 300,
      targetCalories: 2000,
      breakfast: [
        MealItemDto(
          // A real server-assigned id, not a client-generated one.
          id: 4242,
          foodId: 7,
          foodName: request.foodName,
          quantity: request.quantity,
          calories: 300,
          mealType: request.mealType,
        ),
      ],
      lunch: const [],
      dinner: const [],
      snacks: const [],
    );
  }

  @override
  Future<DailyDiaryDto> getDailyDiary(DateTime date) => throw UnimplementedError();

  @override
  Future<List<DailyStatDto>> getStats(DateTime startDate, DateTime endDate) =>
      throw UnimplementedError();
}

/// Local cache that can be told to fail its write.
class FakeStorage implements LocalStorageService {
  FakeStorage({this.failOnAdd = false});

  final bool failOnAdd;
  final List<FoodEntry> entries = [];

  @override
  Future<void> addEntry(FoodEntry entry) async {
    if (failOnAdd) {
      throw StateError('SharedPreferences unavailable');
    }
    entries.add(entry);
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final date = DateTime.utc(2026, 7, 26);

  LogMealRequest buildRequest() => LogMealRequest(
        foodName: 'Phở bò',
        caloriesPer100g: 150,
        quantity: 200,
        mealType: 'Breakfast',
        date: date,
      );

  FoodEntry buildEntry() => FoodEntry(
        id: 'local-1',
        name: 'Phở bò',
        calories: 300,
        proteinG: 10,
        carbsG: 40,
        fatG: 5,
        date: date,
        mealType: 'Breakfast',
      );

  group('server failure', () {
    test('nothing is written locally when the server rejects the meal', () async {
      final storage = FakeStorage();
      final logger = MealLogger(diaryApi: FakeDiaryApi(failWithStatus: 500), storage: storage);

      final outcome = await logger.log(request: buildRequest(), cacheEntry: buildEntry());

      expect(outcome, isA<LogMealFailure>());

      // The whole point: no false local success after a server failure.
      expect(storage.entries, isEmpty);
    });

    test('the POST is never retried automatically', () async {
      final api = FakeDiaryApi(failWithType: DioExceptionType.connectionError);
      final logger = MealLogger(diaryApi: api, storage: FakeStorage());

      await logger.log(request: buildRequest(), cacheEntry: buildEntry());

      // Retrying a non-idempotent write could double-log the meal.
      expect(api.logMealCallCount, 1);
    });

    test('failure classes are distinguished', () async {
      final cases = <int, Type>{
        400: ValidationFailure,
        401: UnauthorizedFailure,
        429: RateLimitFailure,
        500: ServerFailure,
        503: ColdStartFailure,
      };

      for (final entry in cases.entries) {
        final logger = MealLogger(
          diaryApi: FakeDiaryApi(failWithStatus: entry.key),
          storage: FakeStorage(),
        );

        final outcome = await logger.log(request: buildRequest(), cacheEntry: buildEntry());

        final failure = (outcome as LogMealFailure).failure;
        expect(failure.runtimeType, entry.value, reason: 'status ${entry.key}');
      }
    });

    test('a timeout is reported as a timeout, not as a generic error', () async {
      final logger = MealLogger(
        diaryApi: FakeDiaryApi(failWithType: DioExceptionType.receiveTimeout),
        storage: FakeStorage(),
      );

      final outcome = await logger.log(request: buildRequest(), cacheEntry: buildEntry());

      expect((outcome as LogMealFailure).failure, isA<TimeoutFailure>());
    });

    test('the user-facing message never contains a raw exception', () async {
      final logger = MealLogger(
        diaryApi: FakeDiaryApi(failWithStatus: 500),
        storage: FakeStorage(),
      );

      final outcome = await logger.log(request: buildRequest(), cacheEntry: buildEntry()) as LogMealFailure;

      expect(outcome.message, isNot(contains('DioException')));
      expect(outcome.message, isNot(contains('Exception')));
    });
  });

  group('server success', () {
    test('server success plus cache success reports success', () async {
      final storage = FakeStorage();
      final logger = MealLogger(diaryApi: FakeDiaryApi(), storage: storage);

      final outcome = await logger.log(request: buildRequest(), cacheEntry: buildEntry());

      expect(outcome, isA<LogMealSuccess>());
      expect((outcome as LogMealSuccess).cacheWriteFailed, isFalse);
      expect(storage.entries, hasLength(1));
    });

    test('server success with a failed cache write still reports success', () async {
      final logger = MealLogger(
        diaryApi: FakeDiaryApi(),
        storage: FakeStorage(failOnAdd: true),
      );

      final outcome = await logger.log(request: buildRequest(), cacheEntry: buildEntry());

      // The meal IS saved. Reporting failure here would push the user into a
      // retry that double-logs.
      expect(outcome, isA<LogMealSuccess>());
      expect((outcome as LogMealSuccess).cacheWriteFailed, isTrue);
    });

    test('the authoritative server diary is returned for the caller to adopt', () async {
      final logger = MealLogger(diaryApi: FakeDiaryApi(), storage: FakeStorage());

      final outcome = await logger.log(
        request: buildRequest(),
        cacheEntry: buildEntry(),
      ) as LogMealSuccess;

      expect(outcome.diary, isNotNull);
      // Server-assigned id, not the client's 'local-1'.
      expect(outcome.diary!.breakfast.single.id, 4242);
    });

    test('the server is called exactly once on success', () async {
      final api = FakeDiaryApi();
      final logger = MealLogger(diaryApi: api, storage: FakeStorage());

      await logger.log(request: buildRequest(), cacheEntry: buildEntry());

      expect(api.logMealCallCount, 1);
    });
  });
}
