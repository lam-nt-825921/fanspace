/// Unit tests for ClientDetector platform identification.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/client_detector/client_detector.dart';

void main() {
  test('ClientDetector returns a valid platform identifier', () async {
    final clientInfo = await ClientDetector.getClientInfo();
    expect(['WEB', 'MOBILE', 'DESKTOP'].contains(clientInfo.platform), isTrue);
  });
}
