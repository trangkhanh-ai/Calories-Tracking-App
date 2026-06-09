using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Abstractions;

public interface IFoodRepository
{
    Task<Food?> GetByIdAsync(int id, CancellationToken cancellationToken = default);
    Task<Food?> GetByNameAsync(string name, CancellationToken cancellationToken = default);
    void Add(Food food);
}
