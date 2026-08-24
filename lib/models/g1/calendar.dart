import 'dart:convert';
import 'dart:typed_data';

class CalendarItem {
  String name;
  String time;
  String location;

  CalendarItem({
    required this.name,
    required this.time,
    required this.location,
  });

  Uint8List constructDashboardCalendarItem() {
    List<int> bytes = [
      0x00, // Fixed byte
      0x6d, // Fixed byte
      0x03, // Fixed byte
      0x01, // Fixed byte
      0x00, // Fixed byte
      0x01, // Fixed byte
      0x00, // Fixed byte
      0x00, // Fixed byte
      0x00, // Fixed byte
      0x03, // Fixed byte
      0x01, // Fixed byte
    ];

    // Length is the *byte* count, not the character count: a "Réunion" is
    // 7 characters but 8 UTF-8 bytes, and mixing the two lets the firmware
    // read one byte short and take the next field's tag byte as part of
    // the name — every field after that shifts and the event turns to
    // garbage. Encoding once, up front, keeps the two in sync.
    final nameBytes = utf8.encode(name);
    final timeBytes = utf8.encode(time);
    final locationBytes = utf8.encode(location);

    bytes.add(0x01); // name of the event
    bytes.add(nameBytes.length);
    bytes.addAll(nameBytes);
    bytes.add(0x02); // time of event
    bytes.add(timeBytes.length);
    bytes.addAll(timeBytes);
    bytes.add(0x03); // location of event
    bytes.add(locationBytes.length);
    bytes.addAll(locationBytes);

    final length = bytes.length + 2;
    List<int> header = [0x06, length];
    return Uint8List.fromList(header + bytes);
  }
}
