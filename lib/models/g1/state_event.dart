/// The events the glasses send without being asked.
///
/// Everything spontaneous arrives under command 0xF5 with a sub-code, and
/// this app has only ever named four of them: exit to dashboard, page
/// control, and the two halves of a touchpad hold. The rest reached a
/// `debugPrint` and stopped there — a head lifted, a pair taken off, the
/// case opened, the dashboard closed, all of it discarded.
///
/// The table below is the official app's (1.6.5, see
/// docs/protocol/transport.md), which supersedes the community's. Naming an event is not the same as
/// acting on it: nothing here changes what the app does. It makes the
/// glasses' own reports readable, which is the step before deciding which
/// of them are worth a behaviour.
enum StateEvent {
  touchbarDoubleTap(0x00, 'Double tap'),
  touchbarSingleTap(0x01, 'Single tap'),
  headUp(0x02, 'Head up'),
  headDown(0x03, 'Head down'),
  silentModeOn(0x04, 'Silent mode on'),
  silentModeOff(0x05, 'Silent mode off'),
  glassesWorn(0x06, 'Glasses worn'),
  glassesRemoved(0x07, 'Glasses removed'),
  inCaseLidOpen(0x08, 'In the case, lid open'),
  chargingState(0x09, 'Charging state'),
  glassesBattery(0x0A, 'Glasses battery'),
  inCaseLidClosed(0x0B, 'In the case, lid closed'),
  caseCharging(0x0E, 'Case charging'),
  caseBattery(0x0F, 'Case battery'),
  headUpEnded(0x10, 'Head-up display ended'),
  blePaired(0x11, 'BLE paired'),
  unknown12(0x12, 'Unknown 0x12'),
  onboardingDashboardStart(0x13, 'Onboarding: dashboard begins'),
  onboardingDashboardEnd(0x14, 'Onboarding: dashboard ends'),
  onboardingNotificationStart(0x15, 'Onboarding: notification begins'),
  onboardingNotificationEnd(0x16, 'Onboarding: notification ends'),
  touchbarHoldStart(0x17, 'Hold start'),
  touchbarHoldEnd(0x18, 'Hold end'),
  touchbarDoubleTapContinue(0x19, 'Double tap to continue'),
  dashboardOpened(0x1E, 'Dashboard opened'),
  dashboardClosed(0x1F, 'Dashboard closed'),
  doubleTapShortcut(0x20, 'Double tap shortcut');

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
