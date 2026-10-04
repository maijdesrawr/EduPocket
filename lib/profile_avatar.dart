import 'package:flutter/material.dart';

import 'profile_service.dart';

class ProfileAvatar extends StatefulWidget {
  final String role;
  final String userId;
  final double radius;
  final IconData fallbackIcon;
  final Color iconColor;
  final Color backgroundColor;

  const ProfileAvatar({
    super.key,
    required this.role,
    required this.userId,
    this.radius = 26,
    this.fallbackIcon = Icons.person,
    this.iconColor = Colors.white,
    this.backgroundColor = Colors.grey,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.role != widget.role) {
      _loadPhoto();
    }
  }

  Future<void> _loadPhoto() async {
    try {
      final profile = await ProfileService.fetchProfile(
        role: widget.role,
        id: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _photoUrl = profile.photoUrl;
      });
    } catch (_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final double iconSize = widget.radius;
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      foregroundImage: hasPhoto ? NetworkImage(_photoUrl!) : null,
      child: Icon(
        widget.fallbackIcon,
        size: iconSize,
        color: widget.iconColor,
      ),
    );
  }
}

