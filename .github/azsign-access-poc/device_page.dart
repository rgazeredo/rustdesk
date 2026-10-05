import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  bool _loading = false;
  bool _requesting = false;
  bool _unavailable = false;
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      await gFFI.serverModel.fetchID();
      final raw = await platformFFI.invokeMethod('azsign_device_status');
      if (!mounted) return;
      setState(() {
        _status = jsonDecode(raw as String) as Map<String, dynamic>;
        _unavailable = false;
      });
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _requestPermission(bool screen) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final model = gFFI.serverModel;
      if (screen && (!model.isStart || !model.mediaOk)) {
        await model.checkRequestNotificationPermission();
        await model.startService();
      } else if (!screen && !model.inputOk) {
        await model.toggleInput();
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
      await _refresh();
    }
  }

  String get _connectionLabel {
    final model = gFFI.serverModel;
    if (_unavailable) return 'Verificando equipamento';
    if (_status['state'] == 'APPLYING') return 'Atualizando acesso';
    final renewal = _status['renewal'] as Map<String, dynamic>? ?? {};
    if (renewal['enrolled'] == false) return 'Aguardando autorização';
    if (!model.isStart || !model.mediaOk || !model.inputOk) {
      return 'Permissões pendentes';
    }
    if (model.connectStatus > 0) return 'Pronto para acesso remoto';
    return 'Conectando';
  }

  @override
  Widget build(BuildContext context) {
    final model = gFFI.serverModel;
    final missingScreen = !model.isStart || !model.mediaOk;
    final missingInput = !model.inputOk;
    final ready = !missingScreen && !missingInput && model.connectStatus > 0;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff3124d9),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff5f6fa),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Image.asset('assets/azsign-remote.png',
                          width: 52,
                          height: 52,
                          semanticLabel: 'AZSign Remote'),
                      const SizedBox(width: 16),
                      const Expanded(
                          child: Text('AZSign Remote',
                              style: TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 28),
                    Card(
                      color: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: Color(0xffe1e4ed)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ID do equipamento',
                                  style: TextStyle(
                                      fontSize: 16, color: Color(0xff526074))),
                              const SizedBox(height: 12),
                              SelectableText(model.serverId.text,
                                  style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xff172033))),
                              const SizedBox(height: 24),
                              Semantics(
                                  liveRegion: true,
                                  child: Row(children: [
                                    Icon(
                                        ready
                                            ? Icons.check_circle_outline
                                            : Icons.schedule,
                                        color: ready
                                            ? const Color(0xff15704b)
                                            : const Color(0xff526074)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(_connectionLabel,
                                            style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w500))),
                                  ])),
                            ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (missingScreen || missingInput) ...[
                      const Text(
                          'Conclua apenas as permissões pendentes para permitir o suporte remoto.',
                          style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: Color(0xff526074))),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        if (missingScreen)
                          FilledButton.icon(
                            onPressed: _requesting
                                ? null
                                : () => _requestPermission(true),
                            icon: const Icon(Icons.screen_share_outlined),
                            label:
                                const Text('Permitir compartilhamento de tela'),
                          ),
                        if (missingInput)
                          OutlinedButton.icon(
                            onPressed: _requesting
                                ? null
                                : () => _requestPermission(false),
                            icon: const Icon(Icons.touch_app_outlined),
                            label: const Text('Permitir controle remoto'),
                          ),
                      ]),
                    ] else
                      const Text(
                          'As permissões estão ativas. O acesso é gerenciado pelo painel.',
                          style: TextStyle(
                              fontSize: 16, color: Color(0xff526074))),
                    const SizedBox(height: 28),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => showLicensePage(
                              context: context,
                              applicationName: 'AZSign Remote',
                              applicationLegalese:
                                  'Baseado no RustDesk · AGPL-3.0'),
                          child: const Text('Sobre o AZSign Remote'),
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
