# Build: docker build -t calories-api ./backend
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Restore trước để tận dụng layer cache
COPY src/CaloriesTracking.Domain/CaloriesTracking.Domain.csproj src/CaloriesTracking.Domain/
COPY src/CaloriesTracking.Application/CaloriesTracking.Application.csproj src/CaloriesTracking.Application/
COPY src/CaloriesTracking.Infrastructure/CaloriesTracking.Infrastructure.csproj src/CaloriesTracking.Infrastructure/
COPY src/CaloriesTracking.Api/CaloriesTracking.Api.csproj src/CaloriesTracking.Api/
RUN dotnet restore src/CaloriesTracking.Api/CaloriesTracking.Api.csproj

COPY src/ src/
RUN dotnet publish src/CaloriesTracking.Api/CaloriesTracking.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
COPY --from=build /app .

# Render injects PORT at runtime; keep 8080 as the local Docker default.
EXPOSE 8080
STOPSIGNAL SIGTERM

ENTRYPOINT ["sh", "-c", "exec dotnet CaloriesTracking.Api.dll --urls http://0.0.0.0:${PORT:-8080}"]
