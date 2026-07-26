using CaloriesTracking.Application.Dtos.Diary;
using CaloriesTracking.Application.Exceptions;

namespace CaloriesTracking.Application.Validation;

/// <summary>
/// Diary contract enforcement. Lives in Application rather than the controller
/// so the service is protected even when invoked directly (tests, background
/// work, future transports).
/// </summary>
public static class DiaryValidationRules
{
    public const int FoodNameMaxLength = 200;
    public const decimal MaxCaloriesPer100g = 10_000m;
    public const decimal MaxQuantity = 100_000m;
    public const int MaxStatsRangeDays = 90;

    /// <summary>A meal logged more than this far ahead is a client bug.</summary>
    public static readonly TimeSpan MaxFutureTolerance = TimeSpan.FromDays(1);

    public static readonly IReadOnlySet<string> AllowedMealTypes =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "Breakfast",
            "Lunch",
            "Dinner",
            "Snack"
        };

    /// <summary>
    /// Validates the whole request and returns a normalized copy. Callers must
    /// use the returned value — the original may carry untrimmed input.
    /// </summary>
    public static LogMealRequest ValidateLogMeal(LogMealRequest request, DateTime utcNow)
    {
        ArgumentNullException.ThrowIfNull(request);

        var foodName = ValidateFoodName(request.FoodName);
        ValidateCaloriesPer100g(request.CaloriesPer100g);
        ValidateQuantity(request.Quantity);
        var mealType = ValidateMealType(request.MealType);
        ValidateDate(request.Date, utcNow);

        return request with
        {
            FoodName = foodName,
            MealType = mealType
        };
    }

    public static string ValidateFoodName(string? foodName)
    {
        if (string.IsNullOrWhiteSpace(foodName))
        {
            throw new ValidationAppException("foodName", "FoodName is required.");
        }

        var trimmed = foodName.Trim();

        if (trimmed.Length > FoodNameMaxLength)
        {
            throw new ValidationAppException(
                "foodName",
                $"FoodName must not exceed {FoodNameMaxLength} characters.");
        }

        return trimmed;
    }

    public static void ValidateCaloriesPer100g(decimal calories)
    {
        if (calories <= 0)
        {
            throw new ValidationAppException(
                "caloriesPer100g",
                "CaloriesPer100g must be greater than zero.");
        }

        if (calories > MaxCaloriesPer100g)
        {
            throw new ValidationAppException(
                "caloriesPer100g",
                $"CaloriesPer100g must not exceed {MaxCaloriesPer100g:0} kcal.");
        }
    }

    public static void ValidateQuantity(decimal quantity)
    {
        if (quantity <= 0)
        {
            throw new ValidationAppException("quantity", "Quantity must be greater than zero.");
        }

        if (quantity > MaxQuantity)
        {
            throw new ValidationAppException(
                "quantity",
                $"Quantity must not exceed {MaxQuantity:0} g.");
        }
    }

    public static string ValidateMealType(string? mealType)
    {
        if (string.IsNullOrWhiteSpace(mealType) || !AllowedMealTypes.Contains(mealType))
        {
            throw new ValidationAppException(
                "mealType",
                "MealType must be one of: Breakfast, Lunch, Dinner, Snack.");
        }

        return mealType;
    }

    public static void ValidateDate(DateTime date, DateTime utcNow)
    {
        if (date == default)
        {
            throw new ValidationAppException("date", "Date is required and must be a valid date.");
        }

        var normalizedUtc = date.Kind == DateTimeKind.Utc
            ? date
            : DateTime.SpecifyKind(date, DateTimeKind.Utc);

        if (normalizedUtc.Date > utcNow.Date.Add(MaxFutureTolerance))
        {
            throw new ValidationAppException(
                "date",
                "Date must not be more than 1 day in the future.");
        }
    }

    /// <summary>
    /// Bounds the stats window. Defaulted dates are rejected outright — an
    /// unvalidated <c>DateTime.MinValue</c> start would otherwise drive a
    /// multi-million-iteration day loop in the service.
    /// </summary>
    public static void ValidateStatsRange(DateTime startDate, DateTime endDate)
    {
        if (startDate == default)
        {
            throw new ValidationAppException("startDate", "startDate is required and must be a valid date.");
        }

        if (endDate == default)
        {
            throw new ValidationAppException("endDate", "endDate is required and must be a valid date.");
        }

        if (startDate.Date > endDate.Date)
        {
            throw new ValidationAppException("startDate", "startDate must be on or before endDate.");
        }

        // Inclusive span: the same day start and end counts as 1 day.
        var inclusiveDays = (endDate.Date - startDate.Date).Days + 1;
        if (inclusiveDays > MaxStatsRangeDays)
        {
            throw new ValidationAppException(
                "endDate",
                $"The requested range must not exceed {MaxStatsRangeDays} days.");
        }
    }
}
