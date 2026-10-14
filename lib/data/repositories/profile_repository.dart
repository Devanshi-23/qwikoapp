import '../../models/media_ref.dart';
import '../../models/partner.dart';

abstract interface class ProfileRepository {
  Future<PartnerProfile> fetchProfile();

  Future<PartnerProfile> updatePersonal({
    required String name,
    required String email,
    required String phone,
    required String address,
    MediaRef? photo,

    /// Removes the profile picture. The KYC selfie document is kept.
    bool removePhoto = false,
  });

  Future<PartnerProfile> updateVehicle(Vehicle vehicle);

  Future<PartnerProfile> updateBank(BankAccount bank, {required String upiId});

  /// Replaces the media for the given documents; each moves to review.
  Future<PartnerProfile> saveDocuments(Map<DocumentType, MediaRef> documents);

  Future<PartnerProfile> submitForVerification();

  /// Up to three contacts SOS alerts go to.
  Future<PartnerProfile> updateEmergencyContacts(
    List<EmergencyContact> contacts,
  );

  /// Asks whether verification has finished.
  Future<PartnerProfile> refreshVerification();
}
