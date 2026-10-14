import '../../core/clock.dart';
import '../../core/domain_events.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../models/activity.dart';
import '../../models/money.dart';
import '../../models/partner.dart';
import '../repositories/wallet_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoWalletRepository implements WalletRepository {
  DemoWalletRepository(this._backend);

  final DemoBackend _backend;

  int get _withdrawablePaise => _backend.withdrawablePaise;

  DateTime get _nextMonday {
    final now = _backend.clock.now();
    final today = startOfDay(now);
    var monday = DateTime(
      today.year,
      today.month,
      today.day + (DateTime.monday - today.weekday + 7) % 7,
      6,
    );
    if (!monday.isAfter(now)) monday = monday.add(const Duration(days: 7));
    return monday;
  }

  @override
  Future<WalletBalance> balance() =>
      _backend.engine.run(OperationType.loadWallet, () {
        _backend.settlePayouts();
        return WalletBalance(
          withdrawablePaise: _withdrawablePaise,
          pendingPaise: _backend.db.payouts
              .where((p) => p.status.isInFlight)
              .fold(0, (sum, p) => sum + p.amountPaise),
          nextScheduledPayoutOn: _nextMonday,
        );
      });

  @override
  Future<List<Payout>> payouts() =>
      _backend.engine.run(OperationType.loadWallet, () {
        _backend.settlePayouts();
        return List.unmodifiable(_backend.db.payouts);
      });

  @override
  Future<Payout> requestInstantPayout(int amountPaise) =>
      _backend.engine.run(OperationType.withdraw, () {
        _backend.settleReviews();
        final db = _backend.db;
        final bank = db.partner.bank;
        if (bank == null) {
          throw const NotAllowedFailure('Add your bank account to withdraw.');
        }
        if (bank.verification != BankVerification.verified) {
          throw const NotAllowedFailure(
            'Your bank account is still being verified.',
          );
        }
        final now = _backend.clock.now();
        final today = startOfDay(now);
        final error = Validators.withdrawAmount(
          amountPaise: amountPaise,
          availablePaise: _withdrawablePaise,
          alreadyWithdrewToday: db.payouts.any(
            (p) =>
                p.isInstant &&
                p.status != PayoutStatus.failed &&
                !p.requestedAt.isBefore(today),
          ),
        );
        if (error != null) throw ValidationFailure(error, field: 'amount');

        final payout = Payout(
          id: _backend.ids.next('pay'),
          amountPaise: amountPaise,
          requestedAt: now,
          status: PayoutStatus.requested,
          reference: _backend.ids.reference('TXN'),
          isInstant: true,
        );
        _backend.startPayout(payout);
        _backend.recordActivity(ActivityType.payoutRequested, payout.reference);
        _backend.events.emit(const WalletChanged());
        return payout;
      });

  @override
  Future<CashInHand> cashInHand() =>
      _backend.engine.run(OperationType.loadWallet, () => _backend.db.cash);

  @override
  Future<CashDeposit> depositCash(int amountPaise, DepositMethod method) =>
      _backend.engine.run(OperationType.depositCash, () {
        final db = _backend.db;
        final error = Validators.cashDeposit(
          amountPaise: amountPaise,
          cashInHandPaise: db.cash.balancePaise,
        );
        if (error != null) throw ValidationFailure(error, field: 'amount');

        final now = _backend.clock.now();
        final deposit = CashDeposit(
          id: _backend.ids.next('dep'),
          amountPaise: amountPaise,
          at: now,
          method: method,
          reference: _backend.ids.reference('DEP'),
        );
        db.cash = db.cash.copyWith(
          movements: [
            ...db.cash.movements,
            CashMovement(
              type: CashMovementType.deposit,
              amountPaise: amountPaise,
              at: now,
            ),
          ],
          deposits: [...db.cash.deposits, deposit],
        );
        _backend.recordActivity(
          ActivityType.cashDeposited,
          '${formatPaise(amountPaise)} · ${deposit.reference}',
        );
        _backend.events.emit(const WalletChanged());
        return deposit;
      });
}
