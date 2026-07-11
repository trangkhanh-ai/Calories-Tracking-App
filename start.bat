@echo off
echo =========================================
echo   KHOI DONG CALORIES TRACKING APP
echo =========================================

echo 1. Dang khoi dong Backend API (Terminal moi se hien len)...
REM DOTNET_ROLL_FORWARD: cho phep chay app net9.0 tren may chi cai .NET 10 runtime
start cmd /k "title Backend API && cd backend\src\CaloriesTracking.Api && set DOTNET_ROLL_FORWARD=LatestMajor&& dotnet run"

echo 2. Dang khoi dong Frontend (Flutter Web) tren port 54321...
flutter run -d chrome --web-port=54321
