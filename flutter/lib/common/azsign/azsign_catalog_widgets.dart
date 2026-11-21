import 'package:flutter/material.dart';
import 'azsign_types.dart';

class AzsignCatalogFilters extends StatelessWidget {
  final TextEditingController search;
  final PlayerHeartbeatStatus? playerStatus;
  final bool? provisioned;
  final ValueChanged<String> onSearch;
  final VoidCallback onSubmit;
  final ValueChanged<PlayerHeartbeatStatus?> onPlayerStatus;
  final ValueChanged<bool?> onProvisioned;
  const AzsignCatalogFilters(
      {super.key,
      required this.search,
      required this.playerStatus,
      required this.provisioned,
      required this.onSearch,
      required this.onSubmit,
      required this.onPlayerStatus,
      required this.onProvisioned});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final filterWidth =
            constraints.maxWidth < 440 ? constraints.maxWidth : 200.0;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
              width: wide ? constraints.maxWidth - 424 : constraints.maxWidth,
              child: TextField(
                  controller: search,
                  onChanged: onSearch,
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                      labelText: 'Buscar player pelo nome',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                search.clear();
                                onSearch('');
                              })))),
          SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                  key: const ValueKey('provisioning-filter'),
                  isExpanded: true,
                  value: provisioned == null
                      ? 'all'
                      : provisioned!
                          ? 'yes'
                          : 'no',
                  decoration: const InputDecoration(
                      labelText: 'Provisionamento',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(
                        value: 'yes', child: Text('Provisionados')),
                    DropdownMenuItem(
                        value: 'no', child: Text('Não provisionados'))
                  ],
                  onChanged: (value) =>
                      onProvisioned(value == 'all' ? null : value == 'yes'))),
          SizedBox(
              width: filterWidth,
              child: DropdownButtonFormField<String>(
                  key: const ValueKey('heartbeat-filter'),
                  isExpanded: true,
                  value: playerStatus?.name ?? 'all',
                  decoration: const InputDecoration(
                      labelText: 'Conexão do player',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(value: 'online', child: Text('Online')),
                    DropdownMenuItem(value: 'offline', child: Text('Offline'))
                  ],
                  onChanged: (value) => onPlayerStatus(value == 'all'
                      ? null
                      : value == 'online'
                          ? PlayerHeartbeatStatus.online
                          : PlayerHeartbeatStatus.offline))),
        ]);
      });
}

class AzsignPlayerCard extends StatelessWidget {
  final AddressBookDevice device;
  final VoidCallback? onConnect;
  const AzsignPlayerCard({super.key, required this.device, this.onConnect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provisioned = device.isProvisioned;
    final online = device.playerStatus == PlayerHeartbeatStatus.online;
    final blocked = device.remoteAccessStatus == RemoteTransportStatus.blocked;
    final revoked = device.remoteAccessStatus == RemoteTransportStatus.revoked;
    final foreground = scheme.onSurface.withOpacity(provisioned ? 0.9 : 0.65);
    final iconColor =
        provisioned ? scheme.primary : scheme.onSurface.withOpacity(0.45);
    final status = Wrap(spacing: 8, runSpacing: 8, children: [
      _StatusBadge(
          label: provisioned ? 'Provisionado' : 'Não provisionado',
          icon: provisioned
              ? Icons.verified_user_outlined
              : Icons.build_circle_outlined,
          color: provisioned
              ? scheme.primary
              : scheme.onSurface.withOpacity(0.65)),
      _StatusBadge(
          label: online ? 'Online' : 'Offline',
          icon: online ? Icons.wifi : Icons.wifi_off,
          color: online
              ? (scheme.brightness == Brightness.dark
                  ? Colors.green.shade300
                  : Colors.green.shade800)
              : scheme.onSurface.withOpacity(0.65)),
      if (blocked || revoked)
        _StatusBadge(
            label: blocked ? 'Acesso bloqueado' : 'Acesso revogado',
            icon: Icons.lock_outline,
            color: scheme.error),
    ]);
    final connect = Tooltip(
        message: !provisioned
            ? 'Configure o acesso remoto pelo AZSign Setup.'
            : blocked || revoked
                ? 'Confira a autorização do acesso remoto no painel.'
                : 'Acessar este player',
        child: OutlinedButton.icon(
            onPressed: provisioned && !blocked && !revoked ? onConnect : null,
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text('Conectar')));
    return Container(
        key: ValueKey('player-${device.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: provisioned
                ? scheme.surface
                : scheme.onSurface.withOpacity(0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.onSurface.withOpacity(0.12))),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.tv, color: iconColor, size: 24)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(device.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      device.remoteId?.isNotEmpty == true
                          ? 'ID do Remote: ${device.remoteId}'
                          : 'Acesso remoto ainda não configurado',
                      style: TextStyle(color: foreground, fontSize: 12)),
                  const SizedBox(height: 12),
                  status,
                  if (compact)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: connect),
                ])),
            if (!compact)
              Padding(padding: const EdgeInsets.only(left: 16), child: connect),
          ]);
        }));
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusBadge(
      {required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)))
          ])));
}
