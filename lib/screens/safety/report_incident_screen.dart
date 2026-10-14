import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../models/media_ref.dart';
import '../../models/support.dart';
import '../../services/image_service.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/media_image.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/unsaved_changes_guard.dart';

/// Records an accident, harassment, breakdown or unsafe place, and opens a
/// linked support request.
class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  SafetyIncidentType? _type;
  late DateTime _at = context.services.clock.now();
  MediaRef? _photo;
  String? _error;

  bool get _dirty =>
      _type != null || _description.text.isNotEmpty || _photo != null;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = context.services.clock.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => _at = picked.isAfter(now) ? now : picked);
  }

  Future<void> _addPhoto() async {
    final path = await ImageService.pickImage(context);
    if (path != null && mounted) {
      setState(() => _photo = MediaRef.file(path));
    }
  }

  Future<void> _submit() async {
    final type = _type;
    if (!_formKey.currentState!.validate() || type == null) return;
    setState(() => _error = null);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final incident = await context.services.safety.reportIncident(
        type: type,
        at: _at,
        description: _description.text,
        photo: _photo,
      );
      navigator.pop();
      final ticketId = incident.ticketId;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${type.label} reported. Our safety team will call.'),
          action: ticketId == null
              ? null
              : SnackBarAction(
                  label: 'View',
                  onPressed: () => navigator.pushNamed(
                    AppRoutes.ticket,
                    arguments: ticketId,
                  ),
                ),
        ),
      );
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safety = context.services.safety;
    final textTheme = Theme.of(context).textTheme;
    final photo = _photo;
    return UnsavedChangesGuard(
      isDirty: () => _dirty,
      child: AppScaffold(
        title: 'Report an incident',
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text('What happened?', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final type in SafetyIncidentType.reportable)
                    ChoiceChip(
                      label: Text(type.label),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('When'),
                subtitle: Text(
                  formatDateTime(_at, now: context.services.clock.now()),
                ),
                trailing: TextButton(
                  onPressed: _pickWhen,
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _description,
                minLines: 4,
                maxLines: 8,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Describe what happened',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: Validators.incidentDescription,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (photo == null)
                OutlinedButton.icon(
                  onPressed: _addPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add a photo (optional)'),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox.square(
                    dimension: 48,
                    child: MediaImage(media: photo),
                  ),
                  title: const Text('Photo added'),
                  trailing: IconButton(
                    tooltip: 'Remove photo',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _photo = null),
                  ),
                ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              ListenableBuilder(
                listenable: safety,
                builder: (context, _) => PrimaryButton(
                  label: 'Send report',
                  icon: Icons.send_rounded,
                  isLoading: safety.isSending,
                  onPressed: _type == null ? null : _submit,
                ),
              ),
              if (_type == null) const DisabledReason('Choose what happened.'),
            ],
          ),
        ),
      ),
    );
  }
}
