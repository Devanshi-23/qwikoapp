import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_services.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/media_image.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import '../earnings/earnings_view.dart';
import '../offers/offer_host.dart';
import '../orders/order_details_screen.dart';
import '../orders/order_history_view.dart';
import '../profile/bank_details_screen.dart';
import '../profile/personal_details_screen.dart';
import '../profile/vehicle_details_screen.dart';
import 'dashboard_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  late final AppServices _services = context.services;

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _openTab(int index) => setState(() => _currentTab = index);

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to log in again to receive orders.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await _services.session.signOut();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
    (
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded,
      'Earnings',
    ),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  String? _selectedOrderId;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ReadableWidth(child: DashboardView(onOpenTab: _openTab)),
      _buildOrdersTab(),
      const EarningsView(),
      ReadableWidth(
        child: ListenableBuilder(
          listenable: Listenable.merge([_services.session, _services.profile]),
          builder: (context, _) => _buildProfile(),
        ),
      ),
    ];

    return OfferHost(child: _buildScaffold(tabs));
  }

  Widget _buildOrdersTab() {
    if (!Breakpoints.useTwoPane(context)) return const OrderHistoryView();
    final selected = _selectedOrderId;
    return TwoPane(
      list: OrderHistoryView(
        selectedOrderId: selected,
        onOpenOrder: (id) => setState(() => _selectedOrderId = id),
      ),
      detail: selected == null
          ? const Center(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Select an order',
                message: 'Its details show here.',
              ),
            )
          : OrderDetailsScreen(key: ValueKey(selected), orderId: selected),
    );
  }

  Widget _buildScaffold(List<Widget> tabs) {
    if (Breakpoints.useRail(context)) {
      return AppScaffold(
        maxWidth: double.infinity,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentTab,
              onDestinationSelected: _openTab,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.white,
              indicatorColor: AppColors.primaryLight,
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected, color: AppColors.primary),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: tabs[_currentTab]),
          ],
        ),
      );
    }
    return AppScaffold(
      body: tabs[_currentTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryLight,
        onDestinationSelected: _openTab,
        destinations: [
          for (final (icon, selected, label) in _destinations)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected, color: AppColors.primary),
              label: label,
            ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    final profile = _services.profile.profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final bank = profile.bank;
    final textTheme = Theme.of(context).textTheme;
    final photo = mediaImageProvider(profile.photo);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: photo,
            child: photo == null
                ? const Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: AppColors.primary,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            profile.name,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(fontSize: 20),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            profile.phone.isNotEmpty
                ? '+91 ${profile.phone}'
                : 'Qwiko Delivery Partner',
            style: textTheme.bodySmall?.copyWith(fontSize: 13),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: StatusBadge.verification(profile.verification)),
        const SizedBox(height: 16),
        _buildStats(profile),
        const SizedBox(height: 16),
        _buildQuickLinks(),
        const SizedBox(height: 16),
        _buildProfileItem(
          Icons.person_outline_rounded,
          'Personal details',
          () => _open(const PersonalDetailsScreen()),
        ),
        _buildProfileItem(
          Icons.two_wheeler_rounded,
          'Vehicle details',
          () => _open(const VehicleDetailsScreen()),
          subtitle: profile.vehicle?.summary ?? 'Not added',
        ),
        _buildProfileItem(
          Icons.description_outlined,
          'Documents',
          () => Navigator.pushNamed(context, AppRoutes.documents),
          subtitle:
              '${profile.uploadedDocumentCount} of ${profile.requiredDocuments.length} uploaded',
        ),
        _buildProfileItem(
          Icons.account_balance_outlined,
          'Bank details',
          () => _open(const BankDetailsScreen()),
          subtitle: bank == null
              ? 'Not added'
              : '${bank.bankName} • A/c ending ${bank.last4}',
        ),
        _buildProfileItem(
          Icons.payments_outlined,
          'Cash in hand',
          () => Navigator.pushNamed(context, AppRoutes.cashInHand),
        ),
        _buildProfileItem(
          Icons.history_rounded,
          'Activity',
          () => Navigator.pushNamed(context, AppRoutes.activityLog),
        ),
        _buildProfileItem(
          Icons.insights_rounded,
          'Performance',
          () => Navigator.pushNamed(context, AppRoutes.performance),
        ),
        _buildProfileItem(
          Icons.notifications_none_rounded,
          'Notifications',
          () => Navigator.pushNamed(context, AppRoutes.notifications),
        ),
        _buildProfileItem(
          Icons.shield_outlined,
          'Safety',
          () => Navigator.pushNamed(context, AppRoutes.safety),
        ),
        _buildProfileItem(
          Icons.help_outline_rounded,
          'Help & support',
          () => Navigator.pushNamed(context, AppRoutes.help),
        ),
        _buildProfileItem(
          Icons.settings_outlined,
          'Settings',
          () => Navigator.pushNamed(context, AppRoutes.settings),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Log out',
          icon: Icons.logout_rounded,
          variant: ButtonVariant.destructive,
          height: 52,
          onPressed: _services.session.isBusy ? null : _logout,
        ),
      ],
    );
  }

  Widget _buildStats(PartnerProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    Widget stat(String label, String value) => Expanded(
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              value,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: textTheme.bodySmall),
          ],
        ),
      ),
    );
    final rating = profile.rating;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          stat('Partner ID', profile.id),
          stat(
            'Rating',
            rating.count == 0
                ? 'New'
                : '${rating.average.toStringAsFixed(1)} ★',
          ),
          stat('Member since', formatMonthYear(profile.joinedOn)),
        ],
      ),
    );
  }

  Widget _buildQuickLinks() {
    Widget link(IconData icon, String label, String route) => Expanded(
      child: Material(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.pushNamed(context, route),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        link(Icons.star_outline_rounded, 'Ratings', AppRoutes.ratings),
        const SizedBox(width: 8),
        link(
          Icons.contact_phone_outlined,
          'Emergency contacts',
          AppRoutes.emergencyContacts,
        ),
        const SizedBox(width: 8),
        link(Icons.account_balance_outlined, 'Payouts', AppRoutes.payouts),
        const SizedBox(width: 8),
        link(
          Icons.local_fire_department_outlined,
          'Incentives',
          AppRoutes.incentives,
        ),
      ],
    );
  }

  Widget _buildProfileItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        tileColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textGrey,
        ),
        onTap: onTap,
      ),
    );
  }
}
