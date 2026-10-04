class PaymentTransaction {
  final String id;
  final String recipientName;
  final String recipientNumber;
  final String paymentTitle;
  final double amount;
  final DateTime timestamp;
  final bool isCompleted;

  PaymentTransaction({
    required this.id,
    required this.recipientName,
    required this.recipientNumber,
    required this.paymentTitle,
    required this.amount,
    required this.timestamp,
    required this.isCompleted,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id'].toString(),
      recipientName: json['recipientName'],
      recipientNumber: json['recipientNumber'].toString(),
      amount: (json['amount'] as num).toDouble(),
      paymentTitle: json['paymentTitle'],
      timestamp: DateTime.parse(json['timestamp']),
      isCompleted: json['isCompleted'],
    );
  }
}

class PaymentState {
  final String? scannedQRData;
  final String? recipientName;
  final String? recipientNumber;
  final double? amount;
  final String? pin;
  final PaymentTransaction? lastTransaction;

  PaymentState({
    this.scannedQRData,
    this.recipientName,
    this.recipientNumber,
    this.amount,
    this.pin,
    this.lastTransaction,
  });

  PaymentState copyWith({
    String? scannedQRData,
    String? recipientName,
    String? recipientNumber,
    double? amount,
    String? pin,
    PaymentTransaction? lastTransaction,
  }) {
    return PaymentState(
      scannedQRData: scannedQRData ?? this.scannedQRData,
      recipientName: recipientName ?? this.recipientName,
      recipientNumber: recipientNumber ?? this.recipientNumber,
      amount: amount ?? this.amount,
      pin: pin ?? this.pin,
      lastTransaction: lastTransaction ?? this.lastTransaction,
    );
  }
}
