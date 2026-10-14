import 'media_ref.dart';

enum VerificationStatus { newSignup, pending, verified, rejected, suspended }

enum DocumentType {
  photo('Profile Photo', 'A clear selfie with your face visible'),
  aadhaar('Aadhaar Card', 'Front side of your Aadhaar card'),
  pan('PAN Card', 'Front side of your PAN card'),
  license('Driving Licence', 'Front side of your driving licence'),
  rc('Vehicle RC', 'Registration certificate of your vehicle'),
  insurance('Vehicle Insurance', 'Current insurance policy of your vehicle'),
  pucc('PUC Certificate', 'Valid pollution under control certificate');

  const DocumentType(this.title, this.hint);

  final String title;
  final String hint;
}

enum DocumentStatus {
  notUploaded('Not uploaded'),
  pending('Under review'),
  verified('Verified'),
  rejected('Rejected'),
  expiringSoon('Expiring soon'),
  expired('Expired');

  const DocumentStatus(this.label);

  final String label;
}

class PartnerDocument {
  const PartnerDocument({
    required this.type,
    this.status = DocumentStatus.notUploaded,
    this.rejectionReason,
    this.expiresOn,
    this.media,
  });

  final DocumentType type;
  final DocumentStatus status;
  final String? rejectionReason;
  final DateTime? expiresOn;
  final MediaRef? media;

  bool get isUploaded => status != DocumentStatus.notUploaded;

  bool isExpiredAt(DateTime now) {
    if (status == DocumentStatus.expired) return true;
    final expires = expiresOn;
    return expires != null &&
        status != DocumentStatus.pending &&
        !now.isBefore(expires);
  }

  PartnerDocument copyWith({
    DocumentStatus? status,
    String? rejectionReason,
    DateTime? expiresOn,
    MediaRef? media,
  }) => PartnerDocument(
    type: type,
    status: status ?? this.status,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    expiresOn: expiresOn ?? this.expiresOn,
    media: media ?? this.media,
  );

  @override
  bool operator ==(Object other) =>
      other is PartnerDocument &&
      other.type == type &&
      other.status == status &&
      other.rejectionReason == rejectionReason &&
      other.expiresOn == expiresOn &&
      other.media == media;

  @override
  int get hashCode =>
      Object.hash(type, status, rejectionReason, expiresOn, media);

  @override
  String toString() => 'PartnerDocument(${type.name}, ${status.name})';
}

enum VehicleType {
  bike('Bike'),
  scooter('Scooter'),
  eBike('Electric Bike'),
  cycle('Cycle');

  const VehicleType(this.label);

  final String label;

  /// Low-speed e-bikes and cycles need no licence, RC, insurance or PUCC.
  bool get needsRegistration => this == bike || this == scooter;
}

class Vehicle {
  const Vehicle({
    required this.type,
    this.registrationNumber = '',
    this.model = '',
    this.isEv = false,
  });

  final VehicleType type;
  final String registrationNumber;
  final String model;
  final bool isEv;

  String get summary => registrationNumber.isEmpty
      ? type.label
      : '${type.label} • $registrationNumber';

  @override
  bool operator ==(Object other) =>
      other is Vehicle &&
      other.type == type &&
      other.registrationNumber == registrationNumber &&
      other.model == model &&
      other.isEv == isEv;

  @override
  int get hashCode => Object.hash(type, registrationNumber, model, isEv);

  @override
  String toString() => 'Vehicle($summary)';
}

enum BankVerification { verifying, verified, failed }

class BankAccount {
  const BankAccount({
    required this.holderName,
    required this.accountNumber,
    required this.ifsc,
    required this.bankName,
    this.verification = BankVerification.verified,
  });

  final String holderName;

  /// Kept in full only in demo mode so the edit form can be prefilled.
  final String accountNumber;
  final String ifsc;
  final String bankName;
  final BankVerification verification;

  String get last4 => accountNumber.length <= 4
      ? accountNumber
      : accountNumber.substring(accountNumber.length - 4);

  String get maskedAccountNumber => '•••• $last4';

  BankAccount copyWith({BankVerification? verification}) => BankAccount(
    holderName: holderName,
    accountNumber: accountNumber,
    ifsc: ifsc,
    bankName: bankName,
    verification: verification ?? this.verification,
  );

  @override
  bool operator ==(Object other) =>
      other is BankAccount &&
      other.holderName == holderName &&
      other.accountNumber == accountNumber &&
      other.ifsc == ifsc &&
      other.verification == verification;

  @override
  int get hashCode =>
      Object.hash(holderName, accountNumber, ifsc, verification);

  @override
  String toString() => 'BankAccount($bankName $maskedAccountNumber)';
}

const Map<String, String> _bankNamesByIfscPrefix = {
  'HDFC': 'HDFC Bank',
  'ICIC': 'ICICI Bank',
  'SBIN': 'State Bank of India',
  'UTIB': 'Axis Bank',
  'KKBK': 'Kotak Mahindra Bank',
  'PUNB': 'Punjab National Bank',
  'BARB': 'Bank of Baroda',
  'CNRB': 'Canara Bank',
  'YESB': 'Yes Bank',
  'IDIB': 'Indian Bank',
};

String bankNameForIfsc(String ifsc) =>
    _bankNamesByIfscPrefix[ifsc.toUpperCase().padRight(4).substring(0, 4)] ??
    'Bank';

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.relation,
    required this.phone,
  });

  final String name;
  final String relation;
  final String phone;

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact &&
      other.name == name &&
      other.relation == relation &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(name, relation, phone);
}

class RatingSummary {
  const RatingSummary({
    this.average = 0,
    this.count = 0,
    this.distribution = const [0, 0, 0, 0, 0],
    this.recentCompliments = const [],
    this.tips = const [],
  });

  final double average;
  final int count;

  /// Counts of 1★ to 5★ ratings, in that order.
  final List<int> distribution;
  final List<String> recentCompliments;
  final List<String> tips;
}

class PartnerProfile {
  const PartnerProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.address = '',
    this.photo,
    this.rating = const RatingSummary(),
    required this.joinedOn,
    this.verification = VerificationStatus.newSignup,
    this.suspensionReason,
    this.vehicle,
    this.bank,
    this.upiId = '',
    this.documents = const [],
    this.emergencyContacts = const [],
    this.homeZoneId,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final MediaRef? photo;
  final RatingSummary rating;
  final DateTime joinedOn;
  final VerificationStatus verification;
  final String? suspensionReason;
  final Vehicle? vehicle;
  final BankAccount? bank;
  final String upiId;
  final List<PartnerDocument> documents;
  final List<EmergencyContact> emergencyContacts;
  final String? homeZoneId;

  String get firstName => name.trim().split(' ').first;

  bool get isVerified => verification == VerificationStatus.verified;

  bool get hasVehicleDetails => vehicle != null;

  bool get hasBankDetails => bank != null;

  /// Documents this partner must provide for their vehicle (plan 3.8.9).
  List<DocumentType> get requiredDocuments => requiredDocumentsFor(vehicle);

  PartnerDocument documentFor(DocumentType type) => documents.firstWhere(
    (doc) => doc.type == type,
    orElse: () => PartnerDocument(type: type),
  );

  int get uploadedDocumentCount =>
      requiredDocuments.where((type) => documentFor(type).isUploaded).length;

  bool get hasAllDocuments => uploadedDocumentCount == requiredDocuments.length;

  bool get isKycComplete =>
      hasVehicleDetails && hasAllDocuments && hasBankDetails;

  /// Required documents that were rejected and need a new upload.
  List<PartnerDocument> get rejectedDocuments => [
    for (final type in requiredDocuments)
      if (documentFor(type).status == DocumentStatus.rejected)
        documentFor(type),
  ];

  /// Required documents that have expired as of [now]. A replacement that is
  /// under review no longer counts as expired.
  List<PartnerDocument> expiredDocumentsAt(DateTime now) => [
    for (final type in requiredDocuments)
      if (documentFor(type).isExpiredAt(now)) documentFor(type),
  ];

  PartnerProfile copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    MediaRef? photo,
    RatingSummary? rating,
    VerificationStatus? verification,
    String? suspensionReason,
    Vehicle? vehicle,
    BankAccount? bank,
    String? upiId,
    List<PartnerDocument>? documents,
    List<EmergencyContact>? emergencyContacts,
    String? homeZoneId,
    bool clearSuspensionReason = false,
    bool clearPhoto = false,
  }) => PartnerProfile(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    photo: clearPhoto ? null : photo ?? this.photo,
    rating: rating ?? this.rating,
    joinedOn: joinedOn,
    verification: verification ?? this.verification,
    suspensionReason: clearSuspensionReason
        ? null
        : suspensionReason ?? this.suspensionReason,
    vehicle: vehicle ?? this.vehicle,
    bank: bank ?? this.bank,
    upiId: upiId ?? this.upiId,
    documents: documents ?? this.documents,
    emergencyContacts: emergencyContacts ?? this.emergencyContacts,
    homeZoneId: homeZoneId ?? this.homeZoneId,
  );

  @override
  bool operator ==(Object other) =>
      other is PartnerProfile &&
      other.id == id &&
      other.name == name &&
      other.phone == phone &&
      other.email == email &&
      other.address == address &&
      other.photo == photo &&
      other.verification == verification &&
      other.suspensionReason == suspensionReason &&
      other.vehicle == vehicle &&
      other.bank == bank &&
      other.upiId == upiId &&
      _listEquals(other.documents, documents);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    phone,
    email,
    address,
    photo,
    verification,
    vehicle,
    bank,
    upiId,
    Object.hashAll(documents),
  );

  @override
  String toString() => 'PartnerProfile($id, $name, ${verification.name})';
}

List<DocumentType> requiredDocumentsFor(Vehicle? vehicle) {
  const base = [DocumentType.photo, DocumentType.aadhaar, DocumentType.pan];
  final type = vehicle?.type;
  if (type != null && !type.needsRegistration) return base;
  return [
    ...base,
    DocumentType.license,
    DocumentType.rc,
    DocumentType.insurance,
    if (vehicle?.isEv != true) DocumentType.pucc,
  ];
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
