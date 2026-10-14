import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'azsign_auth_adapter.dart';
import 'azsign_desktop_page.dart';
import 'azsign_http.dart';
import 'azsign_installation.dart';
import 'azsign_native_channel.dart';
import 'azsign_native_storage.dart';

class AzsignPanelPage extends StatefulWidget {
  final String defaultOrigin;
  final AzsignSecureStorage? storage;
  final AzsignInstallationDiscovery? discovery;
  final AzsignHttp Function(Uri)? httpFactory;
  final Future<void> Function(Map<String, dynamic>, String)? onConnect;
  const AzsignPanelPage(
      {super.key,
      required this.defaultOrigin,
      this.storage,
      this.discovery,
      this.httpFactory,
      this.onConnect});

  @override
  State<AzsignPanelPage> createState() => _AzsignPanelPageState();
}

class _AzsignPanelPageState extends State<AzsignPanelPage> {
  static const _key = 'azsign_desktop_panel';
  late final _storage = widget.storage ?? AzsignNativeStorage();
  late final _discovery = widget.discovery ?? AzsignInstallationDiscovery();
  final _domain = TextEditingController();
  AzsignInstallation? _installation;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  Future<void> _clearNative() => azsignNativeInvoke<void>(
      const MethodChannel('org.rustdesk.rustdesk/host'), 'azsignIdentityClear');

  AzsignInstallation get _default {
    final origin = azsignPanelOrigin(widget.defaultOrigin);
    return AzsignInstallation(origin.host, 'AZSign', origin);
  }

  Future<void> _restore() async {
    try {
      // A previous process may have exited before logout. Never reuse its
      // transport certificate before restoring the matching CMS session.
      await _clearNative();
      final saved = await _storage.read(_key);
      var installation = _default;
      if (saved != null) {
        final record = jsonDecode(saved) as Map<String, dynamic>;
        final domain = azsignPanelDomain(record['domain'] as String);
        if (domain == null) throw const FormatException('Painel inválido.');
        if (!mounted) return;
        _domain.text = domain;
        installation = domain == _default.domain
            ? _default
            : await _discovery.discover(domain);
        if (record['origin'] != installation.origin.origin) {
          throw StateError(
              'A origem cadastrada mudou. Selecione o painel novamente.');
        }
      }
      if (mounted) setState(() => _installation = installation);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Não foi possível validar o painel salvo. Confira a conexão e selecione o painel novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select({bool primary = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final installation =
          primary ? _default : await _discovery.discover(_domain.text);
      await _clearNative();
      await _storage.write(
          _key,
          jsonEncode({
            'domain': installation.domain,
            'origin': installation.origin.origin,
          }));
      if (mounted) setState(() => _installation = installation);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Painel indisponível. Informe o domínio cadastrado e confira a conexão e o armazenamento seguro.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePanel() async {
    await _storage.delete(_key);
    if (mounted)
      setState(() {
        _installation = null;
        _error = null;
      });
  }

  @override
  Widget build(BuildContext context) {
    final installation = _installation;
    if (installation != null)
      return AzsignDesktopPage(
        key: ValueKey('${installation.domain}|${installation.origin.origin}'),
        cmsOrigin: installation.origin.origin,
        panelDomain: installation.domain,
        panelName: installation.name,
        secureStorage: _storage,
        httpFactory: widget.httpFactory,
        onConnect: widget.onConnect,
        onChangePanel: _changePanel,
      );
    return Center(
        child: SingleChildScrollView(
            child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Conectar ao seu painel',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text(
                  'Use o domínio do painel da sua empresa para entrar e acessar seus players.'),
              const SizedBox(height: 20),
              TextField(
                  controller: _domain,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: (_) {
                    if (!_busy) _select();
                  },
                  decoration: const InputDecoration(
                      labelText: 'Domínio do painel',
                      hintText: 'painel.exemplo.com.br',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!, semanticsLabel: _error),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: _busy ? null : () => _select(),
                  child: const Text('Usar este painel')),
              TextButton(
                  onPressed: _busy ? null : () => _select(primary: true),
                  child: const Text('Usar painel AZSign')),
            ],
          )),
    )));
  }
}
