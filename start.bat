@echo off
echo =========================================
echo   KHOI DONG CALORIES TRACKING APP
echo =========================================

echo 1. Dang khoi dong Backend API (Terminal moi se hien len)...
start cmd /k "title Backend API && cd backend\src\CaloriesTracking.Api && dotnet run"

echo 2. Dang khoi dong Frontend (Flutter Web)...
flutter run -d chrome
