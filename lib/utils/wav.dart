import 'dart:typed_data';

/// Wraps raw PCM in a RIFF/WAVE container.
///
/// The glasses hand us headerless 16-bit little-endian mono samples once
/// LC3 has been decoded. Every player on the phone — and every human with a
/// file manager — expects a header, so this is the difference between a
/// recording someone can listen to and forty kilobytes of unopenable bytes.
///
/// Deliberately hand-rolled rather than pulled from a package: the header is
/// 44 fixed bytes and the app is meant to stay offline with few dependencies.
class Wav {
  /// The glasses microphone, after LC3 decoding.
  static const int defaultSampleRate = 16000;

  const Wav._();

  /// Prepends a canonical 44-byte header to [pcm].
  ///
  /// [pcm] must be 16-bit little-endian samples. An odd length would mean a
  /// half sample — the trailing byte is dropped rather than shifting every
  /// sample after it into noise.
  static Uint8List fromPcm16(
    Uint8List pcm, {
    int sampleRate = defaultSampleRate,
    int channels = 1,
  }) {
    const int bitsPerSample = 16;
    final int bytesPerFrame = channels * bitsPerSample ~/ 8;

    final Uint8List samples =
        pcm.length % bytesPerFrame == 0
            ? pcm
            : Uint8List.sublistView(
                pcm, 0, pcm.length - (pcm.length % bytesPerFrame));

    final int dataLength = samples.length;
    final out = Uint8List(44 + dataLength);
    final view = ByteData.sublistView(out);

    void ascii(int offset, String tag) {
      for (var i = 0; i < tag.length; i++) {
        out[offset + i] = tag.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    // Everything after this field: 44-byte header minus the 8 already read.
    view.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');

    ascii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // PCM subchunk size
    view.setUint16(20, 1, Endian.little); // format 1 = uncompressed PCM
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * bytesPerFrame, Endian.little); // byte rate
    view.setUint16(32, bytesPerFrame, Endian.little); // block align
    view.setUint16(34, bitsPerSample, Endian.little);

    ascii(36, 'data');
    view.setUint32(40, dataLength, Endian.little);

    out.setRange(44, 44 + dataLength, samples);
    return out;
  }

  /// How long [pcmByteLength] bytes of 16-bit mono audio lasts.
  static Duration durationOfPcm16(
    int pcmByteLength, {
    int sampleRate = defaultSampleRate,
    int channels = 1,
  }) {
    final int bytesPerSecond = sampleRate * channels * 2;
    if (bytesPerSecond <= 0) return Duration.zero;
    return Duration(
      milliseconds: (pcmByteLength * 1000 / bytesPerSecond).round(),
    );
  }
}
