import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/auth.dart';
import '../../utils/app_colors.dart';
import '../../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showEmail = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _sendingOtp = false;
  bool _signingIn = false;

  static const Color primaryColor = AppColors.primary;
  static const Color textColor = AppColors.textDark;
  static const Color hintColor = AppColors.textSecondary;
  static const Color backgroundColor = AppColors.background;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showFailure(AppFailure failure) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _continueWithPhone() async {
    FocusScope.of(context).unfocus();
    if (!_phoneFormKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    setState(() => _sendingOtp = true);
    try {
      await context.services.session.requestOtp(
        _phoneController.text.trim(),
        OtpPurpose.signIn,
      );
    } on AppFailure catch (failure) {
      if (mounted) _showFailure(failure);
      return;
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
    navigator.pushNamed(AppRoutes.otp, arguments: OtpPurpose.signIn);
  }

  Future<void> _signInWithEmail() async {
    FocusScope.of(context).unfocus();
    if (!_emailFormKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    setState(() => _signingIn = true);
    try {
      final partner = await context.services.session.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      AppRoutes.goToAccountHome(navigator, partner);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() => _signingIn = false);
      _showFailure(failure);
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA1A9B8), fontSize: 14),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      counterText: '',
      filled: true,
      fillColor: backgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  static const TextStyle _labelStyle = TextStyle(
    color: textColor,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  Widget _buildPhoneForm() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Mobile number', style: _labelStyle),
          const SizedBox(height: 9),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofillHints: const [AutofillHints.telephoneNumberNational],
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: Validators.mobile,
            onFieldSubmitted: (_) => _continueWithPhone(),
            decoration:
                _inputDecoration(
                  hint: '10-digit mobile number',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 16, right: 8),
                    child: Text(
                      '+91',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ).copyWith(
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Continue with phone',
            icon: Icons.arrow_forward_rounded,
            isLoading: _sendingOtp,
            onPressed: _continueWithPhone,
          ),
        ],
      ),
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Email address', style: _labelStyle),
          const SizedBox(height: 9),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: Validators.email,
            decoration: _inputDecoration(
              hint: 'you@example.com',
              prefixIcon: const Icon(
                Icons.mail_outline_rounded,
                color: hintColor,
                size: 21,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Password', style: _labelStyle),
          const SizedBox(height: 9),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: Validators.password,
            onFieldSubmitted: (_) => _signInWithEmail(),
            decoration: _inputDecoration(
              hint: 'Enter your password',
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: hintColor,
                size: 21,
              ),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: hintColor,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _rememberMe,
                    activeColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    onChanged: (value) {
                      setState(() => _rememberMe = value ?? false);
                    },
                  ),
                  const Flexible(
                    child: Text(
                      'Remember me',
                      style: TextStyle(color: hintColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.forgotPassword),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Sign in',
            variant: ButtonVariant.outlined,
            isLoading: _signingIn,
            onPressed: _signInWithEmail,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      height: 96,
                      width: 180,
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.delivery_dining_rounded,
                            color: primaryColor,
                            size: 75,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: const Text(
                      'Welcome back!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Sign in to continue your delivery journey.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hintColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _DemoSignInInfo(),
                  const SizedBox(height: 22),
                  _buildPhoneForm(),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: Color(0xFFE8EBF2))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'or',
                          style: TextStyle(color: hintColor, fontSize: 13),
                        ),
                      ),
                      Expanded(child: Divider(color: Color(0xFFE8EBF2))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_showEmail)
                    _buildEmailForm()
                  else
                    PrimaryButton(
                      label: 'Sign in with email',
                      icon: Icons.mail_outline_rounded,
                      variant: ButtonVariant.outlined,
                      onPressed: () => setState(() => _showEmail = true),
                    ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account?",
                        style: TextStyle(color: hintColor, fontSize: 13),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          AppRoutes.signup,
                        ),
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How to sign in to the demo, which account state it uses, and a link to
/// Demo controls.
class _DemoSignInInfo extends StatelessWidget {
  const _DemoSignInInfo();

  @override
  Widget build(BuildContext context) {
    final demo = context.services.demo;
    if (demo == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Use any valid 10-digit mobile number and OTP 123456.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: ListenableBuilder(
              listenable: demo,
              builder: (context, _) => Text(
                'Demo account: ${demo.account.label}',
                style: textTheme.bodySmall,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.demoControls),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Demo controls'),
            ),
          ),
        ],
      ),
    );
  }
}
