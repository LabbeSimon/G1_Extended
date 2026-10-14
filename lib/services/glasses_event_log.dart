import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:g1_extended/models/g1/state_event.dart';

/// One spontaneous report from the glasses, as it arrived.
@immutable
class GlassesEvent {
  GlassesEvent({
    required this.side,
    required this.subcommand,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// 'left' or 'right', as the receiver knows it.
  final String side;

  /// The 0xF5 sub-code.
  final int subcommand;

  final DateTime at;

  StateEvent? get event => StateEvent.fromId(subcommand);

  /// True when nothing in the table accounts for this one.
  bool get isUnnamed => event == null;

  String get label => StateEvent.describe(subcommand);

  @override
  String toString() => '[$side] $label';
}

/// The last events the glasses sent, kept so they can be looked at.
///
/// The receiver acts on four sub-codes and printed the rest into a debug
/// console nobody reads on a phone. Keeping a short history in memory costs
/// nothing and turns "the glasses did something and the app ignored it" into
/// a line you can point at — which is how the unnamed sub-codes will get
/// names.
class GlassesEventLog {
  GlassesEventLog._();

  static final GlassesEventLog instance = GlassesEventLog._();

  /// Long enough to cover a walk to the kitchen and back, short enough that
  /// a chatty firmware cannot eat memory.
  static const int depth = 50;

  final List<GlassesEvent> _events = <GlassesEvent>[];
  final _changes = StreamController<List<GlassesEvent>>.broadcast();

  /// Most recent first.
  List<GlassesEvent> get events => List.unmodifiable(_events);

  Stream<List<GlassesEvent>> get changes => _changes.stream;

  void record(String side, int subcommand) {
    _events.insert(0, GlassesEvent(side: side, subcommand: subcommand));
    if (_events.length > depth) _events.removeRange(depth, _events.length);
    if (!_changes.isClosed) _changes.add(events);
  }

  void clear() {
    _events.clear();
    if (!_changes.isClosed) _changes.add(events);
  }
}
