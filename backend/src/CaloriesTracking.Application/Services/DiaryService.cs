using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Services;

public sealed class DiaryService : IDiaryService
{
    private readonly IDailyLogRepository _dailyLogRepository;
    private readonly IFoodRepository _foodRepository;
    private readonly IUserRepository _userRepository;

    public DiaryService(
        IDailyLogRepository dailyLogRepository,
        IFoodRepository foodRepository,
        IUserRepository userRepository)
    {
        _dailyLogRepository = dailyLogRepository;
        _foodRepository = foodRepository;
        _userRepository = userRepository;
    }

    public async Task<DailyDiaryDto> GetDailyDiaryAsync(int userId, DateTime date, CancellationToken cancellationToken = default)
    {
        var dailyLog = await _dailyLogRepository.GetDailyLogAsync(userId, date, cancellationToken);
        var user = await _userRepository.GetByIdAsync(userId, cancellationToken);

        // Calculate Target Calories
        decimal targetCalories = user?.TargetCalories ?? 2000;
        if (user != null && user.TargetCalories == null && user.Weight > 0 && user.Height > 0 && user.Age > 0)
        {
            // BMR calculation (Mifflin-St Jeor)
            decimal bmr = 10 * user.Weight.Value + 6.25m * user.Height.Value - 5 * user.Age.Value;
            bmr += user.Gender?.ToLower() == "male" ? 5 : -161;
            
            // TDEE (assuming sedentary for now)
            targetCalories = bmr * 1.2m;
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

    public async Task LogMealAsync(int userId, LogMealRequest request, CancellationToken cancellationToken = default)
    {
        var food = await _foodRepository.GetByNameAsync(request.FoodName, cancellationToken);
        if (food == null)
        {
            food = new Food
            {
                Name = request.FoodName,
                CaloriesPer100g = request.CaloriesPer100g,
                Protein = 0,
                Carbs = 0,
                Fat = 0
            };
            _foodRepository.Add(food);
            // We need to save changes so Food gets an ID before being added to MealItem
            await _dailyLogRepository.SaveChangesAsync(cancellationToken);
        }

        var dailyLog = await _dailyLogRepository.GetDailyLogAsync(userId, request.Date, cancellationToken);
        if (dailyLog == null)
        {
            dailyLog = new DailyLog
            {
                UserId = userId,
                Date = DateOnly.FromDateTime(request.Date.Date),
                TotalCaloriesConsumed = 0,
                MealItems = new List<MealItem>()
            };
            _dailyLogRepository.Add(dailyLog);
        }

        decimal calories = food.CaloriesPer100g * request.Quantity / 100m;

        dailyLog.MealItems.Add(new MealItem
        {
            FoodId = food.Id,
            Quantity = request.Quantity,
            TotalCalories = calories,
            MealType = request.MealType
        });

        dailyLog.TotalCaloriesConsumed += calories;

        await _dailyLogRepository.SaveChangesAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<DailyStatDto>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default)
    {
        var logs = await _dailyLogRepository.GetStatsAsync(userId, startDate, endDate, cancellationToken);
        
        var stats = new List<DailyStatDto>();
        for (var d = startDate.Date; d <= endDate.Date; d = d.AddDays(1))
        {
            var dateOnly = DateOnly.FromDateTime(d);
            var log = logs.FirstOrDefault(l => l.Date == dateOnly);
            stats.Add(new DailyStatDto(d, log?.TotalCaloriesConsumed ?? 0));
        }

        return stats;
    }
}
