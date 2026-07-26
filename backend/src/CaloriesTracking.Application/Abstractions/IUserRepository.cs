using CaloriesTracking.Domain.Entities;

namespace CaloriesTracking.Application.Abstractions;

public interface IUserRepository
{
    Task<User?> GetByIdAsync(int userId, CancellationToken cancellationToken = default);

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);

    Task<User?> GetByUsernameAsync(string username, CancellationToken cancellationToken = default);

    Task<User?> GetByEmailAsync(string email, CancellationToken cancellationToken = default);

    /// <summary>
    /// Case-insensitive username lookup against the indexed normalized column.
    /// The caller supplies an already-normalized value.
    /// </summary>
    Task<User?> GetByNormalizedUsernameAsync(string normalizedUsername, CancellationToken cancellationToken = default);

    /// <summary>Case-insensitive email lookup against the indexed normalized column.</summary>
    Task<User?> GetByNormalizedEmailAsync(string normalizedEmail, CancellationToken cancellationToken = default);

    Task AddAsync(User user, CancellationToken cancellationToken = default);

    /// <summary>
    /// Drops a failed insert from the change tracker so a retry on the same
    /// scoped context does not resubmit the rejected row.
    /// </summary>
    void Detach(User user);
}
