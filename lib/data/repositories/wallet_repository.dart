import '../../models/money.dart';

abstract interface class WalletRepository {
  Future<WalletBalance> balance();

  /// Newest first.
  Future<List<Payout>> payouts();

  Future<Payout> requestInstantPayout(int amountPaise);

  Future<CashInHand> cashInHand();

  /// Hands COD cash over to Qwiko. Throws `ValidationFailure` if the amount
  /// is zero or more than the rider holds.
  Future<CashDeposit> depositCash(int amountPaise, DepositMethod method);
}
