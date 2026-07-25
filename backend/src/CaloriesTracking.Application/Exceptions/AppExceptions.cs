namespace CaloriesTracking.Application.Exceptions;

/// <summary>
/// Base type for every exception the API maps to a deliberate HTTP status.
/// Using types instead of message-substring matching keeps
/// <c>GlobalExceptionHandler</c> deterministic.
/// </summary>
public abstract class AppException : Exception
{
    protected AppException(string message) : base(message)
    {
    }

    protected AppException(string message, Exception innerException) : base(message, innerException)
    {
    }

    /// <summary>Safe to return to the caller: never contains provider text.</summary>
    public abstract string PublicTitle { get; }
}

/// <summary>400 — the request failed contract validation.</summary>
public sealed class ValidationAppException : AppException
{
    public ValidationAppException(string message) : base(message)
    {
    }

    public ValidationAppException(string field, string message) : base(message)
    {
        Field = field;
    }

    public string? Field { get; }

    public override string PublicTitle => "Bad Request";
}

/// <summary>409 — a uniqueness constraint rejected the write.</summary>
public sealed class ConflictAppException : AppException
{
    public ConflictAppException(string message) : base(message)
    {
    }

    public ConflictAppException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public override string PublicTitle => "Conflict";
}

/// <summary>413 — decoded payload exceeded the configured budget.</summary>
public sealed class PayloadTooLargeAppException : AppException
{
    public PayloadTooLargeAppException(string message) : base(message)
    {
    }

    public override string PublicTitle => "Payload Too Large";
}

/// <summary>415 — media type is outside the supported allow-list.</summary>
public sealed class UnsupportedMediaTypeAppException : AppException
{
    public UnsupportedMediaTypeAppException(string message) : base(message)
    {
    }

    public override string PublicTitle => "Unsupported Media Type";
}

/// <summary>
/// 500 — a seeding or migration invariant is broken and needs an operator.
/// The message is deliberately free of credentials and row payloads.
/// </summary>
public sealed class DataIntegrityAppException : AppException
{
    public DataIntegrityAppException(string message) : base(message)
    {
    }

    public DataIntegrityAppException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public override string PublicTitle => "Data Integrity Error";
}
