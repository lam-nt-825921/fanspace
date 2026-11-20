/// Widget tests for FR-11 (UC-06): Real-time Voice Room (Open Mic & Stage Room via Agora RTC).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/screens/workspace/widgets/voice_channel_view.dart';

void main() {
  Widget wrapApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );
  }

  testWidgets(
    'VoiceChannelView renders Stage Room speakers, listeners, raise-hand queue, and moderator controls',
    (tester) async {
      final stageChannel = ChannelModel(
        id: 'ch-voice-stage',
        fandomId: 'f-1',
        name: 'Sân Khấu Đêm Nhạc',
        type: 'VOICE',
        voiceRoomType: 'STAGE_ROOM',
        maxMembers: 50,
        myPermissions: const {
          FandomPermission.viewChannel,
          FandomPermission.voiceConnect,
          FandomPermission.voiceSpeak,
          FandomPermission.moderateChat,
        },
      );

      final initialState = VoiceRoomStateModel(
        channelId: 'ch-voice-stage',
        fandomId: 'f-1',
        voiceRoomType: 'STAGE_ROOM',
        maxMembers: 50,
        activeCount: 2,
        raisedHandUserIds: const ['u-fan-1'],
        participants: const [
          VoiceParticipantModel(
            userId: 'u-host',
            username: 'host_sky',
            displayName: 'Host Sky',
            role: 'SPEAKER',
            isMuted: false,
            isOwner: true,
          ),
          VoiceParticipantModel(
            userId: 'u-fan-1',
            username: 'fan_one',
            displayName: 'Fan Một',
            role: 'LISTENER',
            isMuted: true,
            isHandRaised: true,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapApp(
          VoiceChannelView(
            channel: stageChannel,
            initialRoomState: initialState,
            initialConnected: true,
            currentUserId: 'u-host',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifies channel header and participant counts
      expect(find.text('Sân Khấu Đêm Nhạc'), findsOneWidget);
      expect(find.text('Host Sky'), findsOneWidget);
      expect(find.text('Fan Một'), findsWidgets);

      // Verifies Moderator Mute All button and Raise Hand approval button exist
      expect(find.byKey(const Key('btn_voice_mute_all')), findsOneWidget);
      expect(
        find.byKey(const Key('btn_voice_approve_speaker_u-fan-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('btn_voice_toggle_mic')), findsOneWidget);
      expect(find.byKey(const Key('btn_voice_leave')), findsOneWidget);
    },
  );

  testWidgets(
    'VoiceChannelView renders Listener Raise Hand button in Stage Room when connected as listener',
    (tester) async {
      final stageChannel = ChannelModel(
        id: 'ch-voice-stage',
        fandomId: 'f-1',
        name: 'Sân Khấu Đêm Nhạc',
        type: 'VOICE',
        voiceRoomType: 'STAGE_ROOM',
        myPermissions: const {
          FandomPermission.viewChannel,
          FandomPermission.voiceConnect,
        },
      );

      final initialState = VoiceRoomStateModel(
        channelId: 'ch-voice-stage',
        fandomId: 'f-1',
        voiceRoomType: 'STAGE_ROOM',
        maxMembers: 0,
        activeCount: 1,
        raisedHandUserIds: const [],
        participants: const [
          VoiceParticipantModel(
            userId: 'u-fan-2',
            username: 'fan_two',
            displayName: 'Fan Hai',
            role: 'LISTENER',
            isMuted: true,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapApp(
          VoiceChannelView(
            channel: stageChannel,
            initialRoomState: initialState,
            initialConnected: true,
            currentUserId: 'u-fan-2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_voice_raise_hand')), findsOneWidget);
      expect(find.byKey(const Key('btn_voice_mute_all')), findsNothing);
    },
  );

  testWidgets(
    'VoiceChannelView toggles Deafen mode on and off',
    (tester) async {
      final channel = ChannelModel(
        id: 'ch-voice-1',
        fandomId: 'f-1',
        name: 'Phòng Voice Fan',
        type: 'VOICE',
        voiceRoomType: 'OPEN_MIC',
        myPermissions: const {
          FandomPermission.viewChannel,
          FandomPermission.voiceConnect,
          FandomPermission.voiceSpeak,
        },
      );

      final initialState = VoiceRoomStateModel(
        channelId: 'ch-voice-1',
        fandomId: 'f-1',
        voiceRoomType: 'OPEN_MIC',
        participants: const [
          VoiceParticipantModel(
            userId: 'u-self',
            username: 'me',
            displayName: 'My Name',
            role: 'SPEAKER',
            isMuted: false,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapApp(
          VoiceChannelView(
            channel: channel,
            initialRoomState: initialState,
            initialConnected: true,
            currentUserId: 'u-self',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final deafenBtn = find.byKey(const Key('btn_voice_toggle_deafen'));
      expect(deafenBtn, findsOneWidget);
      expect(find.text('Tắt loa phòng (Deafen)'), findsOneWidget);

      // Tap to toggle deafen on
      await tester.tap(deafenBtn);
      await tester.pumpAndSettle();

      expect(find.text('Bật loa phòng'), findsOneWidget);

      // Tap to toggle deafen off
      await tester.tap(deafenBtn);
      await tester.pumpAndSettle();

      expect(find.text('Tắt loa phòng (Deafen)'), findsOneWidget);
    },
  );

  testWidgets(
    'VoiceChannelView opens User Audio Dialog and adjusts volume slider, local mute, and server moderation',
    (tester) async {
      final channel = ChannelModel(
        id: 'ch-voice-mod',
        fandomId: 'f-1',
        name: 'Phòng Ban Quản Trị',
        type: 'VOICE',
        voiceRoomType: 'STAGE_ROOM',
        myPermissions: const {
          FandomPermission.viewChannel,
          FandomPermission.voiceConnect,
          FandomPermission.voiceSpeak,
          FandomPermission.moderateChat,
        },
      );

      final initialState = VoiceRoomStateModel(
        channelId: 'ch-voice-mod',
        fandomId: 'f-1',
        voiceRoomType: 'STAGE_ROOM',
        participants: const [
          VoiceParticipantModel(
            userId: 'u-host',
            username: 'host',
            displayName: 'Host User',
            role: 'SPEAKER',
            isMuted: false,
            isOwner: true,
          ),
          VoiceParticipantModel(
            userId: 'u-target',
            username: 'speaker_b',
            displayName: 'Speaker B',
            role: 'SPEAKER',
            isMuted: false,
            isOwner: false,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapApp(
          VoiceChannelView(
            channel: channel,
            initialRoomState: initialState,
            initialConnected: true,
            currentUserId: 'u-host',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Audio settings button for target user
      final audioSettingsBtn = find.byKey(
        const Key('btn_voice_audio_settings_u-target'),
      );
      expect(audioSettingsBtn, findsOneWidget);

      // Open audio settings dialog
      await tester.tap(audioSettingsBtn);
      await tester.pumpAndSettle();

      // Verifies Dialog elements: Volume slider, Local mute switch, and Moderator server controls
      expect(find.text('Speaker B'), findsWidgets);
      expect(find.byKey(const Key('slider_voice_volume_u-target')), findsOneWidget);
      expect(find.byKey(const Key('switch_voice_local_mute_u-target')), findsOneWidget);
      expect(find.byKey(const Key('btn_voice_server_mute_u-target')), findsOneWidget);
      expect(find.byKey(const Key('btn_voice_demote_listener_u-target')), findsOneWidget);

      // Toggle local 1-way mute
      await tester.tap(find.byKey(const Key('switch_voice_local_mute_u-target')));
      await tester.pumpAndSettle();

      // Close dialog
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('slider_voice_volume_u-target')), findsNothing);
    },
  );
}
