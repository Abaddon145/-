import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class AtlasAudioPlayer {
  AudioPlayer? _player;

  Future<bool> play(Uint8List bytes) async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(BytesSource(bytes));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await _player?.dispose();
  }
}
