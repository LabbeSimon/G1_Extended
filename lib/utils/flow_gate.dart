import 'dart:async';

/// Serializes the connection flows of the Bluetooth manager.
///
/// Reconnect-from-storage, scan-and-connect and user disconnect used to run
/// freely against each other: the startup reconnect, the crash dialog's
/// Reconnect button, the background service's connection monitor, the home
/// widget's reconnect command and the interface's Connect button all reach
/// the same two Glass fields, and each begins by tearing down whatever the
/// others have half-built. The visible symptom was a temple dying mid-setup
/// with "device is disconnected" the moment another flow ran
/// disconnectFromGlasses.
class FlowGate {
  Future<void> _tail = Future<void>.value();
  Future<void>? _coalesced;

  /// Whether a flow is currently running or queued.
  bool get isBusy => _busy > 0;
  int _busy = 0;

  /// Runs [body] once every previously enqueued flow has finished.
  ///
  /// Errors from [body] reach this call's future only; the queue itself
  /// carries on.
  Future<T> exclusive<T>(Future<T> Function() body) {
    _busy++;
    final run = _tail.then((_) => body()).whenComplete(() => _busy--);
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Like [exclusive], but a caller arriving while a coalesced flow is
  /// already pending joins that flow instead of enqueueing another.
  ///
  /// This is the shape a reconnect wants: five triggers firing in the same
  /// second mean "please be connected", not "reconnect five times" — and a
  /// queued duplicate would begin by tearing down the connection the first
  /// one just made.
  Future<void> coalesced(Future<void> Function() body) {
    return _coalesced ??=
        exclusive(body).whenComplete(() => _coalesced = null);
  }
}
