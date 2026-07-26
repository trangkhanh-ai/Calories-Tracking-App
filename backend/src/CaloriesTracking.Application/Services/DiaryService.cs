using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Exceptions;
using CaloriesTracking.Application.Validation;
using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Services;

public sealed class DiaryService : IDiaryService
{
    /// <summary>
    /// Attempts for the whole log-meal unit of work. Two concurrent writers can
    /// make each other lose exactly once; a third attempt means something other
    /// than contention is wrong, so the request fails rather than spinning.
    /// </summary>
    private const int MaxConcurrencyAttempts = 3;

    private readonly IDailyLogRepository _dailyLogRepository;
    private readonly IFoodRepository _foodRepository;
    private readonly IUserRepository _userRepository;
    private readonly IUniqueConstraintTranslator _constraintTranslator;
    private readonly TimeProvider _timeProvider;

    public DiaryService(
        IDailyLogRepository dailyLogRepository,
        IFoodRepository foodRepository,
        IUserRepository userRepository,
        IUniqueConstraintTranslator constraintTranslator,
        TimeProvider timeProvider)
    {
        _dailyLogRepository = dailyLogRepository;
        _foodRepository = foodRepository;
        _userRepository = userRepository;
        _constraintTranslator = constraintTranslator;
        _timeProvider = timeProvider;
    }

    public async Task<DailyDiaryDto> GetDailyDiaryAsync(int userId, DateTime date, CancellationToken cancellationToken = default)
    {
        var dailyLog = await _dailyLogRepository.GetDailyLogAsync(userId, date, cancellationToken);
        var user = await _userRepository.GetByIdAsync(userId, cancellationToken);

        decimal targetCalories = user?.TargetCalories ?? 2000;
        if (user != null && user.TargetCalories == null && user.Weight > 0 && user.Height > 0 && user.Age > 0)
        {
            var bmr = CalorieCalculator.CalculateBmr(user.Gender, user.Weight.Value, user.Height.Value, user.Age.Value);
            targetCalories = CalorieCalculator.CalculateTdee(bmr, user.ActivityLevel);
        }

        if (dailyLog == null)
        {
            return new DailyDiaryDto(
                date,
                0,
                targetCalories,
                Array.Empty<MealItemDto>(),
                Array.Empty<MealItemDto>(),
                Array.Empty<MealItemDto>(),
                Array.Empty<MealItemDto>());
        }

        var mealItems = dailyLog.MealItems.Select(m => new MealItemDto(
            m.Id,
            m.FoodId,
            m.Food.Name,
            m.Quantity,
            m.TotalCalories,
            m.MealType)).ToList();

        return new DailyDiaryDto(
            date,
            dailyLog.TotalCaloriesConsumed,
            targetCalories,
            mealItems.Where(m => m.MealType == "Breakfast").ToList(),
            mealItems.Where(m => m.MealType == "Lunch").ToList(),
            mealItems.Where(m => m.MealType == "Dinner").ToList(),
            mealItems.Where(m => m.MealType == "Snack").ToList());
    }

    /// <summary>
    /// Persists a meal and returns the resulting diary for the day, so the
    /// client can adopt the server state instead of inventing a local row.
    /// </summary>
    public async Task<DailyDiaryDto> LogMealAsync(int userId, LogMealRequest request, CancellationToken cancellationToken = default)
    {
        // The service validates independently of the controller so it stays
        // safe when called from tests or any future transport.
        var validated = DiaryValidationRules.ValidateLogMeal(request, _timeProvider.GetUtcNow().UtcDateTime);

        for (var attempt = 1; ; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            try
            {
                await _dailyLogRepository.ExecuteInTransactionAsync(
                    () => ExecuteLogMealInternalAsync(userId, validated, cancellationToken),
                    cancellationToken);

                break;
            }
            catch (Exception exception) when (
                attempt < MaxConcurrencyAttempts &&
                !cancellationToken.IsCancellationRequested &&
                _constraintTranslator.IsUniqueViolation(exception))
            {
                // A peer created the same DailyLog or custom Food between our
                // read and our write. The transaction already rolled back, so
                // nothing partial survives — clear the tracker and re-read.
                _dailyLogRepository.ClearChangeTracker();
            }
        }

        return await GetDailyDiaryAsync(userId, validated.Date, cancellationToken);
    }

    private async Task ExecuteLogMealInternalAsync(int userId, LogMealRequest request, CancellationToken cancellationToken)
    {
        var food = await ResolveFoodAsync(request, cancellationToken);
        var dailyLog = await ResolveDailyLogAsync(userId, request.Date, cancellationToken);

        decimal calories = food.CaloriesPer100g * request.Quantity / 100m;

        var mealItem = new MealItem
        {
            FoodId = food.Id,
            Quantity = request.Quantity,
            TotalCalories = calories,
            MealType = request.MealType
        };

        await _dailyLogRepository.AddMealAndIncrementCaloriesAsync(dailyLog, mealItem, cancellationToken);
    }

    private async Task<Food> ResolveFoodAsync(LogMealRequest request, CancellationToken cancellationToken)
    {
        var normalizedName = AuthValidationRules.Normalize(request.FoodName);

        var existing = await _foodRepository.GetByNameAsync(request.FoodName, cancellationToken)
            ?? await _foodRepository.GetCustomByNormalizedNameAsync(normalizedName, cancellationToken);

        if (existing != null)
        {
            return existing;
        }

        var food = new Food
        {
            Name = request.FoodName,
            NormalizedName = normalizedName,
            CaloriesPer100g = request.CaloriesPer100g,
            Protein = 0,
            Carbs = 0,
            Fat = 0
        };

        _foodRepository.Add(food);

        try
        {
            await _dailyLogRepository.SaveChangesAsync(cancellationToken);
            return food;
        }
        catch (Exception exception) when (_constraintTranslator.IsUniqueViolation(exception))
        {
            // Concurrent insert of the same custom food won the partial unique
            // index. Adopt the winner rather than duplicating it.
            _foodRepository.Detach(food);

            return await _foodRepository.GetCustomByNormalizedNameAsync(normalizedName, cancellationToken)
                ?? throw new ConflictAppException(
                    "The food record could not be resolved after a concurrent update.");
        }
    }

    private async Task<DailyLog> ResolveDailyLogAsync(int userId, DateTime date, CancellationToken cancellationToken)
    {
        var existing = await _dailyLogRepository.GetDailyLogAsync(userId, date, cancellationToken);
        if (existing != null)
        {
            return existing;
        }

        var dailyLog = new DailyLog
        {
            UserId = userId,
            Date = DateOnly.FromDateTime(date.Date),
            TotalCaloriesConsumed = 0,
            MealItems = new List<MealItem>()
        };

        _dailyLogRepository.Add(dailyLog);

        try
        {
            await _dailyLogRepository.SaveChangesAsync(cancellationToken);
            return dailyLog;
        }
        catch (Exception exception) when (_constraintTranslator.IsUniqueViolation(exception))
        {
            // The (UserId, Date) unique index rejected us — a peer created the
            // log first. Reload theirs; never insert a duplicate row.
            _dailyLogRepository.Detach(dailyLog);

            return await _dailyLogRepository.GetDailyLogAsync(userId, date, cancellationToken)
                ?? throw new ConflictAppException(
                    "The daily log could not be resolved after a concurrent update.");
        }
    }

    public async Task<IReadOnlyList<DailyStatDto>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default)
    {
        // Validated here as well as in the controller: an unbounded range would
        // otherwise drive the day loop below for millions of iterations.
        DiaryValidationRules.ValidateStatsRange(startDate, endDate);

        var logs = await _dailyLogRepository.GetStatsAsync(userId, startDate, endDate, cancellationToken);
        var totalsByDate = logs
            .GroupBy(l => l.Date)
            .ToDictionary(g => g.Key, g => g.Sum(l => l.TotalCaloriesConsumed));

        var stats = new List<DailyStatDto>();
        for (var d = startDate.Date; d <= endDate.Date; d = d.AddDays(1))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var dateOnly = DateOnly.FromDateTime(d);
            stats.Add(new DailyStatDto(d, totalsByDate.GetValueOrDefault(dateOnly)));
        }

        return stats;
    }
}
