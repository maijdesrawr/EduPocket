import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'app_session_service.dart';
import 'login.dart';
import 'profile_authenticator.dart';
import 'profile_email_service.dart';
import 'profile_password_change.dart';
import 'profile_pin.dart';
import 'profile_service.dart';
import 'profile_verified_email.dart';

class CashierProfileScreen extends StatefulWidget {
  final String cashierId;
  final String cashierName;

  const CashierProfileScreen({
    super.key,
    required this.cashierId,
    required this.cashierName,
  });

  @override
  State<CashierProfileScreen> createState() => _CashierProfileScreenState();
}

class _CashierProfileScreenState extends State<CashierProfileScreen> {
  static const Color _panelRed = Color(0xFFC62828);
  static const Color _vividRed = Color(0xFFCF302E);

  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isUploading = false;
  UserProfileData? _profile;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'profile_view',
        details: const {'profile': 'cashier'},
      ),
    );
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.fetchProfile(
        role: 'cashier',
        id: widget.cashierId,
      );

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      if (_profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Unable to connect to EduPocket. Check the server connection and try again.',
            ),
            action: SnackBarAction(label: 'Retry', onPressed: _loadProfile),
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1200,
      );

      if (picked == null) return;

      var uploadPath = picked.path;

      try {
        final cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 90,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: _vividRed,
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: _vividRed,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              aspectRatioLockEnabled: false,
            ),
          ],
        );

        if (cropped != null) {
          uploadPath = cropped.path;
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Crop failed. Using original image.'),
            ),
          );
        }
      }

      setState(() => _isUploading = true);

      try {
        final updated = await ProfileService.uploadPhoto(
          role: 'cashier',
          id: widget.cashierId,
          file: File(uploadPath),
        );

        if (!mounted) return;

        setState(() => _profile = updated);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      } finally {
        if (mounted) {
          setState(() => _isUploading = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image error: $e')),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (_) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _vividRed,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = (_profile?.name.isNotEmpty == true)
        ? _profile!.name
        : widget.cashierName;
    final displayCashierId =
        (_profile?.id.isNotEmpty == true) ? _profile!.id : widget.cashierId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final width = constraints.maxWidth;
        final panelTop =
            (constraints.maxHeight * 0.32).clamp(190.0, 230.0).toDouble();
        final avatarSize = (width * 0.28).clamp(84.0, 100.0).toDouble();
        final avatarTop = panelTop - (avatarSize / 2);
        final titleTop = avatarTop - 30;
        final logoHeight = (width * 0.18).clamp(54.0, 62.0).toDouble();
        final logoTop = (titleTop - logoHeight - (width * 0.13))
            .clamp(mediaQuery.padding.top + 8, double.infinity)
            .toDouble();
        final horizontalPadding = (width * 0.09).clamp(26.0, 34.0);
        final contentTop = panelTop + (width * 0.215);
        final bottomInset = mediaQuery.padding.bottom + 112;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            Positioned.fill(
              top: panelTop,
              child: Container(
                decoration: const BoxDecoration(
                  color: _panelRed,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(46),
                    topRight: Radius.circular(46),
                  ),
                ),
              ),
            ),
            Positioned(
              top: logoTop,
              left: 0,
              right: 0,
              child: Center(
                child: Image.asset(
                  'assets/redlogo.png',
                  height: logoHeight,
                ),
              ),
            ),
            Positioned(
              top: titleTop,
              left: 0,
              right: 0,
              child: const Text(
                'Profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF651718),
                ),
              ),
            ),
            Positioned(
              top: avatarTop,
              left: 0,
              right: 0,
              child: Center(child: _buildAvatar(avatarSize)),
            ),
            Positioned(
              top: contentTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        bottomInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Account Information',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _infoCard('Name', displayName),
                          const SizedBox(height: 14),
                          _infoCard('Cashier ID', displayCashierId),
                          const SizedBox(height: 14),
                          _CashierEmailField(
                            userId: widget.cashierId,
                            userName: displayName,
                          ),
                          const SizedBox(height: 16),
                          ProfileAuthenticatorButton(
                            role: 'cashier',
                            userId: widget.cashierId,
                          ),
                          const SizedBox(height: 12),
                          ProfilePinButton(
                            role: 'cashier',
                            userId: widget.cashierId,
                          ),
                          const SizedBox(height: 12),
                          _profileActionButton(
                            label: 'Change Password',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProfilePasswordChangePage(
                                    role: 'cashier',
                                    userId: widget.cashierId,
                                    userName: displayName,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _profileActionButton(
                            label: 'Log Out',
                            onPressed: _showLogoutDialog,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatar(double size) {
    final image = (_profile?.photoUrl != null && _profile!.photoUrl!.isNotEmpty)
        ? NetworkImage(_profile!.photoUrl!)
        : null;

    return SizedBox(
      width: size + 24,
      height: size + 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xFFF5E9E7),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: const Color(0xFFF5E9E7),
                backgroundImage: image,
                child: image == null
                    ? Icon(
                        Icons.person,
                        size: size * 0.54,
                        color: _vividRed,
                      )
                    : null,
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 4,
            child: Material(
              color: Colors.white,
              elevation: 3,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _isUploading ? null : _pickAndUploadPhoto,
                child: Semantics(
                  button: true,
                  label: 'Change profile photo',
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: _isUploading
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _vividRed,
                              ),
                            )
                          : const Icon(
                              Icons.add,
                              size: 18,
                              color: _vividRed,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 30,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: const Color(0xFFF1B6AB),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF794243),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: SizedBox(
        width: 256,
        height: 44,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _vividRed,
            elevation: 7,
            shadowColor: const Color(0x66000000),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _CashierEmailField extends StatefulWidget {
  final String userId;
  final String userName;

  const _CashierEmailField({
    required this.userId,
    required this.userName,
  });

  @override
  State<_CashierEmailField> createState() => _CashierEmailFieldState();
}

class _CashierEmailFieldState extends State<_CashierEmailField> {
  static const Color _red = Color(0xFFCF302E);

  final ProfileEmailApi _service = ProfileEmailService();
  VerifiedEmailStatus? _status;
  bool _loading = true;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void didUpdateWidget(covariant _CashierEmailField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    final generation = ++_requestGeneration;
    if (mounted) setState(() => _loading = true);

    try {
      final status = await _service.getStatus(
        role: 'cashier',
        id: widget.userId,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _status = null;
        _loading = false;
      });
    }
  }

  Future<void> _openEmailPage() async {
    if (_loading) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileVerifiedEmailPage(
          role: 'cashier',
          userId: widget.userId,
          userName: widget.userName,
          service: _service,
          initialStatus: _status,
        ),
      ),
    );
    if (!mounted) return;

    if (changed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verified email updated successfully')),
      );
    }
    await _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final emailText = _loading
        ? 'Checking email...'
        : _status?.verified == true
            ? (_status?.emailMasked ?? 'Verified email')
            : 'Add a verified email';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1B6AB),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  emailText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF794243),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 76,
              height: 30,
              child: ElevatedButton(
                onPressed: _loading ? null : _openEmailPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _red,
                  disabledBackgroundColor: const Color(0xFFF2EAEA),
                  disabledForegroundColor: _red,
                  elevation: 1,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: _red,
                        ),
                      )
                    : const Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
