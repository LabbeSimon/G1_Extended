import 'package:flutter/foundation.dart';

/// Where a case battery reading came from.
///
/// This matters enough to carry around. One source is documented and
/// unambiguous; the other is a byte we believe is the case level but have not
/// proven. Mixing them silently would mean never knowing which one the number
/// on screen actually came from.
enum CaseBatterySource {
  /// Spontaneous state change, `F5 0F <percentage>`. Authoritative.
  stateChange,

  /// A byte inside the polled battery reply that is *probably* the case
  /// level. Believed, not established.
  polledCandidate,
}

@immutable
class CaseBattery {
  final int percentage;
  final CaseBatterySource source;
  final DateTime at;

  const CaseBattery({
    required this.percentage,
    required this.source,
    required this.at,
  });

  bool get isConfirmed => source == CaseBatterySource.stateChange;

  @override
  String toString() => '$percentage% (${source.name})';
}

/// Reads the charging case's level out of the two frames that carry it.
abstract final class CaseBatteryParser {
  /// Spontaneous state changes arrive under the 0xF5 command.
  static const int stateChangeCommand = 0xF5;

  /// The subcommand that carries the case level.
  static const int caseBatterySubcommand = 0x0F;

  /// Polled battery replies start with this.
  static const int polledCommand = 0x2C;

  /// The byte in a polled reply suspected of holding the case level.
  ///
  /// Index 2 is the glasses' own percentage, confirmed against a report where
  /// both temples read 100. Index 3 held 100 as well in that capture, with
  /// the glasses out of a case that was plugged in — consistent with a full
  /// case, and equally consistent with a duplicate. Hence "suspected".
  static const int polledCaseIndex = 3;

  /// Percentages are 0x00 to 0x64 in this protocol.
  static const int maxPercentage = 0x64;

  /// Reads `F5 0F <percentage>`.
  static CaseBattery? fromStateChange(List<int> data, {DateTime? at}) {
    if (data.length < 3) return null;
    if (data[0] != stateChangeCommand) return null;
    if (data[1] != caseBatterySubcommand) return null;

    final value = data[2];
    // A byte outside the documented range is not a percentage, and treating
    // it as one would put a plausible-looking wrong number on screen.
    if (value > maxPercentage) return null;

    return CaseBattery(
      percentage: value,
      source: CaseBatterySource.stateChange,
      at: at ?? DateTime.now(),
    );
  }

  /// Reads the suspected case byte out of a polled `2C 66 ...` reply.
  ///
  /// Returns null rather than a guess whenever the byte cannot be a
  /// percentage, which is most of the time if the hypothesis is wrong.
  static CaseBattery? fromPolledReply(List<int> data, {DateTime? at}) {
    if (data.length <= polledCaseIndex) return null;
    if (data[0] != polledCommand) return null;

    final value = data[polledCaseIndex];
    if (value > maxPercentage) return null;

    return CaseBattery(
      percentage: value,
      source: CaseBatterySource.polledCandidate,
      at: at ?? DateTime.now(),
    );
  }
}
