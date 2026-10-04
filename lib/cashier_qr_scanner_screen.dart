import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'select_billpayment.dart';
import 'api_config.dart';

class QRValidationResult {
  final String? studentNumber;
  final String? errorMessage;

  QRValidationResult({this.studentNumber, this.errorMessage});
}

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

  Future<QRValidationResult> _resolveStudentNumberFromQr(String qrCode) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('validate_student_qr.php')),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'student_num': qrCode},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return QRValidationResult(errorMessage: 'Server error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return QRValidationResult(
          errorMessage: 'Could not validate QR. Please try again.',
        );
      }

      if (decoded['status'] != 'success') {
        return QRValidationResult(
            errorMessage: decoded['message'] ?? 'QR validation failed.');
      }

      if (decoded['exists'] != true) {
        return QRValidationResult(
          errorMessage: 'Student number is not registered.',
        );
      }

      final student = decoded['student'];
      if (student is! Map<String, dynamic>) {
        return QRValidationResult(
          errorMessage: 'Student number is not registered.',
        );
      }

      final studentNumber = student['student_num']?.toString().trim() ?? '';
      if (studentNumber.isEmpty) {
        return QRValidationResult(
          errorMessage: 'Student number is not registered.',
        );
      }

      return QRValidationResult(studentNumber: studentNumber);
    } catch (e) {
      return QRValidationResult(errorMessage: 'Could not validate QR: $e');
    }
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
    if (delay > Duration.zero) await Future.delayed(delay);
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
      final validation = await _resolveStudentNumberFromQr(qrData);
      if (!mounted) return;

      if (validation.errorMessage != null) {
        _showSnack(validation.errorMessage!);
        return;
      }

      final studentNumber = validation.studentNumber;
      if (studentNumber == null) {
        _showSnack('Student number is not registered.');
        return;
      }

      await _turnTorchOffIfOn();
      if (!mounted) return;

      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BillPaymentScreen(
          studentNumber: studentNumber,
          cashierId: widget.cashierId,
          onNavigate: widget.onNavigate,
        ),
      ));
    } finally {
      _isScanned = false;
      await _resumeCamera(delay: _resumeDelay);
    }
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Image.asset('assets/icons/logo-red.png', height: 60),
      centerTitle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double bottomPad =
        widget.showAppBar ? media.padding.bottom + 8 : media.padding.bottom + 84;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Align QR Code within frame',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFAC2324)),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white.withAlpha(128), width: 2),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: MobileScanner(
                              controller: controller,
                              onDetect: (capture) {
                                final barcodes = capture.barcodes;
                                if (barcodes.isEmpty) return;

                                final scannedValue = barcodes.first.rawValue ?? '';
                                if (scannedValue.isEmpty) return;

                                final now = DateTime.now();
                                if (scannedValue == _lastScanValue &&
                                    now.difference(_lastScanAt) < _scanDebounce) {
                                  return;
                                }

                                _lastScanValue = scannedValue;
                                _lastScanAt = now;

                                _handleQRScanned(scannedValue);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _zoomFactor = math.max(0.0, _zoomFactor - 0.1);
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
                                  setState(() {
                                    _zoomFactor = math.min(1.0, _zoomFactor + 0.1);
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
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.flash_on,
                                      color: isFlashOn
                                          ? Colors.amber[700]
                                          : const Color(0xFFAC2324),
                                      size: 28,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
