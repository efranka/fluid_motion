import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_motion/fluid_motion.dart';

void main() {
  group('EnergySpring', () {
    const spring = EnergySpring(stiffness: 420);

    test('slow speed gives no bounce, fast speed gives bounce', () {
      expect(spring.forSpeed(0).damping, closeTo(spring.calm.damping, 1e-9));
      final calm = spring.forSpeed(100);
      final wild = spring.forSpeed(5000);
      // Damping = ratio * 2 * sqrt(k*m)
      expect(calm.damping, closeTo(2 * 1.0 * 20.4939, 0.01));
      expect(wild.damping, closeTo(2 * 0.35 * 20.4939, 0.01));
    });

    test('energy is graded and monotonic', () {
      var last = -1.0;
      for (var v = 0.0; v <= 3000; v += 100) {
        final e = spring.energy(v);
        expect(e, inInclusiveRange(0.0, 1.0));
        expect(e, greaterThanOrEqualTo(last));
        last = e;
      }
      expect(spring.energy(-3000), spring.energy(3000));
    });

    test('ratioOffset calms the spring, but never above 1', () {
      final base = spring.forSpeed(2500);
      final offset = spring.forSpeed(2500, ratioOffset: 0.15);
      expect(offset.damping, greaterThan(base.damping));
      expect(
        spring.forSpeed(0, ratioOffset: 0.5).damping,
        closeTo(spring.calm.damping, 1e-9),
      );
    });
  });

  group('rubberBand', () {
    test('is 0 without overshoot and approaches the dimension', () {
      expect(rubberBand(0, 10), 0);
      expect(rubberBand(-5, 10), 0);
      expect(rubberBand(10, 10), lessThan(10));
      expect(rubberBand(100000, 10), closeTo(10, 0.01));
      expect(rubberBand(20, 10), greaterThan(rubberBand(10, 10)));
    });
  });

  group('Ramp', () {
    test('clamps outside the interval and can run backwards', () {
      expect(const Ramp(0, 0.5).transform(-1), 0);
      expect(const Ramp(0, 0.5).transform(0.25), 0.5);
      expect(const Ramp(0, 0.5).transform(2), 1);
      expect(const Ramp(0.5, 0).transform(0), 1);
    });
  });
}
