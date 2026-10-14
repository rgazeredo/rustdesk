import 'package:flutter/foundation.dart';
import 'azsign_installation.dart';

/// A link selects a target, never supplies credentials or gateway settings.
String? azsignRequestedPanelDomain;
final azsignRequestedRemoteId = ValueNotifier<String?>(null);

String? azsignRemoteIdFromLink(Uri uri) {
  if (uri.scheme != 'azsign-remote' ||
      uri.authority != 'connection' ||
      (uri.hasQuery &&
          (uri.queryParametersAll.length != 1 ||
              uri.queryParametersAll['panel']?.length != 1 ||
              azsignPanelDomain(uri.queryParameters['panel'] ?? '') !=
                  uri.queryParameters['panel'])) ||
      uri.hasFragment ||
      !RegExp(r'^/new/[0-9]{6,16}$').hasMatch(uri.path)) return null;
  return uri.path.substring('/new/'.length);
}
