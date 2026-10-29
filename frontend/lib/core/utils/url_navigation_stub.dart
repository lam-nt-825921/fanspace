import 'package:url_launcher/url_launcher.dart';

void navigateToExternalUrlSync(String url) {
  final uri = Uri.parse(url);
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> navigateToExternalUrl(String url) async {
  final uri = Uri.parse(url);
  return await launchUrl(uri, mode: LaunchMode.externalApplication);
}
