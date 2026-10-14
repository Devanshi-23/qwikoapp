import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/core/formatters.dart';
import 'package:qwiko_delivery_agent/core/validators.dart';

void main() {
  group('formatters', () {
    test('formats paise as rupees with Indian grouping', () {
      expect(formatPaise(0), '₹0');
      expect(formatPaise(4550), '₹46');
      expect(formatPaise(12345600), '₹1,23,456');
      expect(formatPaise(-25000), '-₹250');
    });

    test('formats distance and duration', () {
      expect(formatDistance(850), '850 m');
      expect(formatDistance(3240), '3.2 km');
      expect(formatDuration(const Duration(hours: 2, minutes: 5)), '2h 5m');
    });

    test('labels recent dates relative to now', () {
      final now = DateTime(2026, 10, 13, 12);
      expect(formatDate(DateTime(2026, 10, 13, 9), now: now), 'Today');
      expect(formatDate(DateTime(2026, 10, 12, 23), now: now), 'Yesterday');
      expect(formatDate(DateTime(2026, 10, 1), now: now), '1 Oct 2026');
    });
  });

  group('validators', () {
    test('mobile numbers', () {
      expect(Validators.mobile('9876543210'), isNull);
      expect(Validators.mobile('12345'), isNotNull);
      expect(Validators.mobile(''), isNotNull);
    });

    test('passwords need 8 characters', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('long enough'), isNull);
    });

    test('IFSC codes', () {
      expect(Validators.ifsc('HDFC0001234'), isNull);
      expect(Validators.ifsc('hdfc0001234'), isNull);
      expect(Validators.ifsc('HDFC1001234'), isNotNull);
    });

    test('withdrawal amount rules', () {
      expect(
        Validators.withdrawAmount(
          amountPaise: 50000,
          availablePaise: 100000,
          alreadyWithdrewToday: false,
        ),
        isNull,
      );
      expect(
        Validators.withdrawAmount(
          amountPaise: 5000,
          availablePaise: 100000,
          alreadyWithdrewToday: false,
        ),
        isNotNull,
        reason: 'below the ₹100 minimum',
      );
      expect(
        Validators.withdrawAmount(
          amountPaise: 150000,
          availablePaise: 100000,
          alreadyWithdrewToday: false,
        ),
        isNotNull,
        reason: 'more than available',
      );
      expect(
        Validators.withdrawAmount(
          amountPaise: 50000,
          availablePaise: 100000,
          alreadyWithdrewToday: true,
        ),
        isNotNull,
        reason: 'one instant payout per day',
      );
    });
  });
}
