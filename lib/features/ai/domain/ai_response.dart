import 'dart:convert';

abstract interface class AiRequestIdentity {
  String get requestId;
  int get wordId;
  String get originalTerm;
  String get context;
}

const aiPromptVersion = 'ko-zh-v1';
const aiContexts = ['日常韩语', '物流与仓储', '工厂设备', '生产与工业术语', '商务邮件', '自定义语境'];
const aiFieldLabels = <String, String>{
  'meaningZh': '中文释义与义项',
  'partOfSpeech': '词性',
  'baseForm': '原形',
  'collocations': '常见搭配',
  'exampleKo': '韩文例句',
  'exampleZh': '例句中文',
  'workExampleKo': '工作场景例句',
  'workExampleZh': '工作例句中文',
  'usageNote': '正式、口语与工作用法',
  'grammarNote': '语法说明',
  'ambiguityNotes': '候选义项与所需语境',
  'confusingWords': '易混淆词',
  'terminologyNote': '英韩术语对应',
};
const aiListFields = {'collocations', 'ambiguityNotes', 'confusingWords'};
const aiFieldLimits = <String, int>{
  'meaningZh': 2000,
  'partOfSpeech': 200,
  'baseForm': 200,
  'exampleKo': 1000,
  'exampleZh': 1000,
  'workExampleKo': 1000,
  'workExampleZh': 1000,
  'usageNote': 2000,
  'grammarNote': 2000,
  'terminologyNote': 2000,
};

class AiException implements Exception {
  const AiException(this.code);
  final String code;
  String get message =>
      const {
        'not_configured': '请先在 AI 设置中填写代理地址和本次会话凭证。',
        'unauthorized': '代理访问凭证无效，请重新填写。',
        'network': '无法连接 AI 服务，请检查网络。普通背词仍可使用。',
        'timeout': 'AI 请求超时，可稍后手动重试。',
        'rate_limited': '请求达到服务限额，请稍后重试。',
        'cancelled': '请求已取消。',
        'refused': '模型拒绝生成该内容，请调整语境。',
        'truncated': '结果被截断，未保存；请重新生成。',
        'empty_response': '模型返回空内容，未保存。',
        'invalid_json': '结果不是合法 JSON，未保存。',
        'invalid_response': '结果缺少字段或超过长度限制，未保存。',
        'identity_mismatch': '结果与原请求不匹配，已拒绝写入。',
        'provider_error': '模型服务出错，请稍后重试。',
        'deleted': '原词已删除，无法保存。',
        'already_saved': '该建议已经保存，请生成新建议。',
        'duplicate': '拼写或原形与现有词条重复，请调整后重试。',
        'conflict': '原词已发生变化，需要重新对比并确认。',
        'batch_limit': '每个 AI 任务可选择 1–20 个词；可分批继续。',
        'busy': '已有 AI 任务正在运行，请先完成或取消。',
        'request_too_large': '请求内容超过限制，请缩短词条或语境。',
        'prompt_mismatch': '代理提示词版本不兼容，请更新服务。',
      }[code] ??
      'AI 服务暂不可用（$code）。';
  @override
  String toString() => message;
}

class AiSuggestion {
  AiSuggestion({
    required this.result,
    required this.model,
    required this.generatedAt,
    required this.promptVersion,
  });
  final Map<String, dynamic> result;
  final String model, promptVersion;
  final DateTime generatedAt;
  String get requestId => result['requestId'] as String;
  int get wordId => result['wordId'] as int;
  String get context => result['context'] as String;
  bool get needsMoreContext => result['needsMoreContext'] as bool;
  bool get suspectedTypo => result['suspectedTypo'] as bool;
  List<String> get spellings => (result['suggestedSpellings'] as List)
      .cast<String>()
      .where((s) => s.trim().isNotEmpty)
      .toSet()
      .toList();
  String fieldText(String key) => result[key] is List
      ? (result[key] as List).join('\n')
      : result[key] as String;
  Map<String, Object?> toJson() => {
    'result': result,
    'model': model,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'promptVersion': promptVersion,
  };
  factory AiSuggestion.fromJson(
    Map<String, dynamic> json, {
    AiRequestIdentity? request,
  }) {
    if (utf8.encode(jsonEncode(json)).length > 32768 ||
        json['result'] is! Map<String, dynamic>) {
      throw const AiException('invalid_response');
    }
    final data = Map<String, dynamic>.from(json['result'] as Map);
    final required = {
      ...aiFieldLabels.keys,
      'requestId',
      'wordId',
      'originalTerm',
      'context',
      'suspectedTypo',
      'suggestedSpellings',
      'needsMoreContext',
    };
    if (data.length != required.length || !required.every(data.containsKey)) {
      throw const AiException('invalid_response');
    }
    for (final entry in {
      ...aiFieldLimits,
      'originalTerm': 200,
      'context': 600,
      'requestId': 36,
    }.entries) {
      if (data[entry.key] is! String ||
          (data[entry.key] as String).length > entry.value) {
        throw const AiException('invalid_response');
      }
    }
    for (final key in {...aiListFields, 'suggestedSpellings'}) {
      final list = data[key];
      if (list is! List ||
          list.length > (key == 'suggestedSpellings' ? 5 : 6) ||
          list.any(
            (item) =>
                item is! String ||
                item.length > (key == 'suggestedSpellings' ? 200 : 500),
          )) {
        throw const AiException('invalid_response');
      }
    }
    if (data['wordId'] is! int ||
        data['wordId'] <= 0 ||
        data['suspectedTypo'] is! bool ||
        data['needsMoreContext'] is! bool ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(data['requestId'] as String) ||
        (data['originalTerm'] as String).isEmpty ||
        (data['context'] as String).isEmpty ||
        json['model'] is! String ||
        (json['model'] as String).isEmpty ||
        (json['model'] as String).length > 200 ||
        json['promptVersion'] is! String ||
        (json['promptVersion'] as String).length > 100 ||
        json['generatedAt'] is! String ||
        DateTime.tryParse(json['generatedAt'] as String) == null) {
      throw const AiException('invalid_response');
    }
    if (json['promptVersion'] != aiPromptVersion) {
      throw const AiException('prompt_mismatch');
    }
    if (request != null &&
        (data['requestId'] != request.requestId ||
            data['wordId'] != request.wordId ||
            data['originalTerm'] != request.originalTerm ||
            data['context'] != request.context)) {
      throw const AiException('identity_mismatch');
    }
    return AiSuggestion(
      result: data,
      model: json['model'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      promptVersion: json['promptVersion'] as String,
    );
  }
  AiSuggestion edited(Map<String, String> fields) {
    final copy = Map<String, dynamic>.from(result);
    for (final entry in fields.entries) {
      if (!aiFieldLabels.containsKey(entry.key)) {
        throw const AiException('invalid_response');
      }
      copy[entry.key] = aiListFields.contains(entry.key)
          ? entry.value
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : entry.value.trim();
    }
    return AiSuggestion.fromJson({...toJson(), 'result': copy});
  }
}
