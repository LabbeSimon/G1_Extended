import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/battery.dart';
import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/setup.dart';
import 'package:g1_extended/services/time_sync.dart';

/// Frames this app already sent, re-checked against the official Even app
/// 1.6.5 (docs/protocol).
void main() {
  test('the allowlist uses the official, lower-case keys', () {
    final setup = G1Setup(
      calendarEnable: true,
      callEnable: true,
      msgEnable: false,
      iosMailEnable: false,
      app: App(list: [AppItem(id: 'org.example', name: 'Example')], enable: true),
    );

    expect(
      jsonEncode(setup.toJson()),
      '{"calendar_enable":true,"call_enable":true,"msg_enable":false,'
      '"ios_mail_enable":false,"app":{"list":[{"id":"org.example",'
      '"name":"Example"}],"enable":true}}',
    );
  });

  test('battery voltage is byte 4, as (volts * 100) - 200', () {
    final info = G1BatteryInfo.fromResponse(
      [0x2C, 0x66, 0x64, 0x64, 0xEF, 0x80, 0x19],
      GlassSide.right,
    );
    expect(info?.percentage, 100);
    expect(info?.voltage, 4390, reason: 'millivolts');
  });

  test('the date format follows the official country table', () {
    expect(TimeSync.dateFormatFor('US'), 0);
    expect(TimeSync.dateFormatFor('se'), 1);
    expect(TimeSync.dateFormatFor('FR'), 2);
    expect(TimeSync.dateFormatFor(null), 2);
  });
}
