using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Abstractions;

public interface IDailyLogRepository
{
    Task<DailyLog?> GetDailyLogAsync(int userId, DateTime date, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DailyLog>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default);

    void Add(DailyLog dailyLog);

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
