import 'dart:async';
import 'package:flutter/material.dart';
import 'azsign_types.dart';
import 'azsign_auth_adapter.dart';
import 'azsign_address_book_adapter.dart';

/// Read-only Address Book catalog widget for AZSign Desktop Operators.
/// Renders authorized devices with decoupled status (player heartbeat vs remote access).
class AzsignAddressBookWidget extends StatefulWidget {
  final AzsignSession session;
  final AzsignAddressBookService addressBookService;
  final AzsignAuthService authService;
  final void Function(AddressBookDevice device)? onConnect;
  final VoidCallback? onLogout;

  const AzsignAddressBookWidget({
    Key? key,
    required this.session,
    required this.addressBookService,
    required this.authService,
    this.onConnect,
    this.onLogout,
  }) : super(key: key);

  @override
  State<AzsignAddressBookWidget> createState() => _AzsignAddressBookWidgetState();
}

class _AzsignAddressBookWidgetState extends State<AzsignAddressBookWidget> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _loading = false;
  String? _errorMessage;
  List<AddressBookDevice> _devices = [];
  CatalogPagination _pagination = const CatalogPagination(
    currentPage: 1,
    lastPage: 1,
    perPage: 10,
    total: 0,
  );

  PlayerHeartbeatStatus? _playerStatusFilter;
  RemoteTransportStatus? _remoteStatusFilter;

  @override
  void initState() {
    super.initState();
    _loadCatalog(1);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadCatalog(1);
    });
  }

  Future<void> _loadCatalog(int page) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final filter = AzsignAddressBookFilter(
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        playerStatus: _playerStatusFilter,
        remoteAccessStatus: _remoteStatusFilter,
      );

      final response = await widget.addressBookService.loadPage(
        token: widget.session.token,
        page: page,
        perPage: 10,
        filter: filter,
      );

      setState(() {
        _devices = response.devices;
        _pagination = response.pagination;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Não foi possível carregar o catálogo de aparelhos: ${e.toString()}';
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar Sessão'),
        content: const Text('Deseja realmente sair da sua conta AZSign neste computador?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.authService.logout();
      widget.onLogout?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderBar(),
          const SizedBox(height: 12),
          _buildFilterBar(),
          const SizedBox(height: 12),
          if (_errorMessage != null) _buildErrorBanner(),
          Expanded(
            child: _loading && _devices.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildDeviceList(),
          ),
          const SizedBox(height: 8),
          _buildPaginationBar(),
        ],
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle, size: 28, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.session.user.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '${widget.session.user.email} • ${widget.session.tenant.name}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Sair'),
            onPressed: _handleLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Pesquisar por nome do aparelho...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _loadCatalog(1);
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<PlayerHeartbeatStatus?>(
          value: _playerStatusFilter,
          hint: const Text('Status Player'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos os Players')),
            DropdownMenuItem(value: PlayerHeartbeatStatus.online, child: Text('Player Online')),
            DropdownMenuItem(value: PlayerHeartbeatStatus.offline, child: Text('Player Offline')),
          ],
          onChanged: (val) {
            setState(() => _playerStatusFilter = val);
            _loadCatalog(1);
          },
        ),
        const SizedBox(width: 12),
        DropdownButton<RemoteTransportStatus?>(
          value: _remoteStatusFilter,
          hint: const Text('Acesso Remoto'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos Acessos')),
            DropdownMenuItem(value: RemoteTransportStatus.available, child: Text('Disponível')),
            DropdownMenuItem(value: RemoteTransportStatus.offline, child: Text('Indisponível')),
            DropdownMenuItem(value: RemoteTransportStatus.revoked, child: Text('Revogado')),
            DropdownMenuItem(value: RemoteTransportStatus.unprovisioned, child: Text('Não Provisionado')),
          ],
          onChanged: (val) {
            setState(() => _remoteStatusFilter = val);
            _loadCatalog(1);
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar Catálogo',
          onPressed: () => _loadCatalog(_pagination.currentPage),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Nenhum aparelho encontrado.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = _devices[index];
        return _buildDeviceTile(device);
      },
    );
  }

  Widget _buildDeviceTile(AddressBookDevice device) {
    final canConnect = device.remoteAccessStatus == RemoteTransportStatus.available;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.tv, size: 28, color: Colors.grey.shade700),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    for (final tag in device.tags)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tag, style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${device.id} • ${device.tenantName}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildHeartbeatBadge(device.playerStatus),
          const SizedBox(width: 8),
          _buildRemoteBadge(device.remoteAccessStatus),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.login, size: 16),
            label: const Text('Conectar'),
            onPressed: canConnect ? () => widget.onConnect?.call(device) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHeartbeatBadge(PlayerHeartbeatStatus status) {
    final isOnline = status == PlayerHeartbeatStatus.online;
    return Tooltip(
      message: isOnline ? 'Player reportando heartbeat ao CMS' : 'Sem heartbeat recente do player',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOnline ? Colors.green.shade50 : Colors.grey.shade100,
          border: Border.all(color: isOnline ? Colors.green.shade300 : Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 11,
                color: isOnline ? Colors.green.shade800 : Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteBadge(RemoteTransportStatus status) {
    Color bg;
    Color border;
    Color text;
    String label;
    String tip;

    switch (status) {
      case RemoteTransportStatus.available:
        bg = Colors.blue.shade50;
        border = Colors.blue.shade300;
        text = Colors.blue.shade800;
        label = 'Remoto mTLS';
        tip = 'Acesso remoto pronto e verificado no gateway';
        break;
      case RemoteTransportStatus.offline:
        bg = Colors.orange.shade50;
        border = Colors.orange.shade300;
        text = Colors.orange.shade800;
        label = 'Remoto Offline';
        tip = 'Aparelho provisionado mas desconectado do gateway';
        break;
      case RemoteTransportStatus.revoked:
        bg = Colors.red.shade50;
        border = Colors.red.shade300;
        text = Colors.red.shade800;
        label = 'Revogado';
        tip = 'Identidade de acesso remoto revogada no painel';
        break;
      case RemoteTransportStatus.unprovisioned:
      default:
        bg = Colors.grey.shade100;
        border = Colors.grey.shade300;
        text = Colors.grey.shade700;
        label = 'Não Provisionado';
        tip = 'Dispositivo ainda não configurado para acesso remoto';
        break;
    }

    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: text, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    final from = _pagination.from ?? 0;
    final to = _pagination.to ?? 0;
    final total = _pagination.total;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          total > 0 ? 'Exibindo $from a $to de $total aparelhos' : 'Nenhum item',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _pagination.currentPage > 1
                  ? () => _loadCatalog(_pagination.currentPage - 1)
                  : null,
            ),
            Text(
              'Página ${_pagination.currentPage} de ${_pagination.lastPage}',
              style: const TextStyle(fontSize: 12),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _pagination.currentPage < _pagination.lastPage
                  ? () => _loadCatalog(_pagination.currentPage + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
