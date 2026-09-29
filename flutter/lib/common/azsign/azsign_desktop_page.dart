import 'dart:async';
import 'package:flutter/material.dart';
import 'azsign_address_book_adapter.dart';
import 'azsign_auth_adapter.dart';
import 'azsign_http.dart';
import 'azsign_http_transports.dart';
import 'azsign_native_storage.dart';
import 'azsign_native_enrollment.dart';
import 'azsign_types.dart';
import 'azsign_deep_link.dart';

/// Pilot entry point. Public configuration is applied only after native enrollment.
class AzsignDesktopPage extends StatefulWidget {
  final String cmsOrigin;
  final AzsignHttp Function(Uri)? httpFactory;
  final Future<void> Function(Map<String, dynamic> profile, String remoteId)?
      onConnect;
  const AzsignDesktopPage(
      {super.key, required this.cmsOrigin, this.onConnect, this.httpFactory});
  @override
  State<AzsignDesktopPage> createState() => _AzsignDesktopPageState();
}

class _AzsignDesktopPageState extends State<AzsignDesktopPage> {
  late final AzsignHttp _http;
  late final AzsignAuthService _auth;
  late final AzsignAddressBookService _catalog;
  late final AzsignNativeEnrollment _enrollment;
  AzsignSession? _session;
  AzsignAddressBookResponse? _page;
  AzsignAuthorizationRequest? _request;
  String? _error;
  bool _busy = true;
  int _generation = 0;
  int _catalogGeneration = 0;
  final _search = TextEditingController();
  Timer? _searchTimer;

  void _searchChanged(String value) {
    _searchTimer?.cancel();
    _catalogGeneration++;
    setState(() {
      _page = null;
      _error = null;
      _busy = true;
    });
    _searchTimer = Timer(const Duration(milliseconds: 300), () => _load(1));
  }

  @override
  void initState() {
    super.initState();
    _http = (widget.httpFactory ?? AzsignHttp.new)(Uri.parse(widget.cmsOrigin));
    _enrollment = AzsignNativeEnrollment(_http);
    _auth = AzsignAuthService(
        transport: AzsignHttpAuthTransport(_http),
        secureStorage: AzsignNativeStorage());
    _catalog = AzsignAddressBookService(
        transport: AzsignHttpAddressBookTransport(_http));
    azsignRequestedRemoteId.addListener(_schedulePendingLink);
    _restore();
  }

  @override
  void dispose() {
    azsignRequestedRemoteId.removeListener(_schedulePendingLink);
    _searchTimer?.cancel();
    _search.dispose();
    _generation++;
    _auth.cancelLogin();
    _http.close();
    super.dispose();
  }

  void _schedulePendingLink() {
    // Wait until restore/login/catalog continuations have settled their busy state.
    Timer.run(() {
      if (!mounted || _busy || _session == null || widget.onConnect == null) return;
      final remoteId = azsignRequestedRemoteId.value;
      if (remoteId == null) return;
      // Consume before enrollment: denial must not trigger an automatic retry loop.
      azsignRequestedRemoteId.value = null;
      unawaited(_connectRemoteId(remoteId));
    });
  }

  Future<void> _restore() async {
    try {
      final session = await _auth.checkSession();
      if (!mounted) return;
      setState(() => _session = session);
      if (session != null) await _load(1);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Não foi possível validar a sessão. Confira a conexão e o armazenamento seguro do sistema.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _schedulePendingLink();
    }
  }

  Future<void> _login() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
    });
    try {
      final request = await _auth.startLogin();
      if (!mounted || generation != _generation) return;
      setState(() => _request = request);
      var interval = request.interval.clamp(3, 30);
      final deadline = DateTime.now().add(Duration(seconds: request.expiresIn));
      while (mounted &&
          generation == _generation &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(Duration(seconds: interval));
        if (!mounted || generation != _generation) return;
        final result = await _auth.pollLogin();
        if (!mounted || generation != _generation) return;
        if (result.status == TokenPollStatus.slowDown) {
          interval = (interval + 5).clamp(3, 30);
          continue;
        }
        if (result.status == TokenPollStatus.pending) continue;
        if (result.status != TokenPollStatus.approved ||
            result.session == null) {
          throw StateError('Autorização recusada ou expirada.');
        }
        setState(() {
          _session = result.session;
          _request = null;
        });
        _schedulePendingLink();
        await _load(1);
        return;
      }
      throw StateError('Autorização expirada.');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Login não concluído. Verifique o navegador, a conexão e o armazenamento seguro do sistema.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _request = null;
        });
      }
    }
  }

  Future<void> _load(int number) async {
    final session = _session;
    if (session == null) return;
    final generation = _generation;
    final catalogGeneration = ++_catalogGeneration;
    setState(() {
      _busy = true;
      _page = null;
      _error = null;
    });
    try {
      final page = await _catalog.loadPage(
          token: session.token,
          page: number,
          filter: AzsignAddressBookFilter(search: _search.text.trim()));
      if (mounted &&
          generation == _generation &&
          catalogGeneration == _catalogGeneration) setState(() => _page = page);
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          catalogGeneration == _catalogGeneration) {
        setState(() => _error =
            'Catálogo indisponível. Nenhum resultado antigo será usado.');
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          catalogGeneration == _catalogGeneration) {
        setState(() => _busy = false);
        _schedulePendingLink();
      }
    }
  }

  Future<void> _logout() async {
    azsignRequestedRemoteId.value = null;
    _searchTimer?.cancel();
    _search.clear();
    _catalogGeneration++;
    _generation++;
    setState(() {
      _session = null;
      _page = null;
      _request = null;
      _busy = true;
      _error = null;
    });
    try {
      try {
        await _enrollment.clear();
      } finally {
        await _auth.logout();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Não foi possível confirmar todas as etapas da saída. Confira o bloqueio da sessão no painel.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(AddressBookDevice device) async {
    final remoteId = device.remoteId;
    if (remoteId != null) await _connectRemoteId(remoteId);
  }

  Future<void> _connectRemoteId(String remoteId) async {
    final session = _session;
    if (session == null ||
        widget.onConnect == null) {
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _enrollment.provision(session.token);
      if (!mounted || generation != _generation) return;
      await widget.onConnect!(profile, remoteId);
      if (azsignRequestedRemoteId.value == remoteId) {
        azsignRequestedRemoteId.value = null;
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Conexão não iniciada. Verifique autorização, certificado e disponibilidade do CMS.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
      _schedulePendingLink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Padding(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Dispositivos AZSign',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (session != null)
            Row(children: [
              Expanded(
                  child: Text('${session.user.email}\n${session.tenant.name}')),
              TextButton(
                  onPressed: _busy ? null : _logout, child: const Text('Sair')),
            ]),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, semanticsLabel: _error)),
          if (_busy) const LinearProgressIndicator(),
          if (session == null) ...[
            const SizedBox(height: 24),
            const Text(
                'Entre pelo navegador. Sua senha não é digitada neste aplicativo.'),
            const SizedBox(height: 16),
            if (_request != null)
              SelectableText(
                  'Confira este código no navegador: ${_request!.userCode}'),
            ElevatedButton(
                onPressed: _busy ? null : _login,
                child: const Text('Entrar com AZSign')),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
                'O certificado local é validado antes de cada conexão. O gateway confirma a autorização.'),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: _searchChanged,
              onSubmitted: (_) {
                _searchTimer?.cancel();
                _load(1);
              },
              decoration: InputDecoration(
                labelText: 'Buscar player pelo nome',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _searchChanged('');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
                child: ListView(children: [
              for (final device in _page?.devices ?? <AddressBookDevice>[])
                ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(device.name),
                  subtitle: Text(
                      'ID RustDesk: ${device.remoteId ?? "não provisionado"} · ${device.playerStatus.name}\nAcesso remoto: ${device.remoteAccessStatus.name}'),
                  trailing: Tooltip(
                      message:
                          'Conectar pelo gateway autenticado com a identidade deste login.',
                      child: OutlinedButton(
                          onPressed: _busy ||
                                  widget.onConnect == null ||
                                  device.remoteId == null ||
                                  [
                                    RemoteTransportStatus.blocked,
                                    RemoteTransportStatus.revoked,
                                    RemoteTransportStatus.unprovisioned
                                  ].contains(device.remoteAccessStatus)
                              ? null
                              : () => _connect(device),
                          child: const Text('Conectar'))),
                ),
              if (!_busy && _page?.devices.isEmpty == true)
                Text(_search.text.trim().isEmpty
                    ? 'Nenhum dispositivo autorizado.'
                    : 'Nenhum player encontrado para esta busca.'),
            ])),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: _busy || (_page?.pagination.currentPage ?? 1) <= 1
                      ? null
                      : () => _load(_page!.pagination.currentPage - 1),
                  child: const Text('Anterior')),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => _load(_page?.pagination.currentPage ?? 1),
                  child: const Text('Atualizar')),
              TextButton(
                  onPressed: _busy ||
                          _page == null ||
                          _page!.pagination.currentPage >=
                              _page!.pagination.lastPage
                      ? null
                      : () => _load(_page!.pagination.currentPage + 1),
                  child: const Text('Próxima')),
            ]),
          ],
        ]));
  }
}
