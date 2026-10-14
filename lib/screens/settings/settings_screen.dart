import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../core/app_info.dart';
import '../../core/failures.dart';
import '../../models/notification.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<String> _languages = [
    'English',
    'हिन्दी (Hindi)',
    'मराठी (Marathi)',
    'தமிழ் (Tamil)',
    'తెలుగు (Telugu)',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.services.settings.ensureLoaded();
    });
  }

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  static const languageReason =
      'Hindi and regional languages are coming in a later update.';
  static const mapsReason = 'Available once maps are connected.';

  Future<void> _chooseLanguage() async {
    final settings = context.services.settings;
    final selected = await showAppBottomSheet<String>(
      context,
      title: 'Choose language',
      subtitle: languageReason,
      builder: (context) => Column(
        children: [
          for (final language in _languages)
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: language == _languages.first,
              title: Text(language),
              subtitle: language == _languages.first
                  ? null
                  : const Text('Coming soon'),
              trailing: settings.settings.language == language
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(context, language),
            ),
        ],
      ),
    );

    if (selected != null) {
      await _attempt(() => settings.setLanguage(selected));
    }
  }

  void _chooseNavigationApp() {
    showAppBottomSheet<void>(
      context,
      title: 'Navigation',
      subtitle: 'Turn-by-turn directions for pickups and drops.',
      builder: (context) => Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('In-app map'),
            trailing: const Icon(Icons.check_rounded, color: AppColors.primary),
            onTap: () => Navigator.pop(context),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: false,
            title: Text('Google Maps'),
            subtitle: Text(mapsReason),
          ),
        ],
      ),
    );
  }

  static String _categoryHint(NotificationCategory category) =>
      switch (category) {
        NotificationCategory.offer => 'Order updates and cancellations',
        NotificationCategory.earnings => 'Payouts and deposits',
        NotificationCategory.incentive => 'Bonuses and rewards',
        NotificationCategory.account => 'Documents and verification',
        NotificationCategory.safety => 'Always on for your safety',
        NotificationCategory.system => 'App news and tips',
      };

  Future<void> _confirmLogout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to log in again to receive orders.',
      confirmLabel: 'Log out',
      destructive: true,
    );

    if (!confirmed || !mounted) return;
    var signedOut = false;
    await _attempt(() async {
      await context.services.session.signOut();
      signedOut = true;
    });
    if (signedOut && mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }

  void _showInfo(String title, String message) {
    showAppBottomSheet<void>(
      context,
      title: title,
      builder: (context) =>
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.services.settings;

    return AppScaffold(
      title: 'Settings',
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final settings = controller.settings;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionTitle('Notifications'),
              _buildGroup([
                SwitchListTile(
                  value: settings.orderNotifications,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Order notifications'),
                  subtitle: const Text('Get notified about new orders'),
                  onChanged: (v) =>
                      _attempt(() => controller.setOrderNotifications(v)),
                ),
                SwitchListTile(
                  value: settings.soundAlerts,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(
                    Icons.volume_up_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Sound alerts'),
                  subtitle: const Text(
                    'Play a sound for new orders (system alert in this demo)',
                  ),
                  onChanged: (v) =>
                      _attempt(() => controller.setSoundAlerts(v)),
                ),
                SwitchListTile(
                  value: settings.vibration,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(
                    Icons.vibration_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrate for new orders'),
                  onChanged: (v) => _attempt(() => controller.setVibration(v)),
                ),
              ]),
              _buildSectionTitle('Inbox'),
              _buildGroup([
                for (final category in NotificationCategory.values)
                  SwitchListTile(
                    value: settings.allows(category),
                    activeThumbColor: AppColors.primary,
                    title: Text(category.label),
                    subtitle: Text(_categoryHint(category)),
                    onChanged: category == NotificationCategory.safety
                        ? null
                        : (v) => _attempt(
                            () => controller.setCategoryEnabled(category, v),
                          ),
                  ),
              ]),
              _buildSectionTitle('Preferences'),
              _buildGroup([
                ListTile(
                  leading: const Icon(
                    Icons.translate_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Language'),
                  subtitle: Text(settings.language),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onTap: _chooseLanguage,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.navigation_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Navigation'),
                  subtitle: const Text('In-app map'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onTap: _chooseNavigationApp,
                ),
              ]),
              if (context.services.demo != null) ...[
                _buildSectionTitle('Demo'),
                _buildGroup([
                  ListTile(
                    leading: const Icon(
                      Icons.science_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Demo controls'),
                    subtitle: const Text('Trigger offers, failures and more'),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.demoControls),
                  ),
                ]),
              ],
              _buildSectionTitle('About'),
              _buildGroup([
                ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Terms & Conditions'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => _showInfo('Terms & Conditions', termsText),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => _showInfo('Privacy Policy', privacyText),
                ),
                const ListTile(
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text('App version'),
                  trailing: Text(
                    appVersion,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'Log out',
                icon: Icons.logout_rounded,
                variant: ButtonVariant.destructive,
                height: 52,
                onPressed: _confirmLogout,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}
