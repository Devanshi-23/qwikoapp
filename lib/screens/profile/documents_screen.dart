import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../controllers/profile_controller.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/media_ref.dart';
import '../../models/partner.dart';
import '../../services/image_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/media_image.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_badge.dart';
import '../account/blocked_account_actions.dart';

IconData documentIcon(DocumentType type) => switch (type) {
  DocumentType.photo => Icons.face_rounded,
  DocumentType.aadhaar => Icons.badge_outlined,
  DocumentType.pan => Icons.credit_card_rounded,
  DocumentType.license => Icons.card_membership_rounded,
  DocumentType.rc => Icons.description_outlined,
  DocumentType.insurance => Icons.shield_outlined,
  DocumentType.pucc => Icons.eco_outlined,
};

class DocumentsScreen extends StatefulWidget {
  final bool isOnboarding;

  /// Blocked account state: verification was rejected. Rejected documents
  /// are highlighted and saving resubmits for verification.
  final bool resubmit;

  const DocumentsScreen({
    super.key,
    this.isOnboarding = false,
    this.resubmit = false,
  });

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final ProfileController _controller = context.services.profile;

  /// Photos picked on this screen and not saved yet.
  final Map<DocumentType, MediaRef> _picked = {};

  PartnerProfile get _profile => _controller.profile!;

  bool _hasMedia(DocumentType type) =>
      _picked.containsKey(type) || _profile.documentFor(type).isUploaded;

  Future<void> _upload(DocumentType type) async {
    final path = await ImageService.pickImage(context);
    if (path != null) setState(() => _picked[type] = MediaRef.file(path));
  }

  Future<void> _resubmit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final missing = _profile.rejectedDocuments
        .where((doc) => !_picked.containsKey(doc.type))
        .toList();
    if (missing.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Upload a new ${missing.first.type.title} first'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    try {
      await _controller.saveDocuments(Map.of(_picked));
      final profile = await _controller.submitForVerification();
      _picked.clear();
      AppRoutes.goToAccountHome(navigator, profile);
    } on AppFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (widget.resubmit) return _resubmit();
    final messenger = ScaffoldMessenger.of(context);
    final allUploaded = _profile.requiredDocuments.every(_hasMedia);
    if (widget.isOnboarding && !allUploaded) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please upload all documents to continue'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_picked.isNotEmpty) {
      try {
        await _controller.saveDocuments(Map.of(_picked));
      } on AppFailure catch (failure) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    if (!widget.isOnboarding) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Documents saved'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.profile == null) {
          return const AppScaffold(
            title: 'Documents',
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final required = _profile.requiredDocuments;
        final uploaded = required.where(_hasMedia).length;
        final rejected = _profile.rejectedDocuments;

        return AppScaffold(
          title: 'Documents',
          showDemoBadge: widget.resubmit,
          bottomBar: PrimaryButton(
            label: widget.resubmit
                ? 'Resubmit for verification'
                : widget.isOnboarding
                ? 'Save & Continue'
                : 'Save Documents',
            isLoading: _controller.isSaving,
            onPressed: _save,
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.resubmit && rejected.isNotEmpty)
                _RejectedBanner(rejected),
              AppCard(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$uploaded of ${required.length} uploaded',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: uploaded / required.length,
                        minHeight: 7,
                        backgroundColor: AppColors.border,
                        color: AppColors.primary,
                        semanticsLabel:
                            'Documents uploaded: $uploaded of '
                            '${required.length}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Make sure photos are clear and all text is readable.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              ...required.map(_buildDocumentCard),
              if (widget.resubmit) const BlockedAccountActions(),
            ],
          ),
        );
      },
    );
  }

  static const StatusStyle _readyToSave = StatusStyle(
    'Ready to save',
    StatusTone.success,
    Icons.upload_rounded,
  );

  /// Why a document needs attention, shown under its badge.
  String? _statusDetail(PartnerDocument doc) {
    if (_picked.containsKey(doc.type)) return null;
    final expires = doc.expiresOn;
    return switch (doc.status) {
      DocumentStatus.rejected => doc.rejectionReason,
      DocumentStatus.expiringSoon || DocumentStatus.expired
          when expires != null =>
        '${doc.status == DocumentStatus.expired ? 'Expired' : 'Expires'} '
            '${formatDate(expires, now: context.services.clock.now())}',
      _ => null,
    };
  }

  Widget _buildDocumentCard(DocumentType type) {
    final doc = _profile.documentFor(type);
    final media = _picked[type] ?? doc.media;
    final isUploaded = _hasMedia(type);
    final icon = documentIcon(type);
    final detail = _statusDetail(doc);
    final needsReupload =
        doc.status == DocumentStatus.rejected && !_picked.containsKey(type);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderColor: needsReupload
          ? AppColors.error
          : isUploaded
          ? AppColors.primary.withValues(alpha: 0.4)
          : AppColors.border,
      onTap: () => _upload(type),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 56,
              width: 56,
              color: AppColors.primaryLight,
              child: media != null
                  ? MediaImage(
                      media: media,
                      fallback: Icon(icon, color: AppColors.primary),
                    )
                  : Icon(icon, color: AppColors.primary, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (_picked.containsKey(type))
                  const StatusBadge(_readyToSave, dense: true)
                else if (isUploaded)
                  StatusBadge.document(doc.status, dense: true)
                else
                  Text(type.hint, style: Theme.of(context).textTheme.bodySmall),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 6),
                if (isUploaded && !needsReupload)
                  const Text(
                    'Tap to change',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: needsReupload
                          ? AppColors.error
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      needsReupload ? 'Re-upload' : 'Upload',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            needsReupload
                ? Icons.error_outline_rounded
                : isUploaded
                ? Icons.check_circle_rounded
                : Icons.upload_rounded,
            color: needsReupload ? AppColors.error : AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _RejectedBanner extends StatelessWidget {
  const _RejectedBanner(this.rejected);

  final List<PartnerDocument> rejected;

  @override
  Widget build(BuildContext context) {
    final names = rejected.map((doc) => doc.type.title).join(', ');
    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppColors.errorLight,
      borderColor: AppColors.error.withValues(alpha: 0.4),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verification needs attention',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$names was rejected. Upload a new photo and resubmit '
                    'to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
