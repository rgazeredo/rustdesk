import 'azsign_http.dart';

const azsignCentralOrigin = 'https://app.azsign.com.br';

String? azsignPanelDomain(String value) {
  final domain = value.trim().toLowerCase();
  return domain.length <= 253 &&
          RegExp(r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$')
              .hasMatch(domain)
      ? domain
      : null;
}

Uri azsignPanelOrigin(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' ||
      azsignPanelDomain(uri.host) == null ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.port != 443 ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('Origem do painel inválida.');
  }
  return Uri.parse(uri.origin);
}

class AzsignInstallation {
  final String domain;
  final String name;
  final Uri origin;
  const AzsignInstallation(this.domain, this.name, this.origin);

  factory AzsignInstallation.fromDiscovery(
      String requested, Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map<String, dynamic> ||
        data['domain'] != requested ||
        !['internal', 'independent'].contains(data['type']) ||
        data['id'] is! String ||
        (data['id'] as String).isEmpty ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        (data['name'] as String).length > 255 ||
        data['api_base_url'] is! String) {
      throw const FormatException('O catálogo devolveu um painel inválido.');
    }
    return AzsignInstallation(requested, data['name'] as String,
        azsignPanelOrigin(data['api_base_url'] as String));
  }
}

class AzsignInstallationDiscovery {
  Future<AzsignInstallation> discover(String rawDomain) async {
    final domain = azsignPanelDomain(rawDomain);
    if (domain == null)
      throw const FormatException('Informe somente o domínio do painel.');
    final http = AzsignHttp(Uri.parse(azsignCentralOrigin));
    try {
      final response = await http.request(
          'POST', '/api/v1/box-manager/discover-installation',
          body: {'domain': domain});
      response.requireSuccess();
      return AzsignInstallation.fromDiscovery(domain, response.data);
    } finally {
      http.close();
    }
  }
}
