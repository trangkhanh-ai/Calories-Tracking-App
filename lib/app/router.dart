import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/screens/home_screen.dart';
import '../features/scanner/screens/camera_scanner_screen.dart';
import '../features/scanner/screens/results_screen.dart';
import '../features/scanner/models/food_analysis_result.dart';
import '../features/profile/screens/goal_setup_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/diary/screens/stats_screen.dart';
import '../features/food_search/screens/food_search_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/scanner',
      name: 'scanner',
      builder: (context, state) => const CameraScannerScreen(),
    ),
    GoRoute(
      path: '/results',
      name: 'results',
      builder: (context, state) {
        final result = state.extra as FoodAnalysisResult;
        return ResultsScreen(result: result);
      },
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/goal-setup',
      name: 'goal-setup',
      builder: (context, state) => const GoalSetupScreen(),
    ),
    GoRoute(
      path: '/stats',
      name: 'stats',
      builder: (context, state) => const StatsScreen(),
    ),
    GoRoute(
      path: '/food-search',
      name: 'food-search',
      builder: (context, state) => const FoodSearchScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Page not found: ${state.error}'),
    ),
  ),
);
