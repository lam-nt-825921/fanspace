/// Unit tests for FandomDetailModel JSON deserialization.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/fandom_model.dart';

void main() {
  test('FandomDetailModel parses JSON fields and membership flags', () {
    final json = {
      'id': 'fandom-123',
      'slug': 'kpop-vietnam',
      'name': 'K-Pop Fan Community',
      'description': 'K-Pop fandom description',
      'category': 'Music',
      'admission_mode': 'OPEN',
      'member_count': 250,
      'owner_name': 'Leader',
      'owner_id': 'u-456',
      'is_owner': true,
      'is_member': true,
    };
    final fandom = FandomDetailModel.fromJson(json);
    expect(fandom.slug, 'kpop-vietnam');
    expect(fandom.name, 'K-Pop Fan Community');
    expect(fandom.memberCount, 250);
    expect(fandom.admissionMode, 'OPEN');
    expect(fandom.isOwner, isTrue);
    expect(fandom.isMember, isTrue);
  });
}
