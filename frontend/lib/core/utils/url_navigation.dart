import 'url_navigation_stub.dart'
    if (dart.library.html) 'url_navigation_web.dart';

void openExternalUrlSync(String url) => navigateToExternalUrlSync(url);

Future<bool> openExternalUrl(String url) => navigateToExternalUrl(url);
