using CaloriesTracking.Application.Abstractions;
using CaloriesTracking.Application.Services;
using Microsoft.Extensions.DependencyInjection;

namespace CaloriesTracking.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IProfileService, ProfileService>();
        services.AddScoped<IDiaryService, DiaryService>();
        services.AddScoped<IAuthService, AuthService>();
        return services;
    }
}
