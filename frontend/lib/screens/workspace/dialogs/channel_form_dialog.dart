/// Dialog for creating or editing a Fandom communication channel (Text or Voice) with FR-10 governance controls.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';

class ChannelFormDialog extends StatefulWidget {
  final String fandomSlug;
  final ChannelModel? existing;
  final List<RoleModel>? availableRoles;
  final List<MembershipTierModel>? availableTiers;
  final Future<void> Function(ChannelModel saved) onSaved;

  const ChannelFormDialog({
    super.key,
    required this.fandomSlug,
    this.existing,
    this.availableRoles,
    this.availableTiers,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomSlug,
    ChannelModel? existing,
    List<RoleModel>? availableRoles,
    List<MembershipTierModel>? availableTiers,
    required Future<void> Function(ChannelModel saved) onSaved,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChannelFormDialog(
        fandomSlug: fandomSlug,
        existing: existing,
        availableRoles: availableRoles,
        availableTiers: availableTiers,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<ChannelFormDialog> createState() => _ChannelFormDialogState();
}

class _ChannelFormDialogState extends State<ChannelFormDialog> {
  final ApiClient _api = ApiClient();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _topicCtrl;
  late final TextEditingController _slowModeCtrl;
  late final TextEditingController _maxMembersCtrl;

  late String _selectedType;
  late bool _isAnnouncement;
  late bool _isMembershipOnly;
  late String _voiceRoomType;
  String? _requiredRoleId;
  late List<String> _selectedRoleIds;
  late int _rolePermissionsBitmask;
  late int _membershipPermissionsBitmask;
  late int _minMembershipTierLevel;
  late bool _membershipBypassSlowmode;
  List<RoleModel> _regularRoles = [];
  List<MembershipTierModel> _membershipTiers = [];
  String? _dialogError;
  bool _isSubmitting = false;

  static const List<int> _slowModePresets = [0, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _topicCtrl = TextEditingController(text: existing?.topic ?? '');
    _slowModeCtrl = TextEditingController(
      text: (existing?.slowModeSeconds ?? 0).toString(),
    );
    _maxMembersCtrl = TextEditingController(
      text: (existing?.maxMembers ?? 0).toString(),
    );
    _selectedType = existing?.type ?? 'TEXT';
    _isAnnouncement = existing?.isAnnouncement ?? false;
    _isMembershipOnly = existing?.isMembershipOnly ?? false;
    _voiceRoomType = existing?.voiceRoomType ?? 'OPEN_MIC';
    _requiredRoleId = existing?.requiredRoleId;
    _selectedRoleIds = List<String>.from(existing?.allowedRoleIds ?? const []);
    if (_selectedRoleIds.isEmpty && _requiredRoleId != null) {
      _selectedRoleIds.add(_requiredRoleId!);
    }
    _rolePermissionsBitmask =
        existing?.rolePermissionsBitmask ?? ChannelPermissionBit.defaultChannelMask;
    _membershipPermissionsBitmask =
        existing?.membershipPermissionsBitmask ??
        ChannelPermissionBit.defaultChannelMask;
    _minMembershipTierLevel = existing?.minMembershipTierLevel ?? 0;
    _membershipBypassSlowmode = existing?.membershipBypassSlowmode ?? false;
    _regularRoles = (widget.availableRoles ?? [])
        .where((r) => !r.isMembershipTier)
        .toList();
    _membershipTiers = List<MembershipTierModel>.from(
      widget.availableTiers ?? [],
    )..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));

    if (widget.availableRoles == null || widget.availableTiers == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadGovernanceOptions();
      });
    }
  }

  Future<void> _loadGovernanceOptions() async {
    FandomProvider? provider;
    try {
      provider = context.read<FandomProvider>();
    } catch (_) {
      return;
    }

    if (widget.availableRoles == null) {
      try {
        final roles = await provider.fetchRoles(widget.fandomSlug);
        if (mounted) {
          setState(() {
            _regularRoles = roles.where((r) => !r.isMembershipTier).toList();
          });
        }
      } catch (_) {}
    }

    if (widget.availableTiers == null) {
      try {
        final memberships = await provider.fetchMemberships(widget.fandomSlug);
        if (mounted) {
          final sorted = List<MembershipTierModel>.from(memberships.tiers)
            ..sort((a, b) => a.tierLevel.compareTo(b.tierLevel));
          setState(() {
            _membershipTiers = sorted;
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _topicCtrl.dispose();
    _slowModeCtrl.dispose();
    _maxMembersCtrl.dispose();
    super.dispose();
  }

  void _toggleRoleSelection(String roleId, bool selected) {
    setState(() {
      if (selected) {
        if (!_selectedRoleIds.contains(roleId)) {
          _selectedRoleIds.add(roleId);
        }
      } else {
        _selectedRoleIds.remove(roleId);
      }
      _requiredRoleId =
          _selectedRoleIds.isNotEmpty ? _selectedRoleIds.first : null;
    });
  }

  void _togglePermissionBit({
    required bool isRoleBitmask,
    required int bit,
    required bool enabled,
  }) {
    setState(() {
      if (isRoleBitmask) {
        if (enabled) {
          _rolePermissionsBitmask |= bit;
        } else {
          _rolePermissionsBitmask &= ~bit;
        }
      } else {
        if (enabled) {
          _membershipPermissionsBitmask |= bit;
        } else {
          _membershipPermissionsBitmask &= ~bit;
        }
        if (bit == ChannelPermissionBit.bypassSlowmode) {
          _membershipBypassSlowmode = enabled;
        }
      }
    });
  }

  Future<void> _handleSubmit() async {
    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.length < 2) {
      setState(() {
        _dialogError = 'Tên kênh phải có ít nhất 2 ký tự.';
      });
      return;
    }
    final slowSec = (int.tryParse(_slowModeCtrl.text.trim()) ?? 0).clamp(0, 21600);
    final maxMem = (int.tryParse(_maxMembersCtrl.text.trim()) ?? 0).clamp(0, 100000);

    setState(() {
      _isSubmitting = true;
      _dialogError = null;
    });

    try {
      final effectiveMinTier =
          _isMembershipOnly ? _minMembershipTierLevel : 0;
      final effectiveBypassSlowmode =
          _selectedType == 'TEXT' ? _membershipBypassSlowmode : false;
      final primaryRoleId =
          _selectedRoleIds.isNotEmpty ? _selectedRoleIds.first : _requiredRoleId;

      ChannelModel result;
      if (widget.existing == null) {
        final res = await _api.dio.post(
          '/api/v1/fandoms/${widget.fandomSlug}/channels',
          data: {
            'name': trimmedName,
            'type': _selectedType,
            'topic': _topicCtrl.text.trim().isEmpty
                ? null
                : _topicCtrl.text.trim(),
            'required_role_id': primaryRoleId,
            'allowed_role_ids': _selectedRoleIds,
            'max_members': maxMem,
            'role_permissions_bitmask': _rolePermissionsBitmask,
            'membership_permissions_bitmask': _membershipPermissionsBitmask,
            'is_announcement':
                _selectedType == 'TEXT' ? _isAnnouncement : false,
            'is_membership_only': _isMembershipOnly,
            'min_membership_tier_level': effectiveMinTier,
            'membership_bypass_slowmode': effectiveBypassSlowmode,
            'slow_mode_seconds': _selectedType == 'TEXT' ? slowSec : 0,
            'voice_room_type':
                _selectedType == 'VOICE' ? _voiceRoomType : null,
          },
        );
        result = ChannelModel.fromJson(res.data as Map<String, dynamic>);
      } else {
        final res = await _api.dio.put(
          '/api/v1/fandoms/${widget.fandomSlug}/channels/${widget.existing!.id}',
          data: {
            'name': trimmedName,
            'topic': _topicCtrl.text.trim(),
            'required_role_id': primaryRoleId,
            'allowed_role_ids': _selectedRoleIds,
            'max_members': maxMem,
            'role_permissions_bitmask': _rolePermissionsBitmask,
            'membership_permissions_bitmask': _membershipPermissionsBitmask,
            'is_announcement':
                _selectedType == 'TEXT' ? _isAnnouncement : null,
            'is_membership_only': _isMembershipOnly,
            'min_membership_tier_level': effectiveMinTier,
            'membership_bypass_slowmode': effectiveBypassSlowmode,
            'slow_mode_seconds': _selectedType == 'TEXT' ? slowSec : null,
            'voice_room_type':
                _selectedType == 'VOICE' ? _voiceRoomType : null,
          },
        );
        result = ChannelModel.fromJson(res.data as Map<String, dynamic>);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onSaved(result);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : null;
      setState(() {
        _dialogError = detail ?? 'Không thể lưu kênh.';
        _isSubmitting = false;
      });
    }
  }

  Widget _buildGranularPermissionsSection({
    required BuildContext context,
    required Key sectionKey,
    required String title,
    required int currentBitmask,
    required bool isRoleBitmask,
  }) {
    final palette = context.palette;
    final prefix = isRoleBitmask ? 'role_perm' : 'membership_perm';

    final items = <(int, String)>[
      (ChannelPermissionBit.readMessages, 'Xem kênh & Đọc lịch sử'),
      if (_selectedType == 'TEXT') ...[
        (ChannelPermissionBit.sendMessages, 'Gửi tin nhắn thảo luận'),
        (ChannelPermissionBit.attachFiles, 'Đính kèm ảnh & tệp'),
        (ChannelPermissionBit.embedLinks, 'Chèn liên kết (Link)'),
        (ChannelPermissionBit.bypassSlowmode, 'Miễn giới hạn Slow-mode'),
      ] else ...[
        (ChannelPermissionBit.voiceConnect, 'Kết nối phòng thoại'),
        (ChannelPermissionBit.voiceSpeak, 'Bật mic phát biểu'),
      ],
    ];

    return Container(
      key: sectionKey,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items.map((entry) {
              final bit = entry.$1;
              final label = entry.$2;
              final isChecked = (currentBitmask & bit) != 0;
              return FilterChip(
                key: Key('chk_${prefix}_$bit'),
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: isChecked,
                onSelected: (val) => _togglePermissionBit(
                  isRoleBitmask: isRoleBitmask,
                  bit: bit,
                  enabled: val,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        widget.existing == null
            ? 'Tạo kênh giao tiếp mới'
            : 'Chỉnh sửa cấu hình kênh',
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_dialogError != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _dialogError!,
                    style: const TextStyle(color: AppTheme.error, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.existing == null) ...[
                Text(
                  'Loại kênh',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'TEXT',
                      icon: Icon(Icons.tag, size: 18),
                      label: Text('Kênh Văn bản'),
                    ),
                    ButtonSegment(
                      value: 'VOICE',
                      icon: Icon(Icons.volume_up_outlined, size: 18),
                      label: Text('Kênh Thoại'),
                    ),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedType = val.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Tên kênh',
                  hintText: 'Ví dụ: chat-chung, góc-fanart',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _topicCtrl,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Chủ đề / Mô tả kênh',
                  hintText: 'Giới thiệu ngắn về mục đích của kênh',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('input_channel_max_members'),
                controller: _maxMembersCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Giới hạn số người tham gia đồng thời (0 = Không giới hạn)',
                  hintText: 'Ví dụ: 0, 50, 100',
                  prefixIcon: Icon(Icons.people_alt_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Phân quyền Vai trò (Role thường)',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              KeyedSubtree(
                key: ValueKey('roles_loaded_${_regularRoles.length}'),
                child: DropdownButtonFormField<String?>(
                  key: const Key('dropdown_channel_required_role'),
                  initialValue: (_requiredRoleId != null &&
                          _regularRoles.any((r) => r.id == _requiredRoleId))
                      ? _requiredRoleId
                      : null,
                  isExpanded: true,
                  dropdownColor: palette.surfaceElevated,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Giới hạn theo Vai trò nội bộ',
                    helperText:
                        'Chỉ hiển thị Role thường — Có thể chọn nhiều Role ở danh sách chip bên dưới',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Mọi thành viên (Không giới hạn Role)'),
                    ),
                    ..._regularRoles.map(
                      (role) => DropdownMenuItem<String?>(
                        value: role.id,
                        child: Text(role.name),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _requiredRoleId = val;
                      if (val == null) {
                        _selectedRoleIds.clear();
                      } else if (!_selectedRoleIds.contains(val)) {
                        _selectedRoleIds.add(val);
                      }
                    });
                  },
                ),
              ),
              if (_regularRoles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _regularRoles.map((role) {
                    final isSelected = _selectedRoleIds.contains(role.id);
                    return FilterChip(
                      key: Key('chip_channel_role_${role.id}'),
                      label: Text(
                        role.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: isSelected,
                      onSelected: (selected) =>
                          _toggleRoleSelection(role.id, selected),
                    );
                  }).toList(),
                ),
              ],
              _buildGranularPermissionsSection(
                context: context,
                sectionKey: const Key('section_channel_role_permissions'),
                title: 'Quyền chi tiết trên kênh cho các Role được chọn:',
                currentBitmask: _rolePermissionsBitmask,
                isRoleBitmask: true,
              ),
              const SizedBox(height: 14),
              Material(
                key: const Key('card_channel_membership_priority'),
                color: Colors.amber.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Colors.amber.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ưu tiên Hội viên (Membership Priority)',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        key: const Key('switch_channel_membership_only'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Kênh đặc quyền Hội viên VIP',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Chỉ thành viên có Gói Hội viên hợp lệ hoặc Quản trị viên mới được truy cập',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        value: _isMembershipOnly,
                        onChanged: (val) {
                          setState(() => _isMembershipOnly = val);
                        },
                      ),
                      if (_isMembershipOnly) ...[
                        const SizedBox(height: 6),
                        DropdownButtonFormField<int>(
                          key: const Key('dropdown_channel_min_tier'),
                          initialValue: _minMembershipTierLevel.clamp(0, 4),
                          isExpanded: true,
                          dropdownColor: palette.surfaceElevated,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Yêu cầu Hạng Hội viên tối thiểu',
                          ),
                          items: List.generate(5, (level) {
                            if (level == 0) {
                              return const DropdownMenuItem<int>(
                                value: 0,
                                child: Text('Mọi hạng Hội viên (Tier ≥ 1)'),
                              );
                            }
                            final matched = _membershipTiers
                                .where((t) => t.tierLevel == level)
                                .toList();
                            final tierSuffix = matched.isNotEmpty
                                ? ' (${matched.map((t) => t.name).join(', ')})'
                                : '';
                            return DropdownMenuItem<int>(
                              value: level,
                              child: Text('Từ Hạng $level trở lên$tierSuffix'),
                            );
                          }),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _minMembershipTierLevel = val);
                            }
                          },
                        ),
                      ],
                      if (_selectedType == 'TEXT') ...[
                        const SizedBox(height: 4),
                        SwitchListTile(
                          key: const Key(
                            'switch_channel_membership_bypass_slowmode',
                          ),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Hội viên VIP bỏ qua Slow-mode',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Cho phép Hội viên có đặc quyền Kênh ưu tiên nhắn tin không cần chờ slow-mode',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          value: _membershipBypassSlowmode,
                          onChanged: (val) {
                            setState(() {
                              _membershipBypassSlowmode = val;
                              if (val) {
                                _membershipPermissionsBitmask |=
                                    ChannelPermissionBit.bypassSlowmode;
                              } else {
                                _membershipPermissionsBitmask &=
                                    ~ChannelPermissionBit.bypassSlowmode;
                              }
                            });
                          },
                        ),
                      ],
                      _buildGranularPermissionsSection(
                        context: context,
                        sectionKey: const Key(
                          'section_channel_membership_permissions',
                        ),
                        title: 'Quyền chi tiết trên kênh cho Hội viên VIP:',
                        currentBitmask: _membershipPermissionsBitmask,
                        isRoleBitmask: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedType == 'TEXT') ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Kênh thông báo một chiều',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Chỉ Chủ Fandom và Ban quản trị được phép gửi tin nhắn',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: _isAnnouncement,
                  onChanged: (val) {
                    setState(() => _isAnnouncement = val);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('input_channel_slow_mode'),
                  controller: _slowModeCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Giới hạn tốc độ nhắn tin (Slow-mode giây)',
                    hintText: '0 = Không giới hạn',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _slowModePresets.map((sec) {
                    final label = sec == 0 ? 'Tắt (0s)' : '${sec}s';
                    final isCurrent =
                        int.tryParse(_slowModeCtrl.text.trim()) == sec;
                    return ActionChip(
                      key: Key('chip_slowmode_preset_$sec'),
                      backgroundColor: isCurrent
                          ? AppTheme.primary.withValues(alpha: 0.18)
                          : null,
                      label: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: isCurrent
                              ? AppTheme.primary
                              : palette.textSecondary,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _slowModeCtrl.text = sec.toString();
                        });
                      },
                    );
                  }).toList(),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _voiceRoomType,
                  isExpanded: true,
                  dropdownColor: palette.surfaceElevated,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Chế độ phòng thoại',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'OPEN_MIC',
                      child: Text('Đàm thoại tự do (Open Mic)'),
                    ),
                    DropdownMenuItem(
                      value: 'STAGE_ROOM',
                      child: Text(
                        'Sân khấu phát biểu (Stage Room - Giơ tay)',
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _voiceRoomType = val);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: Text(widget.existing == null ? 'Tạo kênh' : 'Lưu thay đổi'),
        ),
      ],
    );
  }
}
