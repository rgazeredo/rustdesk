import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

// RSA generation runs off the UI isolate. Native operations are serialized by
// a mutex shared with the Rust transport; private key bytes never enter Dart.
String _windowsRequest(String request) {
  final library = DynamicLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}\\librustdesk.dll');
  final call = library.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('azsign_windows_dispatch');
  final release = library.lookupFunction<Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('azsign_windows_free');
  final input = request.toNativeUtf8();
  try {
    final output = call(input);
    if (output == nullptr) throw StateError('Native response unavailable');
    try {
      return output.toDartString();
    } finally {
      release(output);
    }
  } finally {
    calloc.free(input);
  }
}

Future<T?> azsignNativeInvoke<T>(MethodChannel channel, String method,
    [Map<String, dynamic>? arguments]) async {
  if (!Platform.isWindows) return channel.invokeMethod<T>(method, arguments);
  final input = jsonEncode({'method': method, 'args': arguments ?? {}});
  try {
    final response = jsonDecode(await Isolate.run(() => _windowsRequest(input)))
        as Map<String, dynamic>;
    if (response['ok'] != true) throw StateError('Native operation rejected');
    return response['value'] as T?;
  } catch (_) {
    throw PlatformException(
        code: 'azsign_native_unavailable',
        message: 'Não foi possível acessar a identidade segura do Windows.');
  }
}
