import 'dart:async';
import 'azsign_types.dart';

/// Filter parameters for the paginated Address Book query.
class AzsignAddressBookFilter {
  final String? search;
  final String? tenantId;
  final PlayerHeartbeatStatus? playerStatus;
  final RemoteTransportStatus? remoteAccessStatus;

  const AzsignAddressBookFilter({
    this.search,
    this.tenantId,
    this.playerStatus,
    this.remoteAccessStatus,
  });

  Map<String, String> toQueryParameters() {
    final params = <String, String>{};
    if (search != null && search!.trim().isNotEmpty) {
      params['search'] = search!.trim();
    }
    if (tenantId != null && tenantId!.isNotEmpty) {
      params['tenant_id'] = tenantId!;
    }
    if (playerStatus != null) {
      params['player_status'] = playerStatus!.name;
    }
    if (remoteAccessStatus != null) {
      params['remote_access_status'] = remoteAccessStatus!.name;
    }
    return params;
  }
}

/// Paginated Address Book catalog response.
class AzsignAddressBookResponse {
  final List<AddressBookDevice> devices;
  final CatalogPagination pagination;

  const AzsignAddressBookResponse({
    required this.devices,
    required this.pagination,
  });

  factory AzsignAddressBookResponse.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as List<dynamic>?) ?? [];
    final meta = (json['meta'] as Map<String, dynamic>?) ?? {};

    return AzsignAddressBookResponse(
      devices: data.map((item) => AddressBookDevice.fromJson(item as Map<String, dynamic>)).toList(),
      pagination: CatalogPagination.fromJson(meta),
    );
  }
}

/// Abstract transport contract for Address Book catalog.
/// Proposed to Codex for the server-side API contract.
abstract class AzsignAddressBookTransport {
  Future<AzsignAddressBookResponse> fetchCatalog({
    required String token,
    int page = 1,
    int perPage = 20,
    AzsignAddressBookFilter? filter,
  });
}

/// Address Book service managing catalog search, pagination, and status aggregation.
class AzsignAddressBookService {
  final AzsignAddressBookTransport transport;

  AzsignAddressBookService({required this.transport});

  Future<AzsignAddressBookResponse> loadPage({
    required String token,
    int page = 1,
    int perPage = 20,
    AzsignAddressBookFilter? filter,
  }) async {
    return transport.fetchCatalog(
      token: token,
      page: page,
      perPage: perPage.clamp(1, 100),
      filter: filter,
    );
  }
}

/// Test fixture and mock implementation representing real CMS behavior.
class MockAzsignAddressBookTransport implements AzsignAddressBookTransport {
  final List<AddressBookDevice> _fixtures;

  MockAzsignAddressBookTransport([List<AddressBookDevice>? customFixtures])
      : _fixtures = customFixtures ?? _defaultFixtures();

  static List<AddressBookDevice> _defaultFixtures() {
    return [
      AddressBookDevice(
        id: '01a0d0b2-702b-706c-b9bc-c2c05e3e6ee2',
        name: 'DC400',
        tenantId: '019d626f-a5ac-733e-9a9c-f159912015e8',
        tenantName: 'Empresa Piloto',
        playerStatus: PlayerHeartbeatStatus.online,
        remoteAccessStatus: RemoteTransportStatus.available,
        lastHeartbeatAt: DateTime.now().subtract(const Duration(seconds: 45)),
        tags: const ['Piloto', 'Lab', 'Recepção'],
      ),
      AddressBookDevice(
        id: '0199a000-0000-7000-8000-000000000010',
        name: 'Totem Entrada Principal',
        tenantId: '019d626f-a5ac-733e-9a9c-f159912015e8',
        tenantName: 'Empresa Piloto',
        playerStatus: PlayerHeartbeatStatus.online,
        remoteAccessStatus: RemoteTransportStatus.unprovisioned,
        lastHeartbeatAt: DateTime.now().subtract(const Duration(minutes: 2)),
        tags: const ['Entrada'],
      ),
      AddressBookDevice(
        id: '0199a000-0000-7000-8000-000000000020',
        name: 'Menu Board 1 - Restaurante',
        tenantId: '019d626f-a5ac-733e-9a9c-f159912015e8',
        tenantName: 'Empresa Piloto',
        playerStatus: PlayerHeartbeatStatus.offline,
        remoteAccessStatus: RemoteTransportStatus.offline,
        lastHeartbeatAt: DateTime.now().subtract(const Duration(hours: 5)),
        tags: const ['Alimentação'],
      ),
      AddressBookDevice(
        id: '0199a000-0000-7000-8000-000000000030',
        name: 'Vitrine Lateral',
        tenantId: '019d626f-a5ac-733e-9a9c-f159912015e8',
        tenantName: 'Empresa Piloto',
        playerStatus: PlayerHeartbeatStatus.online,
        remoteAccessStatus: RemoteTransportStatus.revoked,
        lastHeartbeatAt: DateTime.now().subtract(const Duration(minutes: 1)),
        tags: const ['Bloqueado'],
      ),
    ];
  }

  @override
  Future<AzsignAddressBookResponse> fetchCatalog({
    required String token,
    int page = 1,
    int perPage = 20,
    AzsignAddressBookFilter? filter,
  }) async {
    // Simulate brief network latency
    await Future.delayed(const Duration(milliseconds: 10));

    var filtered = List<AddressBookDevice>.from(_fixtures);

    if (filter != null) {
      if (filter.search != null && filter.search!.isNotEmpty) {
        final query = filter.search!.toLowerCase();
        filtered = filtered.where((d) => d.name.toLowerCase().contains(query)).toList();
      }
      if (filter.tenantId != null && filter.tenantId!.isNotEmpty) {
        filtered = filtered.where((d) => d.tenantId == filter.tenantId).toList();
      }
      if (filter.playerStatus != null) {
        filtered = filtered.where((d) => d.playerStatus == filter.playerStatus).toList();
      }
      if (filter.remoteAccessStatus != null) {
        filtered = filtered.where((d) => d.remoteAccessStatus == filter.remoteAccessStatus).toList();
      }
    }

    final total = filtered.length;
    final lastPage = (total / perPage).ceil().clamp(1, 999999);
    final clampedPage = page.clamp(1, lastPage);
    final start = (clampedPage - 1) * perPage;
    final end = (start + perPage).clamp(0, total);

    final pagedDevices = start < total ? filtered.sublist(start, end) : <AddressBookDevice>[];

    return AzsignAddressBookResponse(
      devices: pagedDevices,
      pagination: CatalogPagination(
        currentPage: clampedPage,
        lastPage: lastPage,
        perPage: perPage,
        total: total,
        from: total > 0 ? start + 1 : null,
        to: total > 0 ? end : null,
      ),
    );
  }
}
