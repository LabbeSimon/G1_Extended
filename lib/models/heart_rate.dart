/// The Bluetooth Heart Rate Measurement, parsed (characteristic 0x2A37).
///
/// This is the standard every chest strap and every watch in broadcast mode
/// speaks — one format, no vendor apps, no cloud. The first byte is a flag
/// field that decides the shape of everything after it, which is exactly
/// the kind of parsing that is always almost right: the rate is eight bits
/// or sixteen depending on bit zero, and optional fields stack after it in
/// a fixed order. Each shape is pinned by a test.
class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    this.contactDetected,
    this.energyKilojoules,
    this.rrIntervals = const [],
  });

  final int bpm;

  /// Null when the sensor does not report contact at all; true or false
  /// when it does. A strap that has slipped says false — worth showing,
  /// because a frozen number and a lost contact look identical otherwise.
  final bool? contactDetected;

  final int? energyKilojoules;

  /// Beat-to-beat intervals in seconds, when the sensor sends them.
  final List<double> rrIntervals;

  /// Parses one notification, or returns null for a frame too short to
  /// carry what its own flags promise — a truncated frame misread as a
  /// heart rate would put a wrong number on someone's lens mid-effort.
  static HeartRateMeasurement? parse(List<int> data) {
    if (data.length < 2) return null;

    final flags = data[0];
    final sixteenBit = flags & 0x01 != 0;
    final contactSupported = flags & 0x04 != 0;
    final contactDetected = flags & 0x02 != 0;
    final hasEnergy = flags & 0x08 != 0;
    final hasRr = flags & 0x10 != 0;

    var offset = 1;

    final int bpm;
    if (sixteenBit) {
      if (data.length < offset + 2) return null;
      bpm = data[offset] | (data[offset + 1] << 8);
      offset += 2;
    } else {
      bpm = data[offset];
      offset += 1;
    }

    int? energy;
    if (hasEnergy) {
      if (data.length < offset + 2) return null;
      energy = data[offset] | (data[offset + 1] << 8);
      offset += 2;
    }

    final rr = <double>[];
    if (hasRr) {
      while (offset + 1 < data.length) {
        final raw = data[offset] | (data[offset + 1] << 8);
        // The spec's unit is 1/1024 of a second.
        rr.add(raw / 1024);
        offset += 2;
      }
    }

    return HeartRateMeasurement(
      bpm: bpm,
      contactDetected: contactSupported ? contactDetected : null,
      energyKilojoules: energy,
      rrIntervals: rr,
    );
  }
}
