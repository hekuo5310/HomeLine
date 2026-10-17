class WakeHint {
  const WakeHint(this.callId, this.expiresAt);
  final String callId;
  final DateTime expiresAt;
  static WakeHint? parse(Map<String, dynamic> data, DateTime now) {
    if (data['type'] != 'incoming_call') return null;
    final id = data['call_id'];
    final expiry = DateTime.tryParse(data['expires_at']?.toString() ?? '');
    if (id is! String ||
        id.isEmpty ||
        id.length > 200 ||
        expiry == null ||
        !expiry.isAfter(now) ||
        expiry.difference(now) > const Duration(minutes: 2)) {
      return null;
    }
    return WakeHint(id, expiry);
  }
}
