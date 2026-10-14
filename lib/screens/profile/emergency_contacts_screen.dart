import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/demo_labels.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/state_views.dart';

/// People the safety screen alerts during an SOS.
class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  static const maxContacts = 3;

  @override
  Widget build(BuildContext context) {
    final controller = context.services.profile;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final profile = controller.profile;
        final contacts = profile?.emergencyContacts ?? const [];
        final canAdd = contacts.length < maxContacts && !controller.isSaving;
        return AppScaffold(
          title: 'Emergency contacts',
          body: profile == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'We alert these people when you use SOS. Add up to '
                      '$maxContacts.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (contacts.isEmpty)
                      const EmptyState(
                        icon: Icons.contact_phone_outlined,
                        title: 'No emergency contacts',
                        message: 'Add someone we can reach if you need help.',
                        boxed: true,
                      ),
                    for (final (index, contact) in contacts.indexed)
                      _ContactTile(
                        contact: contact,
                        onEdit: () => _edit(context, profile, index),
                        onDelete: () => _delete(context, profile, index),
                      ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Add contact',
                      icon: Icons.person_add_alt_1_rounded,
                      variant: ButtonVariant.outlined,
                      onPressed: canAdd
                          ? () => _edit(context, profile, null)
                          : null,
                    ),
                    if (!canAdd && contacts.length >= maxContacts)
                      const DisabledReason(
                        'You have $maxContacts contacts. Remove one to add '
                        'another.',
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _save(
    BuildContext context,
    List<EmergencyContact> contacts,
    String message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.services.profile.updateEmergencyContacts(contacts);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on AppFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _edit(
    BuildContext context,
    PartnerProfile profile,
    int? index,
  ) async {
    final contacts = profile.emergencyContacts;
    final existing = index == null ? null : contacts[index];
    final result = await showAppBottomSheet<EmergencyContact>(
      context,
      title: existing == null ? 'Add contact' : 'Edit contact',
      builder: (context) => _ContactForm(
        initial: existing,
        ownPhone: profile.phone,
        takenPhones: {
          for (final (i, c) in contacts.indexed)
            if (i != index) c.phone,
        },
      ),
    );
    if (result == null || !context.mounted) return;
    final updated = [...contacts];
    index == null ? updated.add(result) : updated[index] = result;
    await _save(
      context,
      updated,
      existing == null ? '${result.name} added' : '${result.name} updated',
    );
  }

  Future<void> _delete(
    BuildContext context,
    PartnerProfile profile,
    int index,
  ) async {
    final contact = profile.emergencyContacts[index];
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove ${contact.name}?',
      message: "They won't be alerted when you use SOS.",
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _save(context, [
      for (final (i, c) in profile.emergencyContacts.indexed)
        if (i != index) c,
    ], '${contact.name} removed');
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  final EmergencyContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        tileColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        leading: const Icon(Icons.person_rounded, color: AppColors.primary),
        title: Text(contact.name),
        subtitle: Text('${contact.relation} · +91 ${contact.phone}'),
        onTap: onEdit,
        trailing: IconButton(
          tooltip: 'Remove ${contact.name}',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _ContactForm extends StatefulWidget {
  const _ContactForm({
    required this.initial,
    required this.ownPhone,
    required this.takenPhones,
  });

  final EmergencyContact? initial;
  final String ownPhone;
  final Set<String> takenPhones;

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _relation = TextEditingController(text: widget.initial?.relation);
  late final _phone = TextEditingController(text: widget.initial?.phone);

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final error = Validators.emergencyContactPhone(
      value,
      ownPhone: widget.ownPhone,
    );
    if (error != null) return error;
    return widget.takenPhones.contains(value!.trim())
        ? 'This number is already a contact'
        : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      EmergencyContact(
        name: _name.text.trim(),
        relation: _relation.text.trim(),
        phone: _phone.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: Validators.name,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _relation,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Relation',
              hintText: 'e.g. Mother, Friend',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter how you know them' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
            ),
            validator: _validatePhone,
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Save contact', onPressed: _submit),
        ],
      ),
    );
  }
}
