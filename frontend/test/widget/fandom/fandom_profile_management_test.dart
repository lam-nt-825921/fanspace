/// Widget tests for Fandom Profile & Appearance Management (FR-07).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/providers/fandom_provider.dart';
import 'package:frontend/screens/workspace/management/fandom_general_settings_tab.dart';

class FakeProfileFandomProvider extends FandomProvider {
  Map<String, dynamic>? lastUpdatePayload;
  int updateCallCount = 0;
  bool shouldSucceed = true;

  @override
  Future<Map<String, dynamic>> updateFandomProfile(
    String identifier, {
    String? name,
    String? description,
    String? category,
    String? avatarUrl,
    String? bannerUrl,
    List<String>? illustrationUrls,
    String? admissionMode,
    String? rulesTos,
  }) async {
    updateCallCount++;
    lastUpdatePayload = {
      'identifier': identifier,
      'name': name,
      'description': description,
      'category': category,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'illustration_urls': illustrationUrls,
      'admission_mode': admissionMode,
      'rules_tos': rulesTos,
    };

    if (shouldSucceed) {
      final updated = FandomDetailModel(
        id: identifier,
        name: name ?? 'Default Fandom',
        slug: 'sky-music',
        description: description,
        category: category ?? 'Âm nhạc',
        avatarUrl: avatarUrl,
        bannerUrl: bannerUrl,
        illustrationUrls: illustrationUrls ?? const [],
        admissionMode: admissionMode ?? 'OPEN',
        rulesTos: rulesTos,
        memberCount: 150,
        ownerId: 'owner-1',
        ownerName: 'Ca Sĩ A',
        isOwner: true,
        isMember: true,
      );
      return {
        'success': true,
        'fandom': updated,
        'message': 'Đã lưu thay đổi hồ sơ Fandom.',
      };
    } else {
      return {
        'success': false,
        'error': 'Không thể cập nhật hồ sơ.',
      };
    }
  }

  @override
  Future<Map<String, dynamic>> updateFandomVisibility(
    String identifier,
    bool isPublic,
  ) async {
    return {
      'success': true,
      'is_public': isPublic,
      'message': 'Đã cập nhật trạng thái hiển thị.',
    };
  }
}

FandomDetailModel _buildSampleFandom() {
  return FandomDetailModel(
    id: 'fandom-100',
    name: 'Cộng Đồng Sky Music',
    slug: 'sky-music',
    description: 'Không gian giao lưu âm nhạc dành cho người hâm mộ',
    category: 'Âm nhạc',
    admissionMode: 'OPEN',
    isPublic: true,
    rulesTos: '1. Luôn tôn trọng nghệ sĩ và các thành viên.',
    memberCount: 150,
    ownerId: 'owner-1',
    ownerName: 'Ca Sĩ A',
    isOwner: true,
    isMember: true,
  );
}

void main() {
  group('FandomGeneralSettingsTab Profile Appearance Management Tests', () {
    testWidgets('renders initial fandom metadata and updates fields on save',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeProvider = FakeProfileFandomProvider();
      FandomDetailModel? updatedFandomResult;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<FandomProvider>.value(
            value: fakeProvider,
            child: Scaffold(
              body: FandomGeneralSettingsTab(
                fandom: _buildSampleFandom(),
                onFandomUpdated: (updated) {
                  updatedFandomResult = updated;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify initial fields loaded
      expect(find.text('Cộng Đồng Sky Music'), findsOneWidget);
      expect(find.text('Không gian giao lưu âm nhạc dành cho người hâm mộ'),
          findsOneWidget);
      expect(find.text('Âm nhạc'), findsOneWidget);
      expect(find.text('Gia nhập tự do'), findsOneWidget);
      expect(find.text('1. Luôn tôn trọng nghệ sĩ và các thành viên.'),
          findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);

      // 2. Edit name, description, and rules
      await tester.enterText(
        find.byKey(const Key('field_fandom_name')),
        'Cộng Đồng Sky Music Mới',
      );
      await tester.enterText(
        find.byKey(const Key('field_fandom_description')),
        'Mô tả mới về cộng đồng',
      );
      await tester.enterText(
        find.byKey(const Key('field_fandom_rules')),
        'Nội quy mới đã được cập nhật',
      );

      // 3. Switch admission mode to APPROVAL
      await tester.tap(find.text('Phê duyệt xét tuyển'));
      await tester.pumpAndSettle();

      // 4. Scroll down using drag to reveal save button
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_save_fandom_profile')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_save_fandom_profile')));
      await tester.pumpAndSettle();

      // 5. Verify provider call and payload
      expect(fakeProvider.updateCallCount, 1);
      expect(
        fakeProvider.lastUpdatePayload?['name'],
        'Cộng Đồng Sky Music Mới',
      );
      expect(
        fakeProvider.lastUpdatePayload?['description'],
        'Mô tả mới về cộng đồng',
      );
      expect(
        fakeProvider.lastUpdatePayload?['rules_tos'],
        'Nội quy mới đã được cập nhật',
      );
      expect(
        fakeProvider.lastUpdatePayload?['admission_mode'],
        'APPROVAL',
      );

      // 6. Verify SnackBar feedback and callback
      expect(find.text('Đã lưu thay đổi hồ sơ Fandom.'), findsOneWidget);
      expect(updatedFandomResult?.name, 'Cộng Đồng Sky Music Mới');
    });
  });
}
