import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_models.dart';
import '../domain/ai_prompts.dart';
import 'ai_client.dart';

/// Direct personal-key mode: key stays in memory and only goes to DeepSeek.
class AiDeepSeekClient implements AiGateway {
  AiDeepSeekClient({
    required this.apiKey,
    this.model = 'deepseek-flash',
    Duration timeout = const Duration(seconds: 90),
    http.Client Function()? clientFactory,
  }) : _transport = AiHttpTransport(
         credential: apiKey.trim(),
         timeout: timeout,
         clientFactory: clientFactory,
       );
  final String apiKey, model;
  final AiHttpTransport _transport;

  void _validate() {
    if (apiKey.trim().isEmpty ||
        apiKey.contains(RegExp(r'\s')) ||
        model.trim().isEmpty ||
        model.length > 200) {
      throw const AiException('not_configured');
    }
  }

  @override
  Future<AiSuggestion> generate(
    AiRequest request,
    AiCancellation cancellation,
  ) async {
    _validate();
    request.validate();
    final response = await _transport.send(
      'POST',
      Uri.https('api.deepseek.com', '/chat/completions'),
      cancellation,
      data: {
        'model': model.trim(),
        'stream': false,
        'max_tokens': 4000,
        'reasoning_effort': 'none',
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': aiSystemPrompt},
          {'role': 'user', 'content': jsonEncode(aiPromptFor(request))},
        ],
      },
    );
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiException('empty_response');
    }
    final choice = choices.first;
    if (choice is! Map || choice['message'] is! Map) {
      throw const AiException('invalid_response');
    }
    final message = choice['message'] as Map;
    if (message['refusal'] != null && message['refusal'] != '' ||
        choice['finish_reason'] == 'content_filter') {
      throw const AiException('refused');
    }
    if (choice['finish_reason'] == 'length') {
      throw const AiException('truncated');
    }
    if (choice['finish_reason'] != 'stop') {
      throw const AiException('provider_error');
    }
    final content = message['content'];
    if (content == null || content == '') {
      throw const AiException('empty_response');
    }
    if (content is! String) throw const AiException('invalid_response');
    if (content.trim().isEmpty) throw const AiException('empty_response');
    dynamic result;
    try {
      result = jsonDecode(content);
    } catch (_) {
      throw const AiException('invalid_json');
    }
    cancellation.check();
    return AiSuggestion.fromJson({
      'result': result,
      'model': response['model'] ?? model.trim(),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'promptVersion': aiPromptVersion,
    }, request: request);
  }

  @override
  Future<String> health() async {
    _validate();
    final response = await _transport.send(
      'GET',
      Uri.https('api.deepseek.com', '/models'),
      AiCancellation(),
    );
    final models = response['data'];
    if (models is! List || models.any((m) => m is! Map || m['id'] is! String)) {
      throw const AiException('invalid_response');
    }
    if (!models.any((m) => m['id'] == model.trim())) {
      throw const AiException('model_unavailable');
    }
    return 'DeepSeek 已连接；连接测试未生成内容';
  }
}
