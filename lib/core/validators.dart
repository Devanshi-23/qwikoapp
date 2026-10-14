import 'formatters.dart';

/// Field validators from Appendix C of the plan. Each returns a message to
/// show under the field, or `null` when the value is valid. They match the
/// `FormFieldValidator<String>` signature where possible.
class Validators {
  Validators._();

  static final RegExp _mobile = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
  static final RegExp _name = RegExp(r"^[A-Za-z][A-Za-z .']{1,49}$");
  static final RegExp _vehicle = RegExp(
    r'^[A-Z]{2}\s?\d{1,2}\s?[A-Z]{0,3}\s?\d{4}$',
    caseSensitive: false,
  );
  static final RegExp _pan = RegExp(r'^[A-Z]{5}\d{4}[A-Z]$');
  static final RegExp _aadhaar = RegExp(r'^\d{12}$');
  static final RegExp _bankAccount = RegExp(r'^\d{9,18}$');
  static final RegExp _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _upi = RegExp(r'^[\w.\-]{2,256}@[A-Za-z]{2,64}$');

  static const int minWithdrawPaise = 10000;

  static String? mobile(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\s'), '');
    if (digits.isEmpty) return 'Please enter your mobile number';
    return _mobile.hasMatch(digits)
        ? null
        : 'Enter a valid 10-digit mobile number';
  }

  static String? signInOtp(String? value) =>
      RegExp(r'^\d{6}$').hasMatch(value ?? '') ? null : 'Enter the 6-digit OTP';

  static String? deliveryOtp(String? value) =>
      RegExp(r'^\d{4}$').hasMatch(value ?? '')
      ? null
      : 'Enter the 4-digit code from the customer';

  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Please enter your email address';
    return _email.hasMatch(email) ? null : 'Enter a valid email address';
  }

  static String? optionalEmail(String? value) =>
      (value ?? '').trim().isEmpty ? null : email(value);

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    return value.length < 8 ? 'Password must be at least 8 characters' : null;
  }

  static String? name(String? value) =>
      _name.hasMatch((value ?? '').trim()) ? null : 'Enter your full name';

  static String? vehicleRegistration(String? value) {
    final number = (value ?? '').trim();
    if (number.isEmpty) return 'Please enter your vehicle number';
    return _vehicle.hasMatch(number)
        ? null
        : 'Enter a number like DL 3S AB 4821';
  }

  static String? pan(String? value) =>
      _pan.hasMatch((value ?? '').trim().toUpperCase())
      ? null
      : 'Enter a valid PAN, like ABCDE1234F';

  static String? aadhaar(String? value) =>
      _aadhaar.hasMatch((value ?? '').replaceAll(' ', ''))
      ? null
      : 'Enter the 12-digit Aadhaar number';

  static String? bankAccount(String? value) =>
      _bankAccount.hasMatch((value ?? '').trim())
      ? null
      : 'Enter a valid account number (9-18 digits)';

  static String? matches(String? value, String other, String message) =>
      (value ?? '').trim() == other.trim() ? null : message;

  static String? ifsc(String? value) =>
      _ifsc.hasMatch((value ?? '').trim().toUpperCase())
      ? null
      : 'Enter a valid IFSC, like HDFC0001234';

  static String? optionalUpi(String? value) {
    final upi = (value ?? '').trim();
    if (upi.isEmpty) return null;
    return _upi.hasMatch(upi) ? null : 'Enter a valid UPI ID, like name@okbank';
  }

  static String? withdrawAmount({
    required int amountPaise,
    required int availablePaise,
    required bool alreadyWithdrewToday,
  }) {
    if (availablePaise <= 0) return 'No balance available to withdraw';
    if (amountPaise < minWithdrawPaise) {
      return 'Minimum withdrawal is ${formatPaise(minWithdrawPaise)}';
    }
    if (amountPaise > availablePaise) {
      return 'You can withdraw up to ${formatPaise(availablePaise)}';
    }
    if (alreadyWithdrewToday) {
      return 'You can make one instant withdrawal per day';
    }
    return null;
  }

  static String? cashReceived({
    required int receivedPaise,
    required int duePaise,
  }) => receivedPaise < duePaise
      ? 'Cash received is less than ${formatPaise(duePaise)} due'
      : null;

  /// Not an error: a likely typo the rider should double-check.
  static bool isLikelyCashTypo({
    required int receivedPaise,
    required int duePaise,
  }) => receivedPaise - duePaise > 200000;

  static String? cashDeposit({
    required int amountPaise,
    required int cashInHandPaise,
  }) {
    if (amountPaise <= 0) return 'Enter an amount to deposit';
    return amountPaise > cashInHandPaise
        ? 'You can deposit up to ${formatPaise(cashInHandPaise)}'
        : null;
  }

  static String? chatMessage(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return "Message can't be empty";
    return text.length > 200 ? 'Keep messages under 200 characters' : null;
  }

  static String? incidentDescription(String? value) {
    final text = (value ?? '').trim();
    if (text.length < 20) {
      return 'Please describe what happened (at least 20 characters)';
    }
    return text.length > 1000 ? 'Keep it under 1,000 characters' : null;
  }

  static String? emergencyContactPhone(
    String? value, {
    required String ownPhone,
  }) {
    final error = mobile(value);
    if (error != null) return error;
    return (value ?? '').trim() == ownPhone.trim()
        ? 'This is your own number'
        : null;
  }

  static String? reason(String? value, {required bool isOther}) {
    if (!isOther) return null;
    final text = (value ?? '').trim();
    return text.length < 10 || text.length > 200
        ? 'Tell us briefly what happened'
        : null;
  }
}
