import '../core/clock.dart';
import '../core/domain_events.dart';
import '../data/repositories/wallet_repository.dart';
import '../models/money.dart';
import 'loadable_controller.dart';

class WalletController extends LoadableController {
  WalletController({
    required this._repository,
    required this._clock,
    super.events,
  });

  final WalletRepository _repository;
  final Clock _clock;

  WalletBalance? _balance;
  List<Payout> _payouts = const [];
  CashInHand _cash = const CashInHand();
  bool _withdrawing = false;
  bool _depositing = false;

  WalletBalance? get balance => _balance;

  /// Newest first.
  List<Payout> get payouts => _payouts;

  CashInHand get cash => _cash;

  bool get isWithdrawing => _withdrawing;

  bool get alreadyWithdrewToday {
    final today = startOfDay(_clock.now());
    return _payouts.any(
      (p) =>
          p.isInstant &&
          p.status != PayoutStatus.failed &&
          !p.requestedAt.isBefore(today),
    );
  }

  @override
  Future<void> fetch() async {
    final results = await Future.wait<Object>([
      _repository.balance(),
      _repository.payouts(),
      _repository.cashInHand(),
    ]);
    _balance = results[0] as WalletBalance;
    _payouts = results[1] as List<Payout>;
    _cash = results[2] as CashInHand;
  }

  @override
  void clearData() {
    _balance = null;
    _payouts = const [];
    _cash = const CashInHand();
  }

  @override
  bool shouldRefresh(DomainEvent event) =>
      event is WalletChanged || event is LedgerChanged;

  Future<Payout> withdraw(int amountPaise) => runBusy((busy) {
    _withdrawing = busy;
    notify();
  }, () => _repository.requestInstantPayout(amountPaise));

  bool get isDepositing => _depositing;

  Future<CashDeposit> depositCash(int amountPaise, DepositMethod method) =>
      runBusy((busy) {
        _depositing = busy;
        notify();
      }, () => _repository.depositCash(amountPaise, method));
}
