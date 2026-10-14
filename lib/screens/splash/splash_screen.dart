import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../utils/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _goNext();
  }

  Future<void> _goNext() async {
    final services = context.services;
    await Future.wait<void>([
      Future<void>.delayed(const Duration(seconds: 2)),
      services.settings.ensureLoaded(),
      services.session.restore(),
    ]);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final partner = services.session.partner;
    if (services.session.isSignedIn && partner != null) {
      AppRoutes.goToAccountHome(navigator, partner);
    } else if (!services.settings.settings.introSeen) {
      navigator.pushReplacementNamed(AppRoutes.intro);
    } else {
      navigator.pushReplacementNamed(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 220,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.delivery_dining_rounded,
                  color: AppColors.primary,
                  size: 90,
                );
              },
            ),
            const SizedBox(height: 40),
            const SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delivery Partner',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
