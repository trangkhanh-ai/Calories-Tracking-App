import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/network_failure.dart';
import '../../profile/services/profile_api_service.dart';
import '../models/diary_dto.dart';
import '../models/food_entry.dart';
import '../services/diary_api_service.dart';
import '../services/local_storage_service.dart';
import '../services/meal_logger.dart';

/// Outcome of a diary read.
///
/// Every value is reachable and distinct. In particular a 5xx maps to
/// [serverError], never [cachedOffline] — labelling a backend fault as
/// "offline" hides a real outage from the user.
enum DiaryStatus {
  loading,
  success,
  empty,
  cachedOffline,
  unauthorized,
  timeout,
  rateLimited,
  serverError,
}

/// Immutable result carrying the status and, separately, any stale cache.
///
/// Cache is exposed via [cachedData] + [isShowingStaleData] rather than being
/// silently substituted into [data], so the UI can never mistake a fallback for
/// a fresh success.
class DiaryState<T> {
  const DiaryState({
    required this.status,
    this.data,
    this.cachedData,
    this.failure,
  });

  final DiaryStatus status;

  /// Authoritative server data. Null whenever the request did not succeed.
  final T? data;

  /// Last known local snapshot, if one exists.
  final T? cachedData;

  /// Structured failure for the non-success statuses.
  final NetworkFailure? failure;

  bool get isSuccess => status == DiaryStatus.success || status == DiaryStatus.empty;

  /// True when the UI is rendering [cachedData] instead of a fresh response.
  bool get isShowingStaleData => !isSuccess && cachedData != null;

  /// What the UI should render: fresh data when available, otherwise the cache.
  T? get displayData => data ?? cachedData;

  /// Vietnamese message for the current status, or null when nothing is wrong.
  String? get message {
    switch (status) {
      case DiaryStatus.loading:
      case DiaryStatus.success:
      case DiaryStatus.empty:
        return null;
      case DiaryStatus.cachedOffline:
        return 'Không có kết nối. Đang hiển thị dữ liệu đã lưu ngoại tuyến.';
      case DiaryStatus.unauthorized:
        return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      case DiaryStatus.timeout:
        return isShowingStaleData
            ? 'Máy chủ phản hồi quá lâu. Đang hiển thị dữ liệu đã lưu.'
            : 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.';
      case DiaryStatus.rateLimited:
        return 'Bạn thao tác quá nhanh. Vui lòng chờ một lát rồi thử lại.';
      case DiaryStatus.serverError:
        return isShowingStaleData
            ? 'Máy chủ đang gặp sự cố. Đang hiển thị dữ liệu đã lưu.'
            : 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.';
    }
  }

  /// Whether offering a retry button makes sense. 401 is excluded: retrying
  /// without re-authenticating just loops.
  bool get canRetry => switch (status) {
        DiaryStatus.cachedOffline ||
        DiaryStatus.timeout ||
        DiaryStatus.rateLimited ||
        DiaryStatus.serverError =>
          true,
        _ => false,
      };
}

/// Maps a transport/HTTP failure onto a diary status.
///
/// [hasCache] only affects the connectivity case: cachedOffline is claimed only
/// when there really is a cache to show.
DiaryStatus diaryStatusFor(NetworkFailure failure, {required bool hasCache}) {
  return switch (failure) {
    UnauthorizedFailure() => DiaryStatus.unauthorized,
    RateLimitFailure() => DiaryStatus.rateLimited,
    TimeoutFailure() => DiaryStatus.timeout,
    NetworkUnreachableFailure() =>
      hasCache ? DiaryStatus.cachedOffline : DiaryStatus.serverError,
    _ => DiaryStatus.serverError,
  };
}

final localStorageProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});

final diaryApiServiceProvider = Provider<DiaryApiService>((ref) {
  return DiaryApiService();
});

/// Single implementation of the server-first write contract, shared by the
/// scanner and food-search screens.
final mealLoggerProvider = Provider<MealLogger>((ref) {
  return MealLogger(
    diaryApi: ref.watch(diaryApiServiceProvider),
    storage: ref.watch(localStorageProvider),
  );
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final dailyDiaryProvider = FutureProvider<DiaryState<DailyDiaryDto>>((ref) async {
  final diaryService = ref.watch(diaryApiServiceProvider);
  final storage = ref.watch(localStorageProvider);
  final date = ref.watch(selectedDateProvider);

  try {
    final serverDiary = await diaryService.getDailyDiary(date);

    final isEmpty = serverDiary.breakfast.isEmpty &&
        serverDiary.lunch.isEmpty &&
        serverDiary.dinner.isEmpty &&
        serverDiary.snacks.isEmpty;

    // A successful empty day is authoritative: the user really has logged
    // nothing. Substituting stale local entries here would resurrect meals the
    // user deleted elsewhere.
    return DiaryState(
      status: isEmpty ? DiaryStatus.empty : DiaryStatus.success,
      data: serverDiary,
    );
  } on DioException catch (error) {
    final failure = NetworkFailure.fromDioException(error);
    final cached = await _loadCachedDiary(storage, date);

    return DiaryState(
      status: diaryStatusFor(failure, hasCache: cached != null),
      cachedData: cached,
      failure: failure,
    );
  }
});

final weeklyStatsProvider = FutureProvider<DiaryState<List<DailyStatDto>>>((ref) async {
  final diaryService = ref.watch(diaryApiServiceProvider);
  final storage = ref.watch(localStorageProvider);
  final end = DateTime.now();
  final start = end.subtract(const Duration(days: 6));

  try {
    final serverStats = await diaryService.getStats(start, end);

    return DiaryState(
      status: serverStats.isEmpty ? DiaryStatus.empty : DiaryStatus.success,
      data: serverStats,
    );
  } on DioException catch (error) {
    final failure = NetworkFailure.fromDioException(error);
    final cached = await _loadCachedStats(storage, start);

    return DiaryState(
      status: diaryStatusFor(failure, hasCache: cached != null),
      cachedData: cached,
      failure: failure,
    );
  }
});

/// Builds a diary snapshot from local entries, or null when nothing is cached.
Future<DailyDiaryDto?> _loadCachedDiary(LocalStorageService storage, DateTime date) async {
  final List<FoodEntry> entries;
  try {
    entries = await storage.loadEntries();
  } catch (_) {
    // An unreadable cache is simply "no cache".
    return null;
  }

  final selectedDate = DateFormat('yyyy-MM-dd').format(date);
  final todaysEntries = entries
      .where((e) => DateFormat('yyyy-MM-dd').format(e.date) == selectedDate)
      .toList();

  if (todaysEntries.isEmpty) {
    return null;
  }

  var targetCalories = (await storage.getDailyGoal()).toDouble();
  try {
    final profile = await profileApiService.getProfile();
    final backendTarget = profile?['targetCalories'];
    if (backendTarget is num && backendTarget > 0) {
      targetCalories = backendTarget.toDouble();
      await storage.setDailyGoal(backendTarget.toInt());
    }
  } on DioException {
    // The stored goal is a fine fallback when the profile call also fails.
  }

  final breakfast = <MealItemDto>[];
  final lunch = <MealItemDto>[];
  final dinner = <MealItemDto>[];
  final snacks = <MealItemDto>[];
  var totalCalories = 0.0;

  for (final entry in todaysEntries) {
    totalCalories += entry.calories;

    final item = MealItemDto(
      id: entry.id.hashCode,
      foodId: entry.id.hashCode,
      foodName: entry.name,
      quantity: 1.0,
      calories: entry.calories.toDouble(),
      mealType: entry.mealType,
    );

    switch (entry.mealType.toLowerCase()) {
      case 'breakfast':
        breakfast.add(item);
      case 'lunch':
        lunch.add(item);
      case 'dinner':
        dinner.add(item);
      default:
        snacks.add(item);
    }
  }

  return DailyDiaryDto(
    date: date,
    totalCaloriesConsumed: totalCalories,
    targetCalories: targetCalories,
    breakfast: breakfast,
    lunch: lunch,
    dinner: dinner,
    snacks: snacks,
  );
}

/// Builds a 7-day stats snapshot from local entries, or null when empty.
Future<List<DailyStatDto>?> _loadCachedStats(LocalStorageService storage, DateTime start) async {
  final List<FoodEntry> entries;
  try {
    entries = await storage.loadEntries();
  } catch (_) {
    return null;
  }

  if (entries.isEmpty) {
    return null;
  }

  final totals = <String, double>{};
  for (final entry in entries) {
    final key = DateFormat('yyyy-MM-dd').format(entry.date);
    totals[key] = (totals[key] ?? 0) + entry.calories;
  }

  return List.generate(7, (i) {
    final date = start.add(Duration(days: i));
    final key = DateFormat('yyyy-MM-dd').format(date);
    return DailyStatDto(date: date, caloriesConsumed: totals[key] ?? 0);
  });
}

class DailyGoalNotifier extends Notifier<int> {
  @override
  int build() => 2000;

  void updateGoal(int goal) {
    state = goal;
  }
}

final dailyGoalProvider = NotifierProvider<DailyGoalNotifier, int>(() => DailyGoalNotifier());
