import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/utils/wav.dart';

/// The header is the difference between a recording someone can play and
/// forty kilobytes nothing will open. These pin every field a player reads.
void main() {
  Uint8List pcm(int samples) {
    final out = Uint8List(samples * 2);
    final view = ByteData.sublistView(out);
    for (var i = 0; i < samples; i++) {
      view.setInt16(i * 2, (i % 1000) - 500, Endian.little);
    }
    return out;
  }

  String tagAt(Uint8List wav, int offset) =>
      String.fromCharCodes(wav.sublist(offset, offset + 4));

  group('Wrapping PCM as WAV', () {
    test('writes the four chunk tags a player looks for', () {
      final wav = Wav.fromPcm16(pcm(100));
      expect(tagAt(wav, 0), 'RIFF');
      expect(tagAt(wav, 8), 'WAVE');
      expect(tagAt(wav, 12), 'fmt ');
      expect(tagAt(wav, 36), 'data');
    });

    test('describes the glasses format: 16 kHz, mono, 16-bit PCM', () {
      final wav = Wav.fromPcm16(pcm(100));
      final view = ByteData.sublistView(wav);
      expect(view.getUint16(20, Endian.little), 1, reason: 'uncompressed PCM');
      expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint16(34, Endian.little), 16, reason: '16-bit samples');
      expect(view.getUint32(28, Endian.little), 32000, reason: 'byte rate');
      expect(view.getUint16(32, Endian.little), 2, reason: 'block align');
    });

    test('the declared sizes match the bytes actually present', () {
      final samples = pcm(500);
      final wav = Wav.fromPcm16(samples);
      final view = ByteData.sublistView(wav);

      expect(wav.length, 44 + samples.length);
      expect(view.getUint32(4, Endian.little), 36 + samples.length);
      expect(view.getUint32(40, Endian.little), samples.length);
    });

    test('the samples survive the wrapping byte for byte', () {
      final samples = pcm(300);
      final wav = Wav.fromPcm16(samples);
      expect(wav.sublist(44), samples);
    });

    test('an odd trailing byte is dropped, not left to shift every sample', () {
      final odd = Uint8List.fromList([...pcm(10), 0x7f]);
      final wav = Wav.fromPcm16(odd);
      final view = ByteData.sublistView(wav);
      expect(view.getUint32(40, Endian.little), 20);
      expect(wav.length, 64);
    });

    test('an empty buffer still produces a valid, empty file', () {
      final wav = Wav.fromPcm16(Uint8List(0));
      expect(wav.length, 44);
      expect(tagAt(wav, 0), 'RIFF');
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 0);
    });

    test('a non-default sample rate reaches both fields that carry it', () {
      final wav = Wav.fromPcm16(pcm(10), sampleRate: 8000);
      final view = ByteData.sublistView(wav);
      expect(view.getUint32(24, Endian.little), 8000);
      expect(view.getUint32(28, Endian.little), 16000);
    });
  });

  group('Duration', () {
    test('one second of 16 kHz mono is 32000 bytes', () {
      expect(Wav.durationOfPcm16(32000), const Duration(seconds: 1));
    });

    test('reads back the length of what was wrapped', () {
      final samples = pcm(16000);
      expect(Wav.durationOfPcm16(samples.length), const Duration(seconds: 1));
    });

    test('nothing lasts no time, rather than throwing', () {
      expect(Wav.durationOfPcm16(0), Duration.zero);
    });
  });
}
