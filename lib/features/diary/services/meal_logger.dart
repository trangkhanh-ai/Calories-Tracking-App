import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/network_failure.dart';
import '../models/diary_dto.dart';
import '../models/food_entry.dart';
import 'diary_api_service.dart';
import 'local_storage_service.dart';

/// Outcome of a server-first meal write.
sealed class LogMealOutcome {
  const LogMealOutcome();
}

/// The backend accepted the meal. Authoritative regardless of what the local
/// cache did afterwards.
class LogMealSuccess extends LogMealOutcome {
  const LogMealSuccess({this.diary, this.cacheWriteFailed = false});

  /// Server diary for the day, when the backend returned one.
  final DailyDiaryDto? diary;

  /// True when the backend saved but the local cache write did not. The user
  /// is still told the save succeeded, because it did.
  final bool cacheWriteFailed;
}

/// The backend rejected or never received the meal. Nothing was persisted.
class LogMealFailure extends LogMealOutcome {
  const LogMealFailure(this.failure);

  final NetworkFailure failure;

  String get message => failure.message;
}

/// Single implementation of the server-first write contract, shared by the
/// scanner and food-search screens so they cannot drift apart.
///
/// Order matters: the backend is written first and its success is what the user
/// is told about. The local cache is a best-effort mirror updated afterwards.
class MealLogger {
  const MealLogger({
    required this.diaryApi,
    required this.storage,
  });

  final DiaryApiService diaryApi;
  final LocalStorageService storage;

  /// Logs a meal.
  ///
  /// The POST is never retried automatically — no endpoint carries an
  /// idempotency key, so a retry could double-log. The caller keeps the form
  /// open on failure so the user can correct and resubmit deliberately.
  Future<LogMealOutcome> log({
    required LogMealRequest request,
    required FoodEntry cacheEntry,
  }) async {
    final DailyDiaryDto? diary;

    try {
      diary = await diaryApi.logMeal(request);
    } on DioException catch (error) {
      // Nothing is written locally: a local "success" after a server failure is
      // exactly the false confirmation this flow exists to prevent.
      return LogMealFailure(NetworkFailure.fromDioException(error));
    }

    // Past this point the meal IS saved. A cache problem must not be reported
    // as a failure, or the user retries and double-logs.
    var cacheWriteFailed = false;
    try {
      await storage.addEntry(cacheEntry);
    } catch (error) {
      cacheWriteFailed = true;
      if (kDebugMode) {
        // Type only — never the token, request body, or image data.
        debugPrint('Diary cache write failed after a successful server save: '
            '${error.runtimeType}');
      }
    }

    return LogMealSuccess(diary: diary, cacheWriteFailed: cacheWriteFailed);
  }
}
