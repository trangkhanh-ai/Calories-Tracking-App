using CaloriesTracking.Application.Dtos.Diary;

namespace CaloriesTracking.Application.Abstractions;

public interface IDiaryService
{
    Task<DailyDiaryDto> GetDailyDiaryAsync(int userId, DateTime date, CancellationToken cancellationToken = default);

    Task LogMealAsync(int userId, LogMealRequest request, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DailyStatDto>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default);
}
