import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../../core/database/backup_limits.dart';

class CloudBackupException implements Exception {
  const CloudBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CloudObject {
  const CloudObject({
    required this.name,
    this.content,
    this.url,
    this.createdAt,
  });

  final String name;
  final String? content;
  final String? url;
  final DateTime? createdAt;
}

const gistUploadLimit = 900000;
const backupFilePrefix = 'korean-memo-backup-';

String redactSecrets(String text, Iterable<String> secrets) {
  var out = text;
  for (final secret in secrets) {
    final value = secret.trim();
    if (value.length < 4) continue;
    out = out.replaceAll(value, '***');
  }
  return out;
}

String backupFileName(DateTime now) {
  final utc = now.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  return '$backupFilePrefix$stamp.json';
}

DateTime? backupFileTime(String name) {
  final match = RegExp(
    r'korean-memo-backup-(\d{8})T(\d{6})Z\.json$',
  ).firstMatch(name);
  if (match == null) return null;
  final day = match.group(1)!;
  final clock = match.group(2)!;
  return DateTime.tryParse(
    '${day.substring(0, 4)}-${day.substring(4, 6)}-${day.substring(6, 8)}T${clock.substring(0, 2)}:${clock.substring(2, 4)}:${clock.substring(4, 6)}Z',
  );
}

int clampCloudKeep(int value) => value.clamp(1, 20);

Uri parseWebDavDirectory(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw const CloudBackupException('WebDAV 地址需要以 https:// 开头');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const CloudBackupException('请把账号和密码填在下面，不要写进地址');
  }
  final text = uri.toString();
  return Uri.parse(text.endsWith('/') ? text : '$text/');
}

class CloudBackupApi {
  CloudBackupApi(this._client, {DateTime Function()? now}) : _now = now;

  final http.Client _client;
  final DateTime Function()? _now;

  DateTime get clock => _now?.call() ?? DateTime.now();

  Future<String> uploadGist({
    required String token,
    required String? gistId,
    required String body,
    required int keep,
  }) async {
    if (body.length > gistUploadLimit) {
      throw const CloudBackupException('这份备份超过 Gist 能保存的大小，请改用 WebDAV');
    }
    final name = backupFileName(clock);
    final headers = _githubHeaders(token);
    final limit = clampCloudKeep(keep);
    if (gistId == null || gistId.trim().isEmpty) {
      final response = await _send(
        () => _client.post(
          Uri.parse('https://api.github.com/gists'),
          headers: headers,
          body: jsonEncode({
            'description': '词忆备份',
            'public': false,
            'files': {
              name: {'content': body},
            },
          }),
        ),
        [token],
      );
      final id = (jsonDecode(response.body) as Map)['id'];
      if (id is! String || id.isEmpty) {
        throw const CloudBackupException('GitHub 没有返回备份编号');
      }
      return id;
    }
    final current = await _send(
      () => _client.get(
        Uri.parse('https://api.github.com/gists/${gistId.trim()}'),
        headers: headers,
      ),
      [token],
    );
    final existing = _gistNames(current.body);
    existing.sort();
    final overflow = existing.length + 1 - limit;
    final remove = overflow > 0
        ? existing.take(overflow).toList()
        : const <String>[];
    await _send(
      () => _client.patch(
        Uri.parse('https://api.github.com/gists/${gistId.trim()}'),
        headers: headers,
        body: jsonEncode({
          'files': {
            name: {'content': body},
            for (final old in remove) old: null,
          },
        }),
      ),
      [token],
    );
    return gistId.trim();
  }

  Future<List<CloudObject>> listGist({
    required String token,
    required String gistId,
  }) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('https://api.github.com/gists/$gistId'),
        headers: _githubHeaders(token),
      ),
      [token],
    );
    final files = (jsonDecode(response.body) as Map)['files'];
    if (files is! Map) return const [];
    final versions = <CloudObject>[];
    for (final entry in files.entries) {
      final name = entry.key;
      if (name is! String || !name.startsWith(backupFilePrefix)) continue;
      final meta = entry.value;
      if (meta is! Map) continue;
      final truncated = meta['truncated'] == true;
      final content = meta['content'];
      final raw = meta['raw_url'];
      versions.add(
        CloudObject(
          name: name,
          content: !truncated && content is String && content.isNotEmpty
              ? content
              : null,
          url: raw is String ? raw : null,
          createdAt: backupFileTime(name),
        ),
      );
    }
    versions.sort((a, b) => b.name.compareTo(a.name));
    return versions;
  }

  Future<void> uploadWebDav({
    required Uri directory,
    required String user,
    required String password,
    required String body,
    required int keep,
  }) async {
    if (body.length > maxBackupBytes) {
      throw const CloudBackupException('备份超过 50 MB，云端没有接收');
    }
    final name = backupFileName(clock);
    final target = directory.resolve(name);
    final headers = _webdavHeaders(user, password);
    await _send(
      () => _client.put(
        target,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: body,
      ),
      [user, password],
    );
    final listed = await listWebDav(
      directory: directory,
      user: user,
      password: password,
    );
    final known = {for (final item in listed) item.name: item};
    known.putIfAbsent(
      name,
      () => CloudObject(name: name, url: target.toString()),
    );
    final ordered = known.keys.toList()..sort();
    final overflow = known.length - clampCloudKeep(keep);
    if (overflow <= 0) return;
    final victims = ordered.where((item) => item != name).take(overflow);
    for (final victim in victims) {
      final url = known[victim]?.url;
      if (url == null) continue;
      await _send(() => _client.delete(Uri.parse(url), headers: headers), [
        user,
        password,
      ]);
    }
  }

  Future<List<CloudObject>> listWebDav({
    required Uri directory,
    required String user,
    required String password,
  }) async {
    final request = http.Request('PROPFIND', directory)
      ..headers.addAll({
        ..._webdavHeaders(user, password),
        'Depth': '1',
        'Content-Type': 'application/xml',
      })
      ..body =
          '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>';
    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request);
    } on http.ClientException {
      throw const CloudBackupException('网络没有连上');
    }
    final response = await http.Response.fromStream(streamed);
    _reject(response, [user, password]);
    final found = <CloudObject>[];
    for (final href in _webDavHrefs(response.body)) {
      final fileName = _fileName(href);
      if (fileName == null || !fileName.startsWith(backupFilePrefix)) continue;
      found.add(
        CloudObject(
          name: fileName,
          url: directory.resolve(href).toString(),
          createdAt: backupFileTime(fileName),
        ),
      );
    }
    found.sort((a, b) => b.name.compareTo(a.name));
    return found;
  }

  Future<String> download(
    CloudObject object, {
    String? token,
    String? user,
    String? password,
  }) async {
    if (object.content != null && object.content!.isNotEmpty) {
      return object.content!;
    }
    final url = object.url;
    if (url == null || url.isEmpty) {
      throw const CloudBackupException('云端没有这份备份的内容');
    }
    final headers = <String, String>{};
    final secrets = <String>[];
    if (token != null && token.isNotEmpty) {
      headers.addAll(_githubHeaders(token));
      secrets.add(token);
    }
    if (user != null && password != null) {
      headers.addAll(_webdavHeaders(user, password));
      secrets.addAll([user, password]);
    }
    final response = await _send(
      () => _client.get(Uri.parse(url), headers: headers),
      secrets,
    );
    return response.body;
  }

  List<String> _gistNames(String body) {
    final files = (jsonDecode(body) as Map)['files'];
    if (files is! Map) return const [];
    return [
      for (final key in files.keys)
        if (key is String && key.startsWith(backupFilePrefix)) key,
    ];
  }

  Map<String, String> _githubHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'korean-memo',
    'Content-Type': 'application/json',
  };

  Map<String, String> _webdavHeaders(String user, String password) => {
    'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
  };

  Future<http.Response> _send(
    Future<http.Response> Function() call,
    List<String> secrets,
  ) async {
    try {
      final response = await call();
      _reject(response, secrets);
      return response;
    } on CloudBackupException {
      rethrow;
    } on http.ClientException {
      throw const CloudBackupException('网络没有连上');
    }
  }

  void _reject(http.Response response, List<String> secrets) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw const CloudBackupException('云端拒绝了令牌或密码');
    }
    final snippet = redactSecrets(
      response.body,
      secrets,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final clipped = snippet.length > 160 ? snippet.substring(0, 160) : snippet;
    throw CloudBackupException(
      clipped.isEmpty ? '云端返回 $status' : '云端返回 $status：$clipped',
    );
  }
}

List<String> _webDavHrefs(String body) {
  try {
    final document = XmlDocument.parse(body);
    return [
      for (final node in document.descendants.whereType<XmlElement>())
        if (node.name.local.toLowerCase() == 'href') node.innerText.trim(),
    ];
  } on XmlException {
    throw const CloudBackupException('WebDAV 目录没有列出来');
  }
}

String? _fileName(String href) {
  final segments = Uri.parse(
    href,
  ).pathSegments.where((part) => part.isNotEmpty);
  if (segments.isEmpty) return null;
  return Uri.decodeComponent(segments.last);
}
