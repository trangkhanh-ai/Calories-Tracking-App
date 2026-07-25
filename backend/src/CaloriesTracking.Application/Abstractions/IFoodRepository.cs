using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Abstractions;

public interface IFoodRepository
{
    Task<Food?> GetByIdAsync(int id, CancellationToken cancellationToken = default);

    Task<Food?> GetByNameAsync(string name, CancellationToken cancellationToken = default);

    /// <summary>
    /// Locates a custom food (FdcId is null) by its normalized name. Matches the
    /// partial unique index, so this is the only lookup that can be trusted to
    /// resolve a concurrent-insert conflict.
    /// </summary>
    Task<Food?> GetCustomByNormalizedNameAsync(string normalizedName, CancellationToken cancellationToken = default);

    void Add(Food food);

    /// <summary>Removes a rejected insert from the change tracker before a retry.</summary>
    void Detach(Food food);
}
