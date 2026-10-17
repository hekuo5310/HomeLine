import 'package:uuid/uuid.dart';

/// One key survives ambiguous network failures until this intent is resolved.
class OutboundRequest {
  OutboundRequest(this.destination) : idempotencyKey = const Uuid().v4() {
    if (!RegExp(r'^\+?[0-9]{3,20}$').hasMatch(destination)) {
      throw const FormatException('请输入 3–20 位电话号码，可带 +');
    }
  }
  OutboundRequest.restore(this.destination, this.idempotencyKey);
  final String destination, idempotencyKey;
}
