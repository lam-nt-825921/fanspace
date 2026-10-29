export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart'
    if (dart.library.html) 'url_strategy_web.dart';
