import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_nav.dart';
import 'brand.dart';

/// Shown when a free-tier user opens a paid practice set.
Future<void> showLockedDialog(BuildContext context, {String? practiceSetTitle}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(color: Brand.purple100, shape: BoxShape.circle),
        child: const Icon(Icons.lock_outline, color: Brand.purple, size: 28),
      ),
      title: const Text('Supporters only'),
      content: Text(
        '${practiceSetTitle == null ? 'This practice set is' : '"$practiceSetTitle" is'} '
        'available to Vasis Beats supporters. Donate USD 5 or more to Vasis Studios '
        'and send the receipt to unlock every level.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            AppNav.goTo(AppNav.profile);
          },
          child: const Text('See how to support'),
        ),
      ],
    ),
  );
}

void showBrandSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Platform-support contact, as listed on the website's Help page and in
/// its welcome email.
const String supportEmail = 'mywork.07@outlook.com';

Future<void> launchSupportEmail(BuildContext context, {String? subject}) async {
  final uri = Uri(
    scheme: 'mailto',
    path: supportEmail,
    query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (context.mounted) showBrandSnack(context, 'Support email address copied to clipboard');
  }
}
