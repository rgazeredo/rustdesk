/// Shared domain models and types for AZSign Desktop Integration.
/// All identifiers are UUIDs. Decouples player CMS heartbeat from remote mTLS transport.

enum PlayerHeartbeatStatus {
  online,
  offline,
}

enum RemoteTransportStatus {
  /// mTLS identity active and verified on gateway
  available,
  /// mTLS provisioned but gateway reports offline / unreachable
  offline,
  /// Identity revoked on CMS / gateway
  revoked,
  /// No access identity provisioned yet
  unprovisioned,
}

class AzsignUser {
  final String id;
  final String name;
  final String email;

  const AzsignUser({
    required this.id,
    required this.name,
    required this.email,
  });

  factory AzsignUser.fromJson(Map<String, dynamic> json) {
    return AzsignUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
  };
}

class AzsignTenant {
  final String id;
  final String name;

  const AzsignTenant({
    required this.id,
    required this.name,
  });

  factory AzsignTenant.fromJson(Map<String, dynamic> json) {
    return AzsignTenant(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}

class AzsignSession {
  final String token;
  final DateTime expiresAt;
  final AzsignUser user;
  final AzsignTenant tenant;

  const AzsignSession({
    required this.token,
    required this.expiresAt,
    required this.user,
    required this.tenant,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory AzsignSession.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'] as int? ?? 86400;
    return AzsignSession(
      token: json['access_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      user: AzsignUser.fromJson(json['user'] as Map<String, dynamic>),
      tenant: AzsignTenant.fromJson(json['tenant'] as Map<String, dynamic>),
    );
  }
}

class AddressBookDevice {
  final String id;
  final String name;
  final String tenantId;
  final String tenantName;
  final PlayerHeartbeatStatus playerStatus;
  final RemoteTransportStatus remoteAccessStatus;
  final DateTime? lastHeartbeatAt;
  final List<String> tags;

  const AddressBookDevice({
    required this.id,
    required this.name,
    required this.tenantId,
    required this.tenantName,
    required this.playerStatus,
    required this.remoteAccessStatus,
    this.lastHeartbeatAt,
    this.tags = const [],
  });

  factory AddressBookDevice.fromJson(Map<String, dynamic> json) {
    final playerStatusStr = json['player_status'] as String? ?? 'offline';
    final remoteStatusStr = json['remote_access_status'] as String? ?? 'unprovisioned';

    return AddressBookDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      tenantId: json['tenant_id'] as String,
      tenantName: json['tenant_name'] as String? ?? '',
      playerStatus: playerStatusStr == 'online'
          ? PlayerHeartbeatStatus.online
          : PlayerHeartbeatStatus.offline,
      remoteAccessStatus: _parseRemoteStatus(remoteStatusStr),
      lastHeartbeatAt: json['last_heartbeat_at'] != null
          ? DateTime.tryParse(json['last_heartbeat_at'] as String)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  static RemoteTransportStatus _parseRemoteStatus(String status) {
    switch (status) {
      case 'available':
        return RemoteTransportStatus.available;
      case 'offline':
        return RemoteTransportStatus.offline;
      case 'revoked':
        return RemoteTransportStatus.revoked;
      case 'unprovisioned':
      default:
        return RemoteTransportStatus.unprovisioned;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tenant_id': tenantId,
    'tenant_name': tenantName,
    'player_status': playerStatus == PlayerHeartbeatStatus.online ? 'online' : 'offline',
    'remote_access_status': remoteAccessStatus.name,
    'last_heartbeat_at': lastHeartbeatAt?.toIso8601String(),
    'tags': tags,
  };
}

class CatalogPagination {
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final int? from;
  final int? to;

  const CatalogPagination({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    this.from,
    this.to,
  });

  factory CatalogPagination.fromJson(Map<String, dynamic> json) {
    return CatalogPagination(
      currentPage: json['current_page'] as int? ?? 1,
      lastPage: json['last_page'] as int? ?? 1,
      perPage: json['per_page'] as int? ?? 20,
      total: json['total'] as int? ?? 0,
      from: json['from'] as int?,
      to: json['to'] as int?,
    );
  }
}
