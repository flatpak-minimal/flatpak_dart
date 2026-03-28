@TestOn('vm')
library update_monitor_test;

import 'dart:async';

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  group('UpdateAvailableEvent', () {
    test('can be constructed as const', () {
      const event = UpdateAvailableEvent();
      expect(event, isA<UpdateAvailableEvent>());
    });
  });

  group('UpdateMonitor', () {
    test('can be constructed with stream and close callback', () async {
      final controller = StreamController<UpdateAvailableEvent>.broadcast();
      var closed = false;

      final monitor = UpdateMonitor(
        events: controller.stream,
        close: () async {
          closed = true;
          controller.close();
        },
      );

      expect(monitor.events, isA<Stream<UpdateAvailableEvent>>());

      await monitor.close();
      expect(closed, isTrue);
    });

    test('events stream receives events', () async {
      final controller = StreamController<UpdateAvailableEvent>.broadcast();

      final monitor = UpdateMonitor(
        events: controller.stream,
        close: () async => controller.close(),
      );

      final events = <UpdateAvailableEvent>[];
      final sub = monitor.events.listen(events.add);

      controller.add(const UpdateAvailableEvent());
      controller.add(const UpdateAvailableEvent());

      // Let events propagate
      await Future.delayed(Duration.zero);

      expect(events.length, 2);

      await sub.cancel();
      await monitor.close();
    });

    test('close is idempotent', () async {
      final controller = StreamController<UpdateAvailableEvent>.broadcast();
      var closeCount = 0;

      final monitor = UpdateMonitor(
        events: controller.stream,
        close: () async {
          closeCount++;
          if (!controller.isClosed) controller.close();
        },
      );

      await monitor.close();
      await monitor.close();
      expect(closeCount, 2); // close callback called each time
    });
  });
}
