using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Abstractions;

public interface IDailyLogRepository
{
    Task<DailyLog?> GetDailyLogAsync(int userId, DateTime date, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DailyLog>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default);

    void Add(DailyLog dailyLog);

    /// <summary>Removes a rejected insert from the change tracker before a retry.</summary>
    void Detach(DailyLog dailyLog);

    /// <summary>
    /// Drops all tracked state after a rolled-back transaction so the next
    /// attempt re-reads from the database instead of replaying stale entities.
    /// </summary>
    void ClearChangeTracker();

    Task AddMealAndIncrementCaloriesAsync(
        DailyLog dailyLog,
        MealItem mealItem,
        CancellationToken cancellationToken = default);

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);

    Task ExecuteInTransactionAsync(Func<Task> action, CancellationToken cancellationToken = default);
}
