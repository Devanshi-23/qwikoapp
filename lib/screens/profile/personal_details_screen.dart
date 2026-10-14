import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../controllers/profile_controller.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/media_ref.dart';
import '../../services/image_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/media_image.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/unsaved_changes_guard.dart';
import '../support/help_support_screen.dart';

class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ProfileController _controller = context.services.profile;
  late final _profile = _controller.profile!;

  late final _nameController = TextEditingController(text: _profile.name);
  late final _emailController = TextEditingController(text: _profile.email);
  late final _phoneController = TextEditingController(text: _profile.phone);
  late final _addressController = TextEditingController(text: _profile.address);
  late MediaRef? _photo = _profile.photo;
  bool _photoChanged = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final path = await ImageService.pickImage(context);
    if (path != null) {
      setState(() {
        _photo = MediaRef.file(path);
        _photoChanged = true;
      });
    }
  }

  void _removePhoto() => setState(() {
    _photo = null;
    _photoChanged = _profile.photo != null;
  });

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _controller.updatePersonal(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        photo: _photoChanged ? _photo : null,
        removePhoto: _photoChanged && _photo == null,
      );
    } on AppFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Personal details saved'),
        backgroundColor: AppColors.primary,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final photo = mediaImageProvider(_photo);

    return UnsavedChangesGuard(
      isDirty: () =>
          _photoChanged ||
          _nameController.text.trim() != _profile.name ||
          _emailController.text.trim() != _profile.email ||
          _addressController.text.trim() != _profile.address,
      child: _buildScaffold(photo),
    );
  }

  Widget _buildScaffold(ImageProvider? photo) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Personal Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _changePhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: AppColors.primaryLight,
                          backgroundImage: photo,
                          child: photo == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  size: 50,
                                  color: AppColors.primary,
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _changePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _photo == null ? 'Add photo' : 'Change photo',
                        ),
                      ),
                      if (_photo != null)
                        TextButton.icon(
                          onPressed: _removePhoto,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Remove photo'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Full Name',
                  hint: 'Enter your full name',
                  icon: Icons.person_outline_rounded,
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  validator: Validators.name,
                ),
                AppTextField(
                  label: 'Email Address',
                  hint: 'Enter your email address',
                  icon: Icons.mail_outline_rounded,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.optionalEmail,
                ),
                AppTextField(
                  label: 'Phone Number',
                  hint: '10-digit phone number',
                  icon: Icons.phone_outlined,
                  controller: _phoneController,
                  enabled: false,
                ),
                Transform.translate(
                  offset: const Offset(0, -12),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRoutes.help,
                      arguments: const HelpRequest(
                        category: 'Change phone number',
                        message:
                            'I want to change the phone number on my '
                            'account. My new number is: ',
                      ),
                    ),
                    child: const Text(
                      'Changing your number needs verification · Contact '
                      'support',
                    ),
                  ),
                ),
                AppTextField(
                  label: 'Address',
                  hint: 'House no., street, city',
                  icon: Icons.location_on_outlined,
                  controller: _addressController,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => PrimaryButton(
                    label: 'Save Details',
                    isLoading: _controller.isSaving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
