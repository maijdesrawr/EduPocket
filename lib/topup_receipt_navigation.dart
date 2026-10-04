int topUpTransactionIdFromResponse(dynamic response) {
  if (response is! Map) return 0;

  final direct = response['transaction_id'];
  final nested = response['data'];
  final raw = direct ?? (nested is Map ? nested['transaction_id'] : null);
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}
