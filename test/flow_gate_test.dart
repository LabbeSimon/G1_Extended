import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/utils/flow_gate.dart';

/// The manager's connection flows — reconnect-from-storage (five triggers),
/// scan-and-connect, user disconnect — all reach the same two Glass fields.
/// The gate makes them take turns; without it, one flow's opening
/// disconnect was another flow's temple dying mid-setup.
void main() {
  test('exclusive flows run one at a time, in order', () async {
    final gate = FlowGate();
    final events = <String>[];
    var running = 0;
    var maxRunning = 0;

    Future<void> flow(String name) async {
      running++;
      if (running > maxRunning) maxRunning = running;
      events.add('$name starts');
      await Future.delayed(Duration.zero);
      events.add('$name ends');
      running--;
    }

    await Future.wait([
      gate.exclusive(() => flow('reconnect')),
      gate.exclusive(() => flow('scan')),
      gate.exclusive(() => flow('disconnect')),
    ]);

    expect(maxRunning, 1, reason: 'two flows overlapped');
    expect(events, [
      'reconnect starts',
      'reconnect ends',
      'scan starts',
      'scan ends',
      'disconnect starts',
      'disconnect ends',
    ]);
  });

  test('simultaneous reconnect triggers coalesce into one run', () async {
    final gate = FlowGate();
    var runs = 0;

    Future<void> reconnect() async {
      runs++;
      await Future.delayed(Duration.zero);
    }

    // Startup, crash dialog, background service, widget — all at once.
    await Future.wait([
      gate.coalesced(reconnect),
      gate.coalesced(reconnect),
      gate.coalesced(reconnect),
      gate.coalesced(reconnect),
    ]);

    expect(runs, 1, reason: 'coalesced triggers each ran their own flow');

    // Once settled, a new trigger runs again.
    await gate.coalesced(reconnect);
    expect(runs, 2);
  });

  test('a failing flow does not block the queue', () async {
    final gate = FlowGate();

    await expectLater(
      gate.exclusive(() async => throw StateError('mid-setup drop')),
      throwsStateError,
    );

    var ran = false;
    await gate.exclusive(() async => ran = true);
    expect(ran, isTrue, reason: 'the queue stalled after a failed flow');
  });

  test('a failing coalesced flow clears, letting the next trigger run',
      () async {
    final gate = FlowGate();
    var attempts = 0;

    Future<void> failing() async {
      attempts++;
      throw StateError('temple absent');
    }

    await expectLater(gate.coalesced(failing), throwsStateError);
    await expectLater(gate.coalesced(failing), throwsStateError);
    expect(attempts, 2,
        reason: 'a failed coalesced flow kept swallowing later triggers');
  });

  test('exclusive flows queued behind a coalesced one still wait', () async {
    final gate = FlowGate();
    final events = <String>[];

    final reconnect = gate.coalesced(() async {
      events.add('reconnect starts');
      await Future.delayed(Duration.zero);
      events.add('reconnect ends');
    });
    final disconnect = gate.exclusive(() async {
      events.add('disconnect');
    });

    await Future.wait([reconnect, disconnect]);
    expect(events, ['reconnect starts', 'reconnect ends', 'disconnect']);
  });

  test('isBusy reflects running and queued flows', () async {
    final gate = FlowGate();
    expect(gate.isBusy, isFalse);

    final flow = gate.exclusive(() => Future.delayed(Duration.zero));
    expect(gate.isBusy, isTrue);

    await flow;
    expect(gate.isBusy, isFalse);
  });
}
