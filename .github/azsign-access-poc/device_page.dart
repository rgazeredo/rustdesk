import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../common.dart';
import '../../models/platform_model.dart';

class AzsignDevicePage extends StatefulWidget {
  const AzsignDevicePage({super.key});
  @override
  State<AzsignDevicePage> createState() => _AzsignDevicePageState();
}

class _AzsignDevicePageState extends State<AzsignDevicePage>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _hide;
  bool _loading = false;
  bool _revealed = false;
  String _password = '';
  String _error = '';
  String _server = '';
  String _key = '';
  String _proxy = '';
  Map<String, dynamic> _status = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _hide?.cancel();
    _password = '';
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _password = '';
        _revealed = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final raw = await platformFFI.invokeMethod('azsign_device_status');
      final options =
          jsonDecode(await bind.mainGetOptions()) as Map<String, dynamic>;
      final socks = await bind.mainGetSocks();
      String option(String key) => (options[key] as String?)?.isNotEmpty == true
          ? options[key] as String
          : bind.mainGetBuildinOption(key: key);
      if (!mounted) return;
      setState(() {
        _status = jsonDecode(raw as String) as Map<String, dynamic>;
        _server = option('custom-rendezvous-server');
        _key = option('key');
        _proxy = socks.isNotEmpty && socks.first.isNotEmpty
            ? socks.first
            : 'Sem proxy';
        _error = '';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Não foi possível consultar o estado. Tentando novamente…');
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _showPassword() async {
    if (_revealed) {
      setState(() {
        _revealed = false;
        _password = '';
      });
      return;
    }
    try {
      final value =
          await platformFFI.invokeMethod('azsign_device_password') as String? ??
              '';
      if (!mounted) return;
      setState(() {
        _password = value;
        _revealed = true;
      });
      _hide?.cancel();
      _hide = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _revealed = false;
            _password = '';
          });
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Senha indisponível neste aparelho. Consulte o painel.');
      }
    }
  }

  String get _connectionLabel {
    if (_error.isNotEmpty) return 'Verificando equipamento';
    if (gFFI.serverModel.connectStatus > 0) return 'Pronto para conexão';
    if (_status['state'] == 'APPLYING') return 'Aplicando autorização';
    final renewal = _status['renewal'] as Map<String, dynamic>? ?? {};
    if (renewal['enrolled'] == false) return 'Aguardando autorização no painel';
    return 'Conectando ao AZSign';
  }

  Widget _value(String label, String value, {bool large = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Color(0xff526074), fontSize: 14)),
          const SizedBox(height: 6),
          SelectableText(value.isEmpty ? 'Não informado' : value,
              style: TextStyle(
                  fontSize: large ? 32 : 16,
                  fontWeight: large ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
  Widget _card(String title, List<Widget> children) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xffdce2eb))),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ...children,
                ])),
      );
  @override
  Widget build(BuildContext context) {
    final model = gFFI.serverModel;
    final profile = _status['profile'] as Map<String, dynamic>? ?? {};
    return Theme(
      data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff3124d9), brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xfff4f6fa)),
      child: Scaffold(
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    SvgPicture.asset('assets/azsign-remote.svg',
                        width: 56, height: 56, semanticsLabel: 'AZSign Remote'),
                    const SizedBox(width: 16),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('AZSign Remote',
                              style: TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.w700)),
                          Text('Acesso remoto do equipamento',
                              style: TextStyle(color: Color(0xff526074)))
                        ])),
                    IconButton(
                        tooltip: 'Atualizar estado',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh)),
                  ]),
                  const SizedBox(height: 24),
                  Semantics(
                      liveRegion: true,
                      child: Row(children: [
                        Icon(
                            model.connectStatus > 0
                                ? Icons.check_circle_outline
                                : Icons.schedule,
                            color: const Color(0xff3124d9)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_connectionLabel,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600)))
                      ])),
                  if (_error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error)),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, constraints) {
                    final identity = _card('Este equipamento', [
                      _value('ID de acesso', model.serverId.text, large: true),
                      const Divider(),
                      _value(
                          'Senha permanente',
                          _revealed
                              ? (_password.isEmpty
                                  ? 'Configurada anteriormente. Consulte o painel.'
                                  : _password)
                              : '••••••••'),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                              onPressed: _showPassword,
                              icon: Icon(_revealed
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              label: Text(_revealed
                                  ? 'Ocultar senha'
                                  : 'Mostrar senha'))),
                      if ((_status['player_name'] as String? ?? '').isNotEmpty)
                        _value('Vínculo no painel',
                            '${_status['player_name']} · ${_status['tenant_name']}'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          onPressed: () async {
                            await model.toggleService();
                            if (mounted) setState(() {});
                          },
                          icon: Icon(model.isStart
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline),
                          label: Text(model.isStart
                              ? 'Parar compartilhamento'
                              : 'Iniciar compartilhamento')),
                      TextButton.icon(
                          onPressed: () async {
                            await model.toggleInput();
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.touch_app_outlined),
                          label: Text(model.inputOk
                              ? 'Controle de toque habilitado'
                              : 'Habilitar controle de toque')),
                    ]);
                    final network = _card('Rede gerenciada', [
                      const Text(
                          'Configurações fornecidas pelo AZSign, disponíveis nesta tela somente para consulta.',
                          style: TextStyle(color: Color(0xff526074))),
                      _value('Servidor ID', _server),
                      _value('Chave pública do servidor', _key),
                      _value('Proxy configurado', _proxy),
                      if (profile['host'] != null)
                        _value(
                            'Servidor de acesso seguro', '${profile['host']}'),
                      const Divider(),
                      const Text(
                          'Após uma transferência ou recadastro, mantenha o equipamento conectado à internet. A autorização será recebida automaticamente.',
                          style: TextStyle(height: 1.5)),
                    ]);
                    if (constraints.maxWidth < 760) {
                      return Column(children: [identity, network]);
                    }
                    return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 16),
                          Expanded(child: network)
                        ]);
                  }),
                  const SizedBox(height: 18),
                  TextButton(
                      onPressed: () => showLicensePage(
                          context: context,
                          applicationName: 'AZSign Remote',
                          applicationLegalese:
                              'Baseado no RustDesk · AGPL-3.0'),
                      child: const Text('Baseado no RustDesk · Licenças')),
                ])),
      )))),
    );
  }
}
