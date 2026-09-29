import 'package:flutter/foundation.dart';

/// A link selects a target, never supplies credentials or gateway settings.
final azsignRequestedRemoteId = ValueNotifier<String?>(null);

String? azsignRemoteIdFromLink(Uri uri) {
  if (uri.scheme != 'azsign-remote' ||
      uri.authority != 'connection' ||
      uri.hasQuery ||
      uri.hasFragment ||
      !RegExp(r'^/new/[0-9]{6,16}$').hasMatch(uri.path)) return null;
  return uri.path.substring('/new/'.length);
}
