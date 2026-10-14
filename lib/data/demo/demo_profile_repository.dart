import '../../core/domain_events.dart';
import '../../core/failures.dart';
import '../../models/media_ref.dart';
import '../../models/partner.dart';
import '../repositories/profile_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoProfileRepository implements ProfileRepository {
  DemoProfileRepository(this._backend);

  final DemoBackend _backend;

  PartnerProfile _save(PartnerProfile profile) {
    _backend.db.partner = profile;
    _backend.events.emit(const ProfileChanged());
    return profile;
  }

  @override
  Future<PartnerProfile> fetchProfile() =>
      _backend.engine.run(OperationType.loadProfile, () {
        _backend.settleReviews();
        return _backend.db.partner;
      });

  static const maxEmergencyContacts = 3;

  @override
  Future<PartnerProfile> updateEmergencyContacts(
    List<EmergencyContact> contacts,
  ) => _backend.engine.run(OperationType.saveProfile, () {
    if (contacts.length > maxEmergencyContacts) {
      throw const ValidationFailure('You can add up to 3 emergency contacts.');
    }
    return _save(_backend.db.partner.copyWith(emergencyContacts: contacts));
  });

  @override
  Future<PartnerProfile> updatePersonal({
    required String name,
    required String email,
    required String phone,
    required String address,
    MediaRef? photo,
    bool removePhoto = false,
  }) => _backend.engine.run(OperationType.saveProfile, () {
    var profile = _backend.db.partner.copyWith(
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      address: address.trim(),
      photo: photo,
      clearPhoto: removePhoto,
    );
    if (photo != null) {
      profile = _withDocument(profile, DocumentType.photo, photo);
    }
    return _save(profile);
  });

  @override
  Future<PartnerProfile> updateVehicle(Vehicle vehicle) =>
      _backend.engine.run(OperationType.saveProfile, () {
        final current = _backend.db.partner;
        var profile = current.copyWith(vehicle: vehicle);
        final rc = profile.documentFor(DocumentType.rc);
        if (current.vehicle != null &&
            current.vehicle!.type != vehicle.type &&
            rc.isUploaded) {
          profile = _replaceDocument(
            profile,
            rc.copyWith(status: DocumentStatus.pending),
          );
        }
        return _save(profile);
      });

  @override
  Future<PartnerProfile> updateBank(
    BankAccount bank, {
    required String upiId,
  }) => _backend.engine.run(OperationType.saveProfile, () {
    if (bank.verification == BankVerification.verifying) {
      _backend.startReview(DemoBackend.bankReviewKey);
    }
    return _save(_backend.db.partner.copyWith(bank: bank, upiId: upiId.trim()));
  });

  @override
  Future<PartnerProfile> saveDocuments(Map<DocumentType, MediaRef> documents) =>
      _backend.engine.run(OperationType.saveProfile, () {
        var profile = _backend.db.partner;
        // An active partner's re-uploads are reviewed on their own; new
        // accounts wait for the whole verification.
        final reviewNow = profile.isVerified;
        documents.forEach((type, media) {
          profile = _withDocument(profile, type, media);
          if (type == DocumentType.photo) {
            profile = profile.copyWith(photo: media);
          }
          if (reviewNow) {
            _backend.startReview(
              type.name,
              reject: _backend.rejectNextDocument,
            );
            _backend.rejectNextDocument = false;
          }
        });
        return _save(profile);
      });

  @override
  Future<PartnerProfile> submitForVerification() => _backend.engine.run(
    OperationType.verification,
    () {
      final profile = _backend.db.partner;
      if (!profile.isKycComplete) {
        throw const ValidationFailure(
          'Add your vehicle, documents and bank details first.',
        );
      }
      final rejected = profile.rejectedDocuments;
      if (rejected.isNotEmpty) {
        throw ValidationFailure(
          'Upload a new ${rejected.first.type.title} first.',
        );
      }
      return _save(profile.copyWith(verification: VerificationStatus.pending));
    },
  );

  /// Demo: review finishes only through Demo Controls ("Simulate approval"
  /// or "Simulate rejection").
  @override
  Future<PartnerProfile> refreshVerification() => _backend.engine.run(
    OperationType.verification,
    () => _backend.db.partner,
  );

  PartnerProfile _withDocument(
    PartnerProfile profile,
    DocumentType type,
    MediaRef media,
  ) => _replaceDocument(
    profile,
    PartnerDocument(type: type, status: DocumentStatus.pending, media: media),
  );

  PartnerProfile _replaceDocument(
    PartnerProfile profile,
    PartnerDocument doc,
  ) => profile.copyWith(
    documents: [...profile.documents.where((d) => d.type != doc.type), doc],
  );
}
