/// The sign-in saved on this device, so the app reopens signed in without
/// the network. A real backend would also keep its refresh token here, in
/// secure storage.
class SavedSession {
  const SavedSession({required this.partnerId});

  final String partnerId;

  Map<String, Object?> toJson() => {'partnerId': partnerId};

  /// Null when [json] isn't a saved session.
  static SavedSession? fromJson(Object? json) => switch (json) {
    {'partnerId': final String id} when id.isNotEmpty => SavedSession(
      partnerId: id,
    ),
    _ => null,
  };
}

abstract interface class SessionStore {
  Future<SavedSession?> read();

  Future<void> write(SavedSession session);

  Future<void> clear();
}

/// Keeps the session only while the app runs (tests, and builds without
/// device storage).
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  SavedSession? _session;

  @override
  Future<SavedSession?> read() async => _session;

  @override
  Future<void> write(SavedSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
