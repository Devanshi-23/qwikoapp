import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../core/failures.dart';
import '../../utils/app_colors.dart';
import '../../widgets/primary_button.dart';
import '../profile/bank_details_screen.dart';
import '../profile/documents_screen.dart';
import '../profile/vehicle_details_screen.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  bool _isSubmitting = false;

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _showError(AppFailure failure) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await context.services.profile.submitForVerification();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(failure);
      return;
    }

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.verificationPending,
      (_) => false,
    );
  }

  Future<void> _later() async {
    try {
      await context.services.session.signOut();
    } on AppFailure catch (failure) {
      if (mounted) _showError(failure);
      return;
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.services.profile;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final profile = controller.profile;
        if (profile == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final bank = profile.bank;
        final steps = [
          profile.hasVehicleDetails,
          profile.hasAllDocuments,
          profile.hasBankDetails,
        ];
        final completed = steps.where((done) => done).length;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    children: [
                      Text(
                        'Hi ${profile.firstName} 👋',
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Complete these steps to start delivering with Qwiko.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accentDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              height: 58,
                              width: 58,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CircularProgressIndicator(
                                    value: completed / steps.length,
                                    strokeWidth: 6,
                                    backgroundColor: Colors.white24,
                                    color: Colors.white,
                                  ),
                                  Center(
                                    child: Text(
                                      '$completed/${steps.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                completed == steps.length
                                    ? 'All done! Submit your profile for verification.'
                                    : '${steps.length - completed} step${steps.length - completed == 1 ? '' : 's'} left to complete your profile',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildStep(
                        number: 1,
                        icon: Icons.two_wheeler_rounded,
                        title: 'Vehicle Details',
                        subtitle:
                            profile.vehicle?.summary ??
                            'Vehicle type and number',
                        done: profile.hasVehicleDetails,
                        onTap: () => _open(
                          const VehicleDetailsScreen(isOnboarding: true),
                        ),
                      ),
                      _buildStep(
                        number: 2,
                        icon: Icons.description_outlined,
                        title: 'Upload Documents',
                        subtitle:
                            '${profile.uploadedDocumentCount} of ${profile.requiredDocuments.length} uploaded',
                        done: profile.hasAllDocuments,
                        onTap: () =>
                            _open(const DocumentsScreen(isOnboarding: true)),
                      ),
                      _buildStep(
                        number: 3,
                        icon: Icons.account_balance_outlined,
                        title: 'Bank Details',
                        subtitle: bank != null
                            ? '${bank.bankName} • A/c ending ${bank.last4}'
                            : 'For receiving your weekly payouts',
                        done: profile.hasBankDetails,
                        onTap: () =>
                            _open(const BankDetailsScreen(isOnboarding: true)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      PrimaryButton(
                        label: 'Submit for Verification',
                        isLoading: _isSubmitting,
                        onPressed: profile.isKycComplete ? _submit : null,
                      ),
                      TextButton(
                        onPressed: _later,
                        child: const Text(
                          'I will do this later',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep({
    required int number,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: done ? AppColors.primary : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  done ? Icons.check_rounded : icon,
                  color: done ? Colors.white : AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP $number',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: done
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: done ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
