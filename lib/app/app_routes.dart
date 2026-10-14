import 'package:flutter/material.dart';

import '../models/auth.dart';
import '../models/partner.dart';
import 'app_scope.dart';
import 'gallery_samples.dart';
import '../screens/account/account_suspended_screen.dart';
import '../screens/activity/activity_log_screen.dart';
import '../screens/activity/performance_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/demo/component_gallery_screen.dart';
import '../screens/demo/demo_controls_screen.dart';
import '../screens/earnings/incentives_screen.dart';
import '../screens/home/demand_map_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/kyc/kyc_screen.dart';
import '../screens/kyc/verification_pending_screen.dart';
import '../screens/navigation/navigation_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/orders/active_order_screen.dart';
import '../screens/orders/order_details_screen.dart';
import '../screens/profile/documents_screen.dart';
import '../screens/profile/emergency_contacts_screen.dart';
import '../screens/profile/ratings_screen.dart';
import '../screens/safety/report_incident_screen.dart';
import '../screens/safety/safety_screen.dart';
import '../screens/safety/sos_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/demo_intro_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/support/help_support_screen.dart';
import '../screens/support/ticket_screen.dart';
import '../screens/wallet/cash_in_hand_screen.dart';
import '../screens/wallet/payouts_screen.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const intro = '/intro';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';

  /// Argument: the [OtpPurpose] (defaults to sign-in).
  static const otp = '/otp';

  /// Argument: the reset token (`String`) from the OTP step.
  static const resetPassword = '/reset-password';
  static const kyc = '/kyc';
  static const verificationPending = '/verification-pending';

  /// Blocked state: a document was rejected and must be uploaded again.
  static const documentsResubmit = '/account/documents';
  static const accountSuspended = '/account/suspended';
  static const home = '/home';
  static const notifications = '/notifications';

  /// Optional argument: a [HelpRequest] that prefills a support ticket.
  static const help = '/help';

  /// Argument: the ticket id (`String`). Also used for live chats.
  static const ticket = '/help/ticket';
  static const settings = '/settings';

  /// Argument: the order id (`String`).
  static const orderDetails = '/order';
  static const activeOrder = '/active-order';

  /// Turn-by-turn for the active trip's current leg.
  static const navigation = '/active-order/navigation';
  static const documents = '/profile/documents';
  static const emergencyContacts = '/profile/emergency-contacts';
  static const ratings = '/profile/ratings';
  static const cashInHand = '/wallet/cash';
  static const payouts = '/wallet/payouts';
  static const incentives = '/incentives';

  /// Optional argument: the starting [ActivityFilter].
  static const activityLog = '/activity';
  static const performance = '/performance';
  static const demandMap = '/demand';
  static const safety = '/safety';

  /// Countdown, then the alert; opened after the SOS button is held.
  static const sos = '/safety/sos';
  static const reportIncident = '/safety/report';

  /// Demo builds only.
  static const demoControls = '/demo/controls';
  static const componentGallery = '/demo/components';

  /// The account-state gate: where a signed-in partner lands.
  static String forPartner(PartnerProfile partner) =>
      switch (partner.verification) {
        VerificationStatus.verified => home,
        VerificationStatus.newSignup => kyc,
        VerificationStatus.pending => verificationPending,
        VerificationStatus.rejected => documentsResubmit,
        VerificationStatus.suspended => accountSuspended,
      };

  /// Replaces the whole stack with the gate's destination for [partner].
  static void goToAccountHome(
    NavigatorState navigator,
    PartnerProfile partner,
  ) => navigator.pushNamedAndRemoveUntil(forPartner(partner), (_) => false);

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final arguments = settings.arguments;
    final Widget? screen = switch (settings.name) {
      splash => const SplashScreen(),
      intro => const DemoIntroScreen(),
      login => const LoginScreen(),
      signup => const SignupScreen(),
      forgotPassword => const ForgotPasswordScreen(),
      otp => OtpScreen(
        purpose: arguments is OtpPurpose ? arguments : OtpPurpose.signIn,
      ),
      resetPassword => switch (arguments) {
        final String token => ResetPasswordScreen(resetToken: token),
        _ => null,
      },
      kyc => const KycScreen(),
      verificationPending => const VerificationPendingScreen(),
      documentsResubmit => const DocumentsScreen(resubmit: true),
      accountSuspended => const AccountSuspendedScreen(),
      home => const HomeScreen(),
      notifications => const NotificationsScreen(),
      help => HelpSupportScreen(
        request: arguments is HelpRequest ? arguments : null,
      ),
      AppRoutes.settings => const SettingsScreen(),
      activeOrder => const ActiveOrderScreen(),
      navigation => const NavigationScreen(),
      orderDetails => switch (arguments) {
        final String orderId => OrderDetailsScreen(orderId: orderId),
        _ => null,
      },
      documents => const DocumentsScreen(),
      emergencyContacts => const EmergencyContactsScreen(),
      ratings => const RatingsScreen(),
      cashInHand => const CashInHandScreen(),
      payouts => PayoutsScreen(
        highlightId: arguments is String ? arguments : null,
      ),
      incentives => IncentivesScreen(
        openId: arguments is String ? arguments : null,
      ),
      activityLog => ActivityLogScreen(
        filter: arguments is ActivityFilter ? arguments : ActivityFilter.all,
      ),
      performance => const PerformanceScreen(),
      demandMap => const DemandMapScreen(),
      safety => const SafetyScreen(),
      sos => const SosScreen(),
      reportIncident => const ReportIncidentScreen(),
      ticket => switch (arguments) {
        final String id => TicketScreen(ticketId: id),
        _ => null,
      },
      demoControls => const DemoControlsScreen(),
      componentGallery => Builder(
        builder: (context) => ComponentGalleryScreen(
          samples: GallerySamples.fromSeed(context.services.clock.now()),
        ),
      ),
      _ => null,
    };
    if (screen == null) return null;
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => screen,
    );
  }

  static Route<dynamic> onUnknownRoute(RouteSettings settings) =>
      MaterialPageRoute<dynamic>(
        settings: settings,
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Not found')),
          body: const Center(child: Text("This page doesn't exist.")),
        ),
      );
}
