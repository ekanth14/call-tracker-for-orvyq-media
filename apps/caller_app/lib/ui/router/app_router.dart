import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../view_models/auth_view_model.dart';
import '../views/auth/consent_screen.dart';
import '../views/auth/login_screen.dart';
import '../views/calling/calling_active_screen.dart';
import '../views/calling/post_call_dialog_screen.dart';
import '../views/health/health_check_screen.dart';
import '../views/queue/lead_queue_screen.dart';

class AppRouter {
  final AuthViewModel authViewModel;

  AppRouter(this.authViewModel);

  late final GoRouter router = GoRouter(
    initialLocation: '/queue',
    refreshListenable: authViewModel,
    redirect: (BuildContext context, GoRouterState state) {
      final isAuthenticated = authViewModel.isAuthenticated;
      final hasAcceptedConsent = authViewModel.hasAcceptedConsent;
      final location = state.uri.path;

      // 1. If not authenticated, must go to /login
      if (!isAuthenticated) {
        return location == '/login' ? null : '/login';
      }

      // 2. If authenticated but has not accepted privacy consent, must go to /consent (§6)
      if (!hasAcceptedConsent) {
        return location == '/consent' ? null : '/consent';
      }

      // 3. If authenticated and consented, visiting /login or /consent redirects to /queue
      if (location == '/login' || location == '/consent') {
        return '/queue';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/consent',
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: '/queue',
        builder: (context, state) => const LeadQueueScreen(),
      ),
      GoRoute(
        path: '/calling',
        builder: (context, state) => const CallingActiveScreen(),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) => const PostCallDialogScreen(),
      ),
      GoRoute(
        path: '/health',
        builder: (context, state) => const HealthCheckScreen(),
      ),
    ],
  );
}
