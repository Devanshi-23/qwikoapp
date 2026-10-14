import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialer with 112 filled in. This is the only external
/// launch in the app; it doesn't place the call.
Future<void> call112(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await launchUrl(Uri(scheme: 'tel', path: '112'));
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open the phone dialer.")),
    );
  }
}
