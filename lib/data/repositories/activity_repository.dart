import '../../models/activity.dart';

abstract interface class ActivityRepository {
  /// Events in `[from, to)`, oldest first.
  Future<List<ActivityEvent>> events({
    required DateTime from,
    required DateTime to,
  });
}
