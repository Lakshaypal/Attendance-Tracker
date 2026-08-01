import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'store.dart';

/// Preferred port, so the address shown on screen is usually the same one the
/// other device guesses.
const int kPreferredSyncPort = 45454;

/// A short-lived, code-protected server on the local network. Attendance data
/// never leaves the two devices and no account is involved.
class LocalSyncHost {
  static HttpServer? _server;
  static String? _pairCode;

  static bool get isRunning => _server != null;
  static String? get pairCode => _pairCode;
  static int? get port => _server?.port;

  static Future<List<String>> start(AttendanceStore store) async {
    if (_server != null) return localAddresses();
    _pairCode = (100000 + Random.secure().nextInt(900000)).toString();
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        kPreferredSyncPort,
      );
    } on SocketException {
      // The preferred port is busy; take whatever the OS offers instead.
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(
      (request) => _handle(request, store),
      onError: (_) {},
      cancelOnError: false,
    );
    return localAddresses();
  }

  static Future<void> stop() async {
    final server = _server;
    _server = null;
    _pairCode = null;
    if (server != null) await server.close(force: true);
  }

  static Future<List<String>> localAddresses() async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && !address.isLinkLocal) {
            addresses.add(address.address);
          }
        }
      }
    } catch (_) {
      // Sandboxed platforms can refuse the interface list; pairing still works
      // if the user knows the address.
    }
    return addresses;
  }

  static Future<void> _handle(
    HttpRequest request,
    AttendanceStore store,
  ) async {
    try {
      final code = request.uri.queryParameters['code'];
      // Constant-time-ish comparison is overkill on a LAN, but a wrong code
      // must never leak data.
      if (code == null || _pairCode == null || code != _pairCode) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write('Pairing code is invalid.');
        await request.response.close();
        return;
      }
      if (request.uri.path != '/sync') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      switch (request.method) {
        case 'GET':
          request.response.write(jsonEncode(store.snapshot));
        case 'PUT':
          try {
            final body = await utf8.decoder.bind(request).join();
            final decoded = jsonDecode(body);
            if (decoded is! Map) throw const FormatException('Not an object.');
            store.applySnapshot(Map<String, dynamic>.from(decoded));
            request.response.write(jsonEncode({'ok': true}));
          } catch (error) {
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write(
              jsonEncode({'ok': false, 'error': '$error'}),
            );
          }
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    } catch (_) {
      // A dropped connection must not take the server down.
    }
  }
}

class LocalSyncClient {
  static Future<Map<String, dynamic>> receive({
    required String address,
    required String code,
  }) async {
    final body = await _request(address: address, code: code, method: 'GET');
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('The other device sent an unreadable reply.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<void> send({
    required String address,
    required String code,
    required Map<String, dynamic> data,
  }) async {
    await _request(address: address, code: code, method: 'PUT', data: data);
  }

  static Future<String> _request({
    required String address,
    required String code,
    required String method,
    Map<String, dynamic>? data,
  }) async {
    final uri = syncUri(address, code);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(method, uri);
      if (data != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(data));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          body.isEmpty ? 'The other device refused the sync.' : body,
          uri: uri,
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Uri syncUri(String address, String code) {
    final entered = address.trim();
    if (entered.isEmpty) {
      throw const FormatException(
        'Enter the address shown on the other device.',
      );
    }
    final source = entered.contains('://') ? entered : 'http://$entered';
    final Uri parsed;
    try {
      parsed = Uri.parse(source);
    } on FormatException {
      throw const FormatException('That address could not be understood.');
    }
    if (parsed.host.isEmpty) {
      throw const FormatException(
        'Enter the address shown on the other device.',
      );
    }
    final trimmedCode = code.trim();
    if (trimmedCode.length != 6 || int.tryParse(trimmedCode) == null) {
      throw const FormatException('The pairing code is six digits.');
    }
    return parsed.replace(
      scheme: 'http',
      port: parsed.hasPort ? parsed.port : kPreferredSyncPort,
      path: '/sync',
      queryParameters: {'code': trimmedCode},
    );
  }
}
