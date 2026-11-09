/// Interactive Voice Channel view for Open Mic and Stage Room channels.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';

class VoiceChannelView extends StatelessWidget {
  final ChannelModel channel;

  const VoiceChannelView({
    super.key,
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isStage = channel.voiceRoomType == 'STAGE_ROOM';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
                child: Icon(
                  isStage ? Icons.podcasts : Icons.headset_mic_outlined,
                  size: 38,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                channel.name,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isStage
                    ? 'Chế độ Sân khấu (Stage Room): Thính giả cần giơ tay để được cấp quyền phát biểu.'
                    : 'Chế độ Đàm thoại tự do (Open Mic): Thành viên có quyền thoại có thể bật mic trò chuyện.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              if (channel.canConnectVoice)
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.call_outlined),
                  label: Text(
                    channel.canSpeakVoice
                        ? 'Tham gia phòng thoại (Có quyền bật Mic)'
                        : 'Tham gia với tư cách Thính giả',
                  ),
                )
              else
                const Text(
                  'Bạn không có quyền kết nối vào phòng thoại này.',
                  style: TextStyle(color: AppTheme.error, fontSize: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
