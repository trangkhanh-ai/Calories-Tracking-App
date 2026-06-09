using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Repositories;

public sealed class DailyLogRepository : IDailyLogRepository
{
    private readonly ApplicationDbContext _dbContext;

    public DailyLogRepository(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<DailyLog?> GetDailyLogAsync(int userId, DateTime date, CancellationToken cancellationToken = default)
    {
        var targetDate = DateOnly.FromDateTime(date.Date);
        return await _dbContext.DailyLogs
            .Include(x => x.MealItems)
            .ThenInclude(m => m.Food)
            .FirstOrDefaultAsync(x => x.UserId == userId && x.Date == targetDate, cancellationToken);
    }

    public async Task<IReadOnlyList<DailyLog>> GetStatsAsync(int userId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default)
    {
        var start = DateOnly.FromDateTime(startDate.Date);
        var end = DateOnly.FromDateTime(endDate.Date);
        return await _dbContext.DailyLogs
            .Include(x => x.MealItems)
            .Where(x => x.UserId == userId && x.Date >= start && x.Date <= end)
            .OrderBy(x => x.Date)
            .ToListAsync(cancellationToken);
    }

    public void Add(DailyLog dailyLog)
    {
        _dbContext.DailyLogs.Add(dailyLog);
    }

    public async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        return await _dbContext.SaveChangesAsync(cancellationToken);
    }
}
