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
    expect(fandom.isPublic, isTrue);
  });

  test('FandomDetailModel copyWith toggles isPublic correctly', () {
    final fandom = FandomDetailModel(
      id: 'f1',
      name: 'Test Fandom',
      slug: 'test-fandom',
      category: 'Music',
      admissionMode: 'OPEN',
      memberCount: 1,
      ownerId: 'u1',
      ownerName: 'Owner',
      isOwner: true,
      isMember: true,
      isPublic: true,
    );

    final updated = fandom.copyWith(isPublic: false);
    expect(updated.isPublic, isFalse);
    expect(updated.name, 'Test Fandom');
    expect(updated.slug, 'test-fandom');
  });

  test('MyFandomsDataModel parses quota and computes isQuotaReached correctly', () {
    final json = {
      'joined': [],
      'managed': [
        {
          'id': 'f1',
          'name': 'F1',
          'slug': 'f1',
          'category': 'Music',
          'member_count': 1,
          'owner_id': 'u1',
          'owner_name': 'Me',
        },
      ],
      'pending_requests': [],
      'quota_used': 5,
      'max_quota': 5,
    };

    final model = MyFandomsDataModel.fromJson(json);
    expect(model.quotaUsed, 5);
    expect(model.maxQuota, 5);
    expect(model.isQuotaReached, isTrue);

    final notReached = MyFandomsDataModel(
      quotaUsed: 3,
      maxQuota: 5,
    );
    expect(notReached.isQuotaReached, isFalse);
  });
}

