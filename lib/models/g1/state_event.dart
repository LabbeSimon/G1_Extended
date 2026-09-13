/// The events the glasses send without being asked.
///
/// Everything spontaneous arrives under command 0xF5 with a sub-code, and
/// this app has only ever named four of them: exit to dashboard, page
/// control, and the two halves of a touchpad hold. The rest reached a
/// `debugPrint` and stopped there — a head lifted, a pair taken off, the
/// case opened, the dashboard closed, all of it discarded.
///
/// The table below is the community's, cross-checked between openg1-sdk's
/// protocol specification and g1bridge. Naming an event is not the same as
/// acting on it: nothing here changes what the app does. It makes the
/// glasses' own reports readable, which is the step before deciding which
/// of them are worth a behaviour.
enum StateEvent {
  touchbarDoubleTap(0x00, 'Double tap'),
  touchbarSingleTap(0x01, 'Single tap'),
  headUp(0x02, 'Head up'),
  headDown(0x03, 'Head down'),
  touchbarTripleTap(0x04, 'Triple tap'),
  touchbarTripleTapAlt(0x05, 'Triple tap (alt)'),
  glassesWorn(0x06, 'Glasses worn'),
  glassesRemoved(0x07, 'Glasses removed'),
  caseLidOpen(0x08, 'Case opened'),
  chargingState(0x09, 'Charging state'),
  unknown0A(0x0A, 'Unknown 0x0A'),
  caseLidClosed(0x0B, 'Case closed'),
  caseCharging(0x0E, 'Case charging'),
  caseBattery(0x0F, 'Case battery'),
  blePaired(0x11, 'BLE paired'),
  unknown12(0x12, 'Unknown 0x12'),
  touchbarHoldStart(0x17, 'Hold start'),
  touchbarHoldEnd(0x18, 'Hold end'),
  dashboardOpened(0x1E, 'Dashboard opened'),
  dashboardClosed(0x1F, 'Dashboard closed'),
  translateTranscribeToggle(0x20, 'Translate/transcribe toggle');

  const StateEvent(this.id, this.label);

  final int id;
  final String label;

  /// The event a sub-code names, or null when nobody has named it yet.
  ///
  /// Null is a real answer here. The protocol is reverse-engineered, and an
  /// unnamed sub-code is something the firmware does that no one has
  /// accounted for — worth reporting, never worth guessing.
  static StateEvent? fromId(int id) {
    for (final event in StateEvent.values) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// How it reads in a log or a debug list.
  static String describe(int id) {
    final event = fromId(id);
    final hex = '0x${id.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    return event == null ? 'Unnamed $hex' : '${event.label} ($hex)';
  }
}
