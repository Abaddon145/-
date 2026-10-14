import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uuid/uuid.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/data/ai_client.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late AiRequest request;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    request = AiRequest(
      requestId: const Uuid().v4(),
      word: await addAiWord(db, '시험'),
      context: '日常韩语',
      type: 'complete',
    );
  });
  tearDown(() => db.close());
  AiProxyClient client(
    Future<http.Response> Function(http.Request) handler, {
    Duration? timeout,
  }) => AiProxyClient(
    address: 'https://unit-test.invalid',
    credential: 'unit-test-credential',
    timeout: timeout ?? const Duration(seconds: 1),
    clientFactory: () => MockClient(handler),
  );
  test('unconfigured clients never make a request', () async {
    final proxy = AiProxyClient(address: '', credential: '');
    await expectLater(
      proxy.generate(request, AiCancellation()),
      throwsA(
        isA<AiException>().having((e) => e.code, 'code', 'not_configured'),
      ),
    );
  });
  test(
    'sends only chosen fields with auth, validates JSON and identity, no automatic retry',
    () async {
      var count = 0;
      http.Request? observed;
      final proxy = client((r) async {
        count++;
        observed = r;
        return http.Response(
          jsonEncode(suggestionFor(request).toJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      expect(
        (await proxy.generate(request, AiCancellation())).wordId,
        request.word.id,
      );
      expect(count, 1);
      expect(observed!.headers['authorization'], 'Bearer unit-test-credential');
      final body = jsonDecode(observed!.body) as Map;
      expect(body.containsKey('studyHistory'), false);
      expect(body.containsKey('source'), false);
      await expectLater(
        client(
          (_) async => http.Response('{', 200),
        ).generate(request, AiCancellation()),
        throwsA(
          isA<AiException>().having((e) => e.code, 'code', 'invalid_json'),
        ),
      );
      await expectLater(
        client(
          (_) async => http.Response(
            jsonEncode(
              suggestionFor(request, changes: {'wordId': 999}).toJson(),
            ),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ).generate(request, AiCancellation()),
        throwsA(
          isA<AiException>().having((e) => e.code, 'code', 'identity_mismatch'),
        ),
      );
    },
  );
  for (final code in [
    'refused',
    'truncated',
    'empty_response',
    'rate_limited',
    'timeout',
    'unauthorized',
  ]) {
    test('proxy distinguishes $code', () async {
      await expectLater(
        client(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': code},
            }),
            code == 'rate_limited' ? 429 : 502,
          ),
        ).generate(request, AiCancellation()),
        throwsA(isA<AiException>().having((e) => e.code, 'code', code)),
      );
    });
  }
  test(
    'offline is independent of learning and oversized responses are rejected',
    () async {
      await expectLater(
        client(
          (_) async => throw http.ClientException('offline'),
        ).generate(request, AiCancellation()),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'network')),
      );
      expect(
        await db.nextTrainingWord(const SessionOptions(), DateTime.now()),
        isNotNull,
      );
      await expectLater(
        client(
          (_) async => http.Response(List.filled(32769, 'x').join(), 200),
        ).generate(request, AiCancellation()),
        throwsA(isA<AiException>()),
      );
    },
  );
  test(
    'actual AbortableRequest cancellation and timeout stop the HTTP send',
    () async {
      for (final timeout in [false, true]) {
        final transport = AbortTransport(), cancellation = AiCancellation();
        final proxy = AiProxyClient(
          address: 'https://unit-test.invalid',
          credential: 'unit-test',
          timeout: Duration(milliseconds: timeout ? 20 : 1000),
          clientFactory: () => transport,
        );
        final pending = proxy.generate(request, cancellation);
        await transport.started.future;
        if (!timeout) cancellation.cancel();
        await expectLater(
          pending,
          throwsA(
            isA<AiException>().having(
              (e) => e.code,
              'code',
              timeout ? 'timeout' : 'cancelled',
            ),
          ),
        );
        expect(transport.aborted, true);
        expect(transport.closed, true);
      }
    },
  );
}

class AbortTransport extends http.BaseClient {
  final started = Completer<void>();
  bool aborted = false, closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    await (request as http.AbortableRequest).abortTrigger;
    aborted = true;
    throw http.RequestAbortedException(request.url);
  }

  @override
  void close() {
    closed = true;
  }
}
