import 'package:url_launcher/url_launcher.dart';

/// Apre [url] in una nuova scheda (su web) o nell'app di sistema.
Future<void> openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  } catch (_) {}
}
