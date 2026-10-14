import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../controllers/profile_controller.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/partner.dart';
import '../../utils/app_colors.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/unsaved_changes_guard.dart';

IconData vehicleIcon(VehicleType type) => switch (type) {
  VehicleType.bike => Icons.two_wheeler_rounded,
  VehicleType.scooter => Icons.moped_rounded,
  VehicleType.eBike => Icons.electric_bike_rounded,
  VehicleType.cycle => Icons.pedal_bike_rounded,
};

class VehicleDetailsScreen extends StatefulWidget {
  final bool isOnboarding;

  const VehicleDetailsScreen({super.key, this.isOnboarding = false});

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ProfileController _controller = context.services.profile;
  late final Vehicle? _vehicle = _controller.profile?.vehicle;

  late VehicleType? _vehicleType = _vehicle?.type;
  late bool _isEv = _vehicle?.isEv ?? false;
  late final _numberController = TextEditingController(
    text: _vehicle?.registrationNumber ?? '',
  );
  late final _modelController = TextEditingController(
    text: _vehicle?.model ?? '',
  );

  bool get _needsNumber => _vehicleType?.needsRegistration ?? true;

  @override
  void dispose() {
    _numberController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);

    final type = _vehicleType;
    if (type == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select your vehicle type'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    try {
      await _controller.updateVehicle(
        Vehicle(
          type: type,
          registrationNumber: _needsNumber
              ? _numberController.text.trim().toUpperCase()
              : '',
          model: _modelController.text.trim(),
          isEv: type == VehicleType.eBike || (_needsNumber && _isEv),
        ),
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

    if (!widget.isOnboarding) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Vehicle details saved'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    isDirty: () =>
        _vehicleType != _vehicle?.type ||
        _isEv != (_vehicle?.isEv ?? false) ||
        _numberController.text.trim() != (_vehicle?.registrationNumber ?? '') ||
        _modelController.text.trim() != (_vehicle?.model ?? ''),
    child: _buildScaffold(context),
  );

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Vehicle Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vehicle Type',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: VehicleType.values.map(_buildTypeCard).toList(),
                ),
                const SizedBox(height: 24),
                if (_needsNumber) ...[
                  AppTextField(
                    label: 'Vehicle Number',
                    hint: 'e.g. DL 01 AB 1234',
                    icon: Icons.pin_outlined,
                    controller: _numberController,
                    textCapitalization: TextCapitalization.characters,
                    validator: Validators.vehicleRegistration,
                  ),
                  SwitchListTile(
                    value: _isEv,
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                    title: const Text('Electric vehicle'),
                    subtitle: const Text('EVs do not need a PUC certificate'),
                    onChanged: (v) => setState(() => _isEv = v),
                  ),
                  const SizedBox(height: 8),
                ],
                AppTextField(
                  label: 'Vehicle Model (optional)',
                  hint: 'e.g. Honda Activa 6G',
                  icon: Icons.directions_bike_outlined,
                  controller: _modelController,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => PrimaryButton(
                    label: widget.isOnboarding
                        ? 'Save & Continue'
                        : 'Save Details',
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

  Widget _buildTypeCard(VehicleType type) {
    final selected = _vehicleType == type;

    return InkWell(
      onTap: () => setState(() => _vehicleType = type),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              vehicleIcon(type),
              size: 32,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              type.label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
