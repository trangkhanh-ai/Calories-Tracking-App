# Build: docker build -t calories-api ./backend
# Run:   docker run -p 8080:8080 -e JWT__KEY=... -e GEMINI__APIKEY=... calories-api
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

# Render/Railway map PORT vào đây
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "CaloriesTracking.Api.dll"]
