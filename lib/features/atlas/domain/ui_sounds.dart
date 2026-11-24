import 'dart:typed_data';

enum UiSoundKind { correct, wrong, flip }

bool shouldPlayUiSound({required bool enabled, required bool reduceMotion}) =>
    enabled && !reduceMotion;

Uint8List synthTone({
  required double frequency,
  int milliseconds = 90,
  double volume = 0.18,
}) {
  const sampleRate = 8000;
  final count = (sampleRate * milliseconds / 1000).round();
  final data = BytesBuilder();
  for (var i = 0; i < count; i++) {
    final envelope = i < 80 ? i / 80 : (1 - (i / count)).clamp(0, 1);
    final sample = (volume * envelope * _sine(frequency, i, sampleRate) * 32767)
        .round()
        .clamp(-32767, 32767);
    data.addByte(sample & 0xff);
    data.addByte((sample >> 8) & 0xff);
  }
  return _wav(data.toBytes(), sampleRate);
}

Uint8List uiSoundWav(UiSoundKind kind) => switch (kind) {
  UiSoundKind.correct => _join([
    synthTone(frequency: 660, milliseconds: 70),
    synthTone(frequency: 880, milliseconds: 90),
  ]),
  UiSoundKind.wrong => synthTone(
    frequency: 196,
    milliseconds: 160,
    volume: 0.16,
  ),
  UiSoundKind.flip => synthTone(frequency: 520, milliseconds: 40, volume: 0.1),
};

double _sine(double frequency, int index, int sampleRate) {
  final cycle = (frequency * index / sampleRate) % 1;
  final angle = cycle * 6.283185307179586;
  var value = angle;
  var term = angle;
  for (var n = 1; n <= 6; n++) {
    term *= -angle * angle / ((2 * n) * (2 * n + 1));
    value += term;
  }
  return value.clamp(-1, 1);
}

Uint8List _join(List<Uint8List> clips) {
  final pcm = BytesBuilder();
  for (final clip in clips) {
    pcm.add(clip.sublist(44));
  }
  return _wav(pcm.toBytes(), 8000);
}

Uint8List _wav(Uint8List pcm, int sampleRate) {
  final bytes = BytesBuilder();
  void ascii(String value) => bytes.add(value.codeUnits);
  void u32(int value) {
    bytes.addByte(value & 0xff);
    bytes.addByte((value >> 8) & 0xff);
    bytes.addByte((value >> 16) & 0xff);
    bytes.addByte((value >> 24) & 0xff);
  }

  void u16(int value) {
    bytes.addByte(value & 0xff);
    bytes.addByte((value >> 8) & 0xff);
  }

  ascii('RIFF');
  u32(36 + pcm.length);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  ascii('data');
  u32(pcm.length);
  bytes.add(pcm);
  return bytes.toBytes();
}
