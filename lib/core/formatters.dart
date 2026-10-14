import 'dart:math' as math;

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

String formatDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

String formatMonthYear(DateTime date) =>
    '${_months[date.month - 1]} ${date.year}';

String formatDateTime(DateTime date, {DateTime? now}) =>
    '${formatDate(date, now: now)}, ${formatTime(date)}';

String timeAgo(DateTime time, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(time);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} h ago';
  if (difference.inDays < 7) return '${difference.inDays} d ago';
  return formatDate(time, now: now);
}

/// Rupees with Indian digit grouping, rounded to the nearest rupee:
/// `formatRupees(123456)` → `₹1,23,456`.
String formatRupees(double amount) {
  final negative = amount < 0;
  final whole = amount.abs().round().toString();
  final sign = negative ? '-' : '';
  if (whole.length <= 3) return '$sign₹$whole';

  final lastThree = whole.substring(whole.length - 3);
  var rest = whole.substring(0, whole.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '$sign₹${groups.join(',')},$lastThree';
}

/// Money is stored as integer paise; this formats it as whole rupees.
String formatPaise(int paise) => formatRupees(paise / 100);

/// What a screen reader should say for an amount: `1,295 rupees`.
String spokenPaise(int paise) {
  final rupees = (paise / 100).round();
  final digits = formatRupees(rupees.abs().toDouble()).substring(1);
  final unit = rupees.abs() == 1 ? 'rupee' : 'rupees';
  return '${rupees < 0 ? 'minus ' : ''}$digits $unit';
}

int rupeesToPaise(num rupees) => (rupees * 100).round();

/// Why a cash-on-delivery offer can't be accepted: collecting it would take
/// cash in hand over the limit, which leaves [roomPaise] to collect.
String codLimitReason(int roomPaise) =>
    'Deposit cash to accept COD orders above ${formatPaise(roomPaise)}.';

String formatDistance(int meters) =>
    meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1)} km';

String formatDuration(Duration duration) =>
    '${duration.inHours}h ${duration.inMinutes % 60}m';

/// Timer style: "0:42", "4:05", "12:30".
String formatClock(Duration duration) {
  final seconds = math.max(0, duration.inSeconds);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Travel time rounded up to whole minutes: "1 min", "12 min", "1 h 5 min".
String formatMinutes(Duration duration) {
  final minutes = math.max(1, (duration.inSeconds / 60).ceil());
  return minutes >= 60
      ? '${minutes ~/ 60} h ${minutes % 60} min'
      : '$minutes min';
}

/// Rounds navigation distances the way riders read them: "50 m", "350 m",
/// "1.2 km".
String formatStepDistance(int meters) => meters < 1000
    ? '${(meters / 10).round() * 10} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
