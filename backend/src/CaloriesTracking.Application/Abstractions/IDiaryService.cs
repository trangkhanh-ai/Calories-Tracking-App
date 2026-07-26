using CaloriesTracking.Application.Dtos.Diary;

namespace CaloriesTracking.Application.Abstractions;

public interface IDiaryService
{
    Task<DailyDiaryDto> GetDailyDiaryAsync(int userId, DateTime date, CancellationToken cancellationToken = default);

    /// <summary>
    /// Persists a meal and returns the day's diary as the server now sees it,
    /// so the caller can adopt authoritative state rather than fabricating a
    /// local row with a client-generated id.
    /// </summary>
    Task<DailyDiaryDto> LogMealAsync(int userId, LogMealRequest request, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DailyStatDto>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default);
}
