import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rawr/pos_amount_input_screen.dart';

import 'api_config.dart';

class QRScannerScreen extends StatefulWidget {
  final String cashierId;
  final bool showAppBar;
  final ValueChanged<int>? onNavigate;

  const QRScannerScreen({
    super.key,
    required this.cashierId,
    this.showAppBar = true,
    this.onNavigate,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  late MobileScannerController controller;
  bool _isScanned = false;
  bool _isCameraPaused = false;
  double _zoomFactor = 0.0;
  String? _lastScanValue;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _scanDebounce = Duration(milliseconds: 1200);
  static const Duration _resumeDelay = Duration(milliseconds: 500);

  Future<({String? studentNumber, String? errorMessage})>
  _resolveStudentNumberViaStudentInfo(String studentNum) async {
    try {
      final uri = Uri.parse(
        ApiConfig.url(
          'get_student_info.php?student_id=${Uri.encodeQueryComponent(studentNum)}',
        ),
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return (
          studentNumber: null,
          errorMessage: 'Server error: ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (
          studentNumber: null,
          errorMessage: 'Invalid server response while validating student.',
        );
      }

      if (decoded['status']?.toString() != 'success') {
        return (studentNumber: null, errorMessage: null);
      }

      final id = decoded['id']?.toString();
      if (id == null || id.isEmpty) {
        return (
          studentNumber: null,
          errorMessage: 'Student record is missing student number.',
        );
      }

      return (studentNumber: id, errorMessage: null);
    } catch (e) {
      return (
        studentNumber: null,
        errorMessage: 'Could not validate QR code: $e',
      );
    }
  }

  Future<({String? studentNumber, String? errorMessage})>
  _resolveStudentNumberFromQr(String qrCode) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.url('validate_student_qr.php')),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'student_num': qrCode},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        return _resolveStudentNumberViaStudentInfo(qrCode);
      }

      if (response.statusCode != 200) {
        return (
          studentNumber: null,
          errorMessage: 'Server error: ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (
          studentNumber: null,
          errorMessage: 'Invalid server response while validating QR.',
        );
      }

      final status = decoded['status']?.toString();
      if (status != 'success') {
        final message = decoded['message']?.toString();
        return (
          studentNumber: null,
          errorMessage:
              (message == null || message.isEmpty)
                  ? 'QR validation failed.'
                  : message,
        );
      }

      if (decoded['exists'] != true) {
        return (studentNumber: null, errorMessage: null);
      }

      final student = decoded['student'];
      if (student is! Map) {
        return (
          studentNumber: null,
          errorMessage: 'Invalid student payload from server.',
        );
      }

      final studentNum = student['student_num']?.toString();
      if (studentNum == null || studentNum.isEmpty) {
        return (
          studentNumber: null,
          errorMessage: 'Student record is missing student number.',
        );
      }

      return (studentNumber: studentNum, errorMessage: null);
    } catch (e) {
      return (
        studentNumber: null,
        errorMessage: 'Could not validate QR code: $e',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pauseCamera() async {
    if (_isCameraPaused) return;
    try {
      await controller.stop();
      _isCameraPaused = true;
    } catch (_) {}
  }

  Future<void> _resumeCamera({Duration delay = Duration.zero}) async {
    if (!_isCameraPaused) return;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (!mounted) return;
    try {
      await controller.start();
      _isCameraPaused = false;
    } catch (_) {}
  }

  Future<void> _turnTorchOffIfOn() async {
    try {
      if (controller.torchState.value == TorchState.on) {
        await controller.toggleTorch();
      }
    } catch (_) {}
  }

  Future<void> _handleQRScanned(String qrData) async {
    if (_isScanned) return;
    _isScanned = true;
    await _pauseCamera();

    try {
      final recipientNumber = qrData;
      if (recipientNumber.isEmpty || recipientNumber == 'No value found') {
        _showSnack('Invalid QR code. Please scan a valid student QR.');
        return;
      }

      await _turnTorchOffIfOn();
      if (!mounted) return;

      final validation = await _resolveStudentNumberFromQr(recipientNumber);
      if (!mounted) return;

      if (validation.errorMessage != null) {
        _showSnack(validation.errorMessage!);
        return;
      }

      final studentNumber = validation.studentNumber;
      if (studentNumber == null) {
        debugPrint('Unregistered student_num raw value: "$recipientNumber"');
        _showSnack('Student number is not registered.');
        return;
      }

      const String paymentTitle = 'Payment';

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PaymentScreen(
            recipientNumber: studentNumber,
            paymentTitle: paymentTitle,
            cashierId: widget.cashierId,
            canteenId: widget.cashierId,
            onNavigate: widget.onNavigate,
          ),
        ),
      );
    } finally {
      _isScanned = false;
      await _resumeCamera(delay: _resumeDelay);
    }
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Image.asset(
        'assets/icons/logo-red.png',
        height: 60,
      ),
      centerTitle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Scanning...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFFAC2324),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFAC2324),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(74.0),
                  topRight: Radius.circular(74.0),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(74.0),
                  topRight: Radius.circular(74.0),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(51),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Align the QR Code within the frame to scan',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withAlpha(128),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: MobileScanner(
                              controller: controller,
                              onDetect: (capture) {
                                final List<Barcode> barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty) {
                                  final Barcode barcode = barcodes.first;
                                  final String scannedValue =
                                      barcode.rawValue ?? 'No value found';
                                  if (scannedValue.isEmpty) {
                                    return;
                                  }
                                  final now = DateTime.now();
                                  final isDuplicateWithinDebounce =
                                      scannedValue == _lastScanValue &&
                                      now.difference(_lastScanAt) < _scanDebounce;
                                  if (isDuplicateWithinDebounce) {
                                    return;
                                  }
                                  _lastScanValue = scannedValue;
                                  _lastScanAt = now;
                                  _handleQRScanned(scannedValue);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildBottomControls(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final media = MediaQuery.of(context);
    final double bottomPad = widget.showAppBar
        ? media.padding.bottom + 8
        : media.padding.bottom + 84;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove, color: Colors.white),
                onPressed: () {
                  final newZoom = _zoomFactor - 0.1;
                  setState(() {
                    _zoomFactor = math.max(0.0, newZoom);
                    controller.setZoomScale(_zoomFactor);
                  });
                },
              ),
              Expanded(
                child: Slider(
                  value: _zoomFactor,
                  min: 0.0,
                  max: 1.0,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white38,
                  onChanged: (value) {
                    setState(() {
                      _zoomFactor = value;
                      controller.setZoomScale(value);
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () {
                  final newZoom = _zoomFactor + 0.1;
                  setState(() {
                    _zoomFactor = math.min(1.0, newZoom);
                    controller.setZoomScale(_zoomFactor);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: controller.torchState,
            builder: (context, state, child) {
              final bool isFlashOn = state == TorchState.on;
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => controller.toggleTorch(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.flash_on,
                      color:
                          isFlashOn ? Colors.amber[700] : const Color(0xFFAC2324),
                      size: 28,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}


