import 'package:json_annotation/json_annotation.dart';
part 'models.g.dart';

@JsonSerializable(checked: true, fieldRename: FieldRename.snake)
class SessionDto {
  const SessionDto({
    required this.accessToken,
    required this.expiresAt,
    required this.userId,
    required this.extension,
    required this.deviceId,
    required this.accountStatus,
    this.deviceLimit,
  });
  final String accessToken, userId, extension, deviceId, accountStatus;
  final DateTime expiresAt;
  final int? deviceLimit;
  factory SessionDto.fromJson(Map<String, dynamic> json) =>
      _$SessionDtoFromJson(json);
  Map<String, dynamic> toJson() => _$SessionDtoToJson(this);
}

@JsonSerializable(checked: true, fieldRename: FieldRename.snake)
class DeviceDto {
  const DeviceDto({
    required this.id,
    required this.name,
    required this.status,
    required this.lastSeenAt,
  });
  final String id, name, status;
  final DateTime lastSeenAt;
  factory DeviceDto.fromJson(Map<String, dynamic> json) =>
      _$DeviceDtoFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceDtoToJson(this);
}

@JsonSerializable(checked: true, fieldRename: FieldRename.snake)
class CallDto {
  const CallDto({
    required this.id,
    required this.sipCallId,
    required this.state,
    required this.remote,
    required this.updatedAt,
    required this.revision,
    this.answeredDeviceId,
    this.queuePosition,
    this.waitingSince,
  });
  final String id, sipCallId, state, remote;
  final DateTime updatedAt;
  final int revision;
  final String? answeredDeviceId;
  final int? queuePosition;
  final DateTime? waitingSince;
  bool get terminal =>
      const ['ended', 'failed', 'cancelled', 'timeout'].contains(state);
  factory CallDto.fromJson(Map<String, dynamic> json) =>
      _$CallDtoFromJson(json);
  Map<String, dynamic> toJson() => _$CallDtoToJson(this);
}

@JsonSerializable(checked: true, fieldRename: FieldRename.snake)
class QueueTaskDto {
  const QueueTaskDto({
    required this.id,
    required this.destination,
    required this.state,
    required this.revision,
    this.position,
    this.estimatedWaitSeconds,
    this.failureReason,
  });
  final String id, destination, state;
  final int revision;
  final int? position, estimatedWaitSeconds;
  final String? failureReason;
  factory QueueTaskDto.fromJson(Map<String, dynamic> json) =>
      _$QueueTaskDtoFromJson(json);
  Map<String, dynamic> toJson() => _$QueueTaskDtoToJson(this);
}

@JsonSerializable(checked: true, fieldRename: FieldRename.snake)
class SnapshotDto {
  const SnapshotDto({
    required this.accountStatus,
    required this.deviceStatus,
    required this.lineStatus,
    required this.canCall,
    required this.devices,
    required this.calls,
    required this.outboundTasks,
    required this.history,
  });
  final String accountStatus, deviceStatus, lineStatus;
  final bool canCall;
  final List<DeviceDto> devices;
  final List<CallDto> calls, history;
  final List<QueueTaskDto> outboundTasks;
  factory SnapshotDto.fromJson(Map<String, dynamic> json) =>
      _$SnapshotDtoFromJson(json);
  Map<String, dynamic> toJson() => _$SnapshotDtoToJson(this);
}

@JsonSerializable(checked: true, fieldRename: FieldRename.snake)
class SipCredentialsDto {
  const SipCredentialsDto({
    required this.webSocketUrl,
    required this.uri,
    required this.authorizationUser,
    required this.password,
    required this.expiresAt,
    required this.iceServers,
  });
  final String webSocketUrl, uri, authorizationUser, password;
  final DateTime expiresAt;
  final List<Map<String, String>> iceServers;
  factory SipCredentialsDto.fromJson(Map<String, dynamic> json) =>
      _$SipCredentialsDtoFromJson(json);
  Map<String, dynamic> toJson() => _$SipCredentialsDtoToJson(this);
}
