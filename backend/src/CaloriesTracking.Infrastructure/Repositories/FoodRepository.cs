using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Domain.Entities;
using CaloriesTracking.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CaloriesTracking.Infrastructure.Repositories;

public sealed class FoodRepository : IFoodRepository
{
    private readonly ApplicationDbContext _dbContext;

    public FoodRepository(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<Food?> GetByIdAsync(int id, CancellationToken cancellationToken = default)
    {
        return await _dbContext.Foods.FindAsync(new object[] { id }, cancellationToken);
    }

    public async Task<Food?> GetByNameAsync(string name, CancellationToken cancellationToken = default)
    {
        return await _dbContext.Foods.FirstOrDefaultAsync(f => f.Name == name, cancellationToken);
    }

    public void Add(Food food)
    {
        _dbContext.Foods.Add(food);
    }
}
