// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void navigateToExternalUrlSync(String url) {
  html.window.location.href = url;
}

Future<bool> navigateToExternalUrl(String url) async {
  html.window.location.href = url;
  return true;
}
