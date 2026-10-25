import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_models.dart';

class AiCancellation {
  final _cancel = Completer<void>();
  bool get cancelled => _cancel.isCompleted;
  Future<void> get signal => _cancel.future;
  void cancel() {
    if (!cancelled) _cancel.complete();
  }

  void check() {
    if (cancelled) throw const AiException('cancelled');
  }
}

abstract class AiGateway {
  Future<AiSuggestion> generate(AiRequest request, AiCancellation cancellation);
  Future<String> health();
}

/// Load the saved configuration before choosing a provider for the first call.
class AiDeferredGateway implements AiGateway {
  AiDeferredGateway(this._create);
  final Future<AiGateway> Function() _create;
  late final Future<AiGateway> ready = _create();
  @override
  Future<AiSuggestion> generate(
    AiRequest request,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    final gateway = await ready;
    cancellation.check();
    return gateway.generate(request, cancellation);
  }

  @override
  Future<String> health() async => (await ready).health();
}

class AiProxyClient implements AiGateway {
  AiProxyClient({
    required this.address,
    required this.credential,
    this.timeout = const Duration(seconds: 90),
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final String address, credential;
  final Duration timeout;
  final http.Client Function() _clientFactory;
  Uri _uri(String path) {
    final base = Uri.tryParse(address.trim());
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.query.isNotEmpty ||
        base.fragment.isNotEmpty ||
        (base.scheme != 'https' &&
            !(base.scheme == 'http' &&
                ['localhost', '127.0.0.1'].contains(base.host))) ||
        credential.trim().isEmpty) {
      throw const AiException('not_configured');
    }
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}$path',
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    AiCancellation cancellation, {
    Object? data,
  }) async {
    return AiHttpTransport(
      credential: credential,
      timeout: timeout,
      clientFactory: _clientFactory,
    ).send(method, _uri(path), cancellation, data: data, proxyErrors: true);
  }

  @override
  Future<AiSuggestion> generate(
    AiRequest request,
    AiCancellation cancellation,
  ) async {
    request.validate();
    return AiSuggestion.fromJson(
      await _send(
        'POST',
        '/v1/${request.type}',
        cancellation,
        data: request.toJson(),
      ),
      request: request,
    );
  }

  @override
  Future<String> health() async {
    final json = await _send('GET', '/health', AiCancellation());
    if (json['promptVersion'] != aiPromptVersion) {
      throw const AiException('prompt_mismatch');
    }
    if (json['status'] != 'ready') throw const AiException('not_configured');
    return '服务已连接';
  }
}

/// Shared cancellable HTTP transport; never persists or logs credentials or bodies.
class AiHttpTransport {
  AiHttpTransport({
    required this.credential,
    this.timeout = const Duration(seconds: 90),
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final String credential;
  final Duration timeout;
  final http.Client Function() _clientFactory;
  Future<Map<String, dynamic>> send(
    String method,
    Uri uri,
    AiCancellation cancellation, {
    Object? data,
    bool proxyErrors = false,
  }) async {
    final client = _clientFactory();
    var timedOut = false;
    final requestCancellation = AiCancellation();
    final timer = Timer(timeout, () {
      timedOut = true;
      requestCancellation.cancel();
      client.close();
    });
    try {
      cancellation.check();
      final request =
          http.AbortableRequest(
              method,
              uri,
              abortTrigger: Future.any<void>([
                cancellation.signal,
                requestCancellation.signal,
              ]),
            )
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer $credential',
              'Content-Type': 'application/json',
            });
      if (data != null) request.body = jsonEncode(data);
      final response = await client.send(request);
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 32768) throw const AiException('invalid_response');
        cancellation.check();
        requestCancellation.check();
      }
      cancellation.check();
      requestCancellation.check();
      dynamic json;
      try {
        json = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        if (response.statusCode == 200) throw const AiException('invalid_json');
      }
      if (response.statusCode != 200) {
        final code = proxyErrors && json is Map && json['error'] is Map
            ? json['error']['code']
            : null;
        throw AiException(
          code is String && code.length < 50
              ? code
              : response.statusCode == 401 || response.statusCode == 403
              ? 'unauthorized'
              : response.statusCode == 429
              ? 'rate_limited'
              : response.statusCode == 402
              ? 'insufficient_balance'
              : response.statusCode == 408 || response.statusCode == 504
              ? 'timeout'
              : 'provider_error',
          retryAfterSeconds: response.statusCode == 429
              ? aiRetryAfterSeconds(response.headers['retry-after'])
              : null,
        );
      }
      if (json is! Map<String, dynamic>) {
        throw const AiException('invalid_response');
      }
      return json;
    } catch (error) {
      if (timedOut) throw const AiException('timeout');
      if (cancellation.cancelled) throw const AiException('cancelled');
      if (error is AiException) rethrow;
      throw const AiException('network');
    } finally {
      timer.cancel();
      client.close();
    }
  }
}

/// Only a bounded waiting hint; retries always require a user action.
int? aiRetryAfterSeconds(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value.trim());
  // Accept delta-seconds. Other formats use the ordinary rate-limit guidance.
  if (seconds == null || seconds < 0) return null;
  return seconds.clamp(1, 300);
}
