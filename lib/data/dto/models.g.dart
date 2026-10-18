// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SessionDto _$SessionDtoFromJson(Map<String, dynamic> json) => $checkedCreate(
  'SessionDto',
  json,
  ($checkedConvert) {
    final val = SessionDto(
      accessToken: $checkedConvert('access_token', (v) => v as String),
      expiresAt: $checkedConvert(
        'expires_at',
        (v) => DateTime.parse(v as String),
      ),
      userId: $checkedConvert('user_id', (v) => v as String),
      extension: $checkedConvert('extension', (v) => v as String),
      deviceId: $checkedConvert('device_id', (v) => v as String),
      accountStatus: $checkedConvert('account_status', (v) => v as String),
      deviceLimit: $checkedConvert('device_limit', (v) => (v as num?)?.toInt()),
    );
    return val;
  },
  fieldKeyMap: const {
    'accessToken': 'access_token',
    'expiresAt': 'expires_at',
    'userId': 'user_id',
    'deviceId': 'device_id',
    'accountStatus': 'account_status',
    'deviceLimit': 'device_limit',
  },
);

Map<String, dynamic> _$SessionDtoToJson(SessionDto instance) =>
    <String, dynamic>{
      'access_token': instance.accessToken,
      'user_id': instance.userId,
      'extension': instance.extension,
      'device_id': instance.deviceId,
      'account_status': instance.accountStatus,
      'expires_at': instance.expiresAt.toIso8601String(),
      'device_limit': instance.deviceLimit,
    };

DeviceDto _$DeviceDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DeviceDto', json, ($checkedConvert) {
      final val = DeviceDto(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        status: $checkedConvert('status', (v) => v as String),
        lastSeenAt: $checkedConvert(
          'last_seen_at',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    }, fieldKeyMap: const {'lastSeenAt': 'last_seen_at'});

Map<String, dynamic> _$DeviceDtoToJson(DeviceDto instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'status': instance.status,
  'last_seen_at': instance.lastSeenAt.toIso8601String(),
};

CallDto _$CallDtoFromJson(Map<String, dynamic> json) => $checkedCreate(
  'CallDto',
  json,
  ($checkedConvert) {
    final val = CallDto(
      id: $checkedConvert('id', (v) => v as String),
      sipCallId: $checkedConvert('sip_call_id', (v) => v as String),
      state: $checkedConvert('state', (v) => v as String),
      remote: $checkedConvert('remote', (v) => v as String),
      updatedAt: $checkedConvert(
        'updated_at',
        (v) => DateTime.parse(v as String),
      ),
      revision: $checkedConvert('revision', (v) => (v as num).toInt()),
      answeredDeviceId: $checkedConvert(
        'answered_device_id',
        (v) => v as String?,
      ),
      queuePosition: $checkedConvert(
        'queue_position',
        (v) => (v as num?)?.toInt(),
      ),
      waitingSince: $checkedConvert(
        'waiting_since',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'sipCallId': 'sip_call_id',
    'updatedAt': 'updated_at',
    'answeredDeviceId': 'answered_device_id',
    'queuePosition': 'queue_position',
    'waitingSince': 'waiting_since',
  },
);

Map<String, dynamic> _$CallDtoToJson(CallDto instance) => <String, dynamic>{
  'id': instance.id,
  'sip_call_id': instance.sipCallId,
  'state': instance.state,
  'remote': instance.remote,
  'updated_at': instance.updatedAt.toIso8601String(),
  'revision': instance.revision,
  'answered_device_id': instance.answeredDeviceId,
  'queue_position': instance.queuePosition,
  'waiting_since': instance.waitingSince?.toIso8601String(),
};

QueueTaskDto _$QueueTaskDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'QueueTaskDto',
      json,
      ($checkedConvert) {
        final val = QueueTaskDto(
          id: $checkedConvert('id', (v) => v as String),
          destination: $checkedConvert('destination', (v) => v as String),
          state: $checkedConvert('state', (v) => v as String),
          revision: $checkedConvert('revision', (v) => (v as num).toInt()),
          position: $checkedConvert('position', (v) => (v as num?)?.toInt()),
          estimatedWaitSeconds: $checkedConvert(
            'estimated_wait_seconds',
            (v) => (v as num?)?.toInt(),
          ),
          failureReason: $checkedConvert('failure_reason', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'estimatedWaitSeconds': 'estimated_wait_seconds',
        'failureReason': 'failure_reason',
      },
    );

Map<String, dynamic> _$QueueTaskDtoToJson(QueueTaskDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'destination': instance.destination,
      'state': instance.state,
      'revision': instance.revision,
      'position': instance.position,
      'estimated_wait_seconds': instance.estimatedWaitSeconds,
      'failure_reason': instance.failureReason,
    };

SnapshotDto _$SnapshotDtoFromJson(Map<String, dynamic> json) => $checkedCreate(
  'SnapshotDto',
  json,
  ($checkedConvert) {
    final val = SnapshotDto(
      accountStatus: $checkedConvert('account_status', (v) => v as String),
      deviceStatus: $checkedConvert('device_status', (v) => v as String),
      lineStatus: $checkedConvert('line_status', (v) => v as String),
      canCall: $checkedConvert('can_call', (v) => v as bool),
      devices: $checkedConvert(
        'devices',
        (v) => (v as List<dynamic>)
            .map((e) => DeviceDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      calls: $checkedConvert(
        'calls',
        (v) => (v as List<dynamic>)
            .map((e) => CallDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      outboundTasks: $checkedConvert(
        'outbound_tasks',
        (v) => (v as List<dynamic>)
            .map((e) => QueueTaskDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      history: $checkedConvert(
        'history',
        (v) => (v as List<dynamic>)
            .map((e) => CallDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'accountStatus': 'account_status',
    'deviceStatus': 'device_status',
    'lineStatus': 'line_status',
    'canCall': 'can_call',
    'outboundTasks': 'outbound_tasks',
  },
);

Map<String, dynamic> _$SnapshotDtoToJson(SnapshotDto instance) =>
    <String, dynamic>{
      'account_status': instance.accountStatus,
      'device_status': instance.deviceStatus,
      'line_status': instance.lineStatus,
      'can_call': instance.canCall,
      'devices': instance.devices,
      'calls': instance.calls,
      'history': instance.history,
      'outbound_tasks': instance.outboundTasks,
    };

SipCredentialsDto _$SipCredentialsDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'SipCredentialsDto',
      json,
      ($checkedConvert) {
        final val = SipCredentialsDto(
          webSocketUrl: $checkedConvert('web_socket_url', (v) => v as String),
          uri: $checkedConvert('uri', (v) => v as String),
          authorizationUser: $checkedConvert(
            'authorization_user',
            (v) => v as String,
          ),
          password: $checkedConvert('password', (v) => v as String),
          expiresAt: $checkedConvert(
            'expires_at',
            (v) => DateTime.parse(v as String),
          ),
          iceServers: $checkedConvert(
            'ice_servers',
            (v) => (v as List<dynamic>)
                .map((e) => Map<String, String>.from(e as Map))
                .toList(),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'webSocketUrl': 'web_socket_url',
        'authorizationUser': 'authorization_user',
        'expiresAt': 'expires_at',
        'iceServers': 'ice_servers',
      },
    );

Map<String, dynamic> _$SipCredentialsDtoToJson(SipCredentialsDto instance) =>
    <String, dynamic>{
      'web_socket_url': instance.webSocketUrl,
      'uri': instance.uri,
      'authorization_user': instance.authorizationUser,
      'password': instance.password,
      'expires_at': instance.expiresAt.toIso8601String(),
      'ice_servers': instance.iceServers,
    };
