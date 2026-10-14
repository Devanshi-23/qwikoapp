import '../core/domain_events.dart';
import '../data/repositories/profile_repository.dart';
import '../models/media_ref.dart';
import '../models/partner.dart';
import 'loadable_controller.dart';

class ProfileController extends LoadableController {
  ProfileController({required this._repository, super.events});

  final ProfileRepository _repository;

  PartnerProfile? _profile;
  bool _saving = false;

  PartnerProfile? get profile => _profile;

  bool get isSaving => _saving;

  /// Used by the session after sign-in so the profile is ready immediately.
  void setProfile(PartnerProfile profile) {
    _profile = profile;
    markReady();
    notify();
  }

  @override
  Future<void> fetch() async => _profile = await _repository.fetchProfile();

  @override
  void clearData() => _profile = null;

  @override
  bool shouldRefresh(DomainEvent event) => event is ProfileChanged && !_saving;

  void _setSaving(bool value) {
    _saving = value;
    notify();
  }

  Future<PartnerProfile> _save(Future<PartnerProfile> Function() action) =>
      runBusy(_setSaving, () async {
        final updated = await action();
        _profile = updated;
        return updated;
      });

  Future<PartnerProfile> updatePersonal({
    required String name,
    required String email,
    required String phone,
    required String address,
    MediaRef? photo,
    bool removePhoto = false,
  }) => _save(
    () => _repository.updatePersonal(
      name: name,
      email: email,
      phone: phone,
      address: address,
      photo: photo,
      removePhoto: removePhoto,
    ),
  );

  Future<PartnerProfile> updateVehicle(Vehicle vehicle) =>
      _save(() => _repository.updateVehicle(vehicle));

  Future<PartnerProfile> updateBank(
    BankAccount bank, {
    required String upiId,
  }) => _save(() => _repository.updateBank(bank, upiId: upiId));

  Future<PartnerProfile> updateEmergencyContacts(
    List<EmergencyContact> contacts,
  ) => _save(() => _repository.updateEmergencyContacts(contacts));

  Future<PartnerProfile> saveDocuments(Map<DocumentType, MediaRef> documents) =>
      _save(() => _repository.saveDocuments(documents));

  Future<PartnerProfile> submitForVerification() =>
      _save(_repository.submitForVerification);

  Future<PartnerProfile> refreshVerification() =>
      _save(_repository.refreshVerification);
}
