import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/google_password_saver.dart';
import '../../../../core/widgets/industrial_app_bar.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int _tabIndex = 0; // 0 = Sign In, 1 = Sign Up

  // Sign In controllers
  final TextEditingController _loginEmailCtrl = TextEditingController();
  final TextEditingController _loginPassCtrl = TextEditingController();

  // Sign Up controllers (Strict 4 mandatory fields)
  final TextEditingController _signUpCompanyCtrl = TextEditingController();
  final TextEditingController _signUpPhoneCtrl = TextEditingController();
  final TextEditingController _signUpEmailCtrl = TextEditingController();
  final TextEditingController _signUpPassCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _loginPasswordVisible = false;
  bool _signupPasswordVisible = false;

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _signUpCompanyCtrl.dispose();
    _signUpPhoneCtrl.dispose();
    _signUpEmailCtrl.dispose();
    _signUpPassCtrl.dispose();
    super.dispose();
  }

  void _routeAfterLogin() {
    if (!mounted) return;
    if (AuthController.instance.isAdmin) {
      Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
    } else if (!AuthController.instance.isApproved) {
      Navigator.pushReplacementNamed(context, AppRoutes.pendingVerification);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
    }
  }

  Future<void> _handleSignIn() async {
    final email = _loginEmailCtrl.text.trim();
    final password = _loginPassCtrl.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email.';
        _successMessage = null;
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your password.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await AuthController.instance.signIn(email: email, password: password);
      TextInput.finishAutofillContext(shouldSave: true);
      GooglePasswordSaver.save(username: email, password: password);
      _routeAfterLogin();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignUp() async {
    final company = _signUpCompanyCtrl.text.trim();
    final phone = _signUpPhoneCtrl.text.trim();
    final email = _signUpEmailCtrl.text.trim();
    final password = _signUpPassCtrl.text.trim();

    // Strict validation - all 4 fields mandatory
    if (company.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your company name.';
        _successMessage = null;
      });
      return;
    }

    if (phone.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your phone number.';
        _successMessage = null;
      });
      return;
    }

    final cleanPhoneDigits = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (cleanPhoneDigits.length < 7 || !RegExp(r'^[0-9]+$').hasMatch(cleanPhoneDigits)) {
      setState(() {
        _errorMessage = 'Please enter a valid phone number.';
        _successMessage = null;
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email.';
        _successMessage = null;
      });
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
        _successMessage = null;
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your password.';
        _successMessage = null;
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final res = await AuthController.instance.signUp(
        companyName: company,
        phone: phone,
        email: email,
        password: password,
      );

      if (!mounted) return;

      TextInput.finishAutofillContext(shouldSave: true);
      GooglePasswordSaver.save(username: email, password: password);

      if (res.sessionActive) {
        _routeAfterLogin();
      } else {
        setState(() {
          _successMessage = res.message;
          _tabIndex = 0; // Switch to Sign In tab
          _loginEmailCtrl.text = email;
          _loginPassCtrl.text = password;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildPillTextField({
    required TextEditingController controller,
    required String placeholder,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onSubmitted,
    Iterable<String>? autofillHints,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofillHints: autofillHints,
        style: AppTypography.bodyLg.copyWith(color: AppColors.primary),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: AppTypography.bodyLg.copyWith(
            color: AppColors.primary.withValues(alpha: 0.55),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Icon(prefixIcon, color: AppColors.primary, size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 24),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: suffixIcon,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 24),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50),
            borderSide: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50),
            borderSide: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 2.0,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: IndustrialAppBar(
        title: loc.translate('app_title'),
        showBackButton: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.gutterMobile,
              vertical: AppDimensions.spaceMd,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Application Icon Image
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/webappicon.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Center(
                    child: Text(
                      'PIVOT BEARINGS INDIA',
                      style: AppTypography.headlineSm.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Pill Tab Selector Switcher
                  Container(
                    height: 50,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _tabIndex = 0;
                                _errorMessage = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: _tabIndex == 0 ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'SIGN IN',
                                style: AppTypography.labelMd.copyWith(
                                  color: _tabIndex == 0 ? AppColors.background : AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _tabIndex = 1;
                                _errorMessage = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: _tabIndex == 1 ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'SIGN UP',
                                style: AppTypography.labelMd.copyWith(
                                  color: _tabIndex == 1 ? AppColors.background : AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Pill Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 20, color: Color(0xFFDC2626)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTypography.bodySm.copyWith(
                                color: const Color(0xFF991B1B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _errorMessage = null),
                            child: const Icon(Icons.close, size: 18, color: Color(0xFFDC2626)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Pill Success Banner
                  if (_successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF16A34A)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: AppTypography.bodySm.copyWith(
                                color: const Color(0xFF166534),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _successMessage = null),
                            child: const Icon(Icons.close, size: 18, color: Color(0xFF16A34A)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Form Container
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _tabIndex == 0 ? _buildSignInForm() : _buildSignUpForm(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPillTextField(
            controller: _loginEmailCtrl,
            placeholder: 'Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
          ),
          const SizedBox(height: 14),
          _buildPillTextField(
            controller: _loginPassCtrl,
            placeholder: 'Password',
            prefixIcon: Icons.lock_outline,
            obscureText: !_loginPasswordVisible,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _handleSignIn(),
            suffixIcon: IconButton(
              icon: Icon(
                _loginPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              onPressed: () => setState(() => _loginPasswordVisible = !_loginPasswordVisible),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return AppColors.primary;
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return const Color(0xFF001438);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return const Color(0xFF002B7A);
                  }
                  return AppColors.primary;
                }),
                foregroundColor: WidgetStateProperty.all(AppColors.background),
                elevation: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) return 4.0;
                  return 1.5;
                }),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              onPressed: _isLoading ? null : _handleSignIn,
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.background),
                      ),
                    )
                  : Text(
                      'SIGN IN',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.background,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignUpForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPillTextField(
            controller: _signUpCompanyCtrl,
            placeholder: 'Company Name',
            prefixIcon: Icons.business_outlined,
          ),
          const SizedBox(height: 14),
          _buildPillTextField(
            controller: _signUpPhoneCtrl,
            placeholder: 'Number',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: 14),
          _buildPillTextField(
            controller: _signUpEmailCtrl,
            placeholder: 'Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email, AutofillHints.newUsername],
          ),
          const SizedBox(height: 14),
          _buildPillTextField(
            controller: _signUpPassCtrl,
            placeholder: 'Password',
            prefixIcon: Icons.lock_outline,
            obscureText: !_signupPasswordVisible,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _handleSignUp(),
            suffixIcon: IconButton(
              icon: Icon(
                _signupPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              onPressed: () => setState(() => _signupPasswordVisible = !_signupPasswordVisible),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return AppColors.primary;
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return const Color(0xFF001438);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return const Color(0xFF002B7A);
                  }
                  return AppColors.primary;
                }),
                foregroundColor: WidgetStateProperty.all(AppColors.background),
                elevation: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) return 4.0;
                  return 1.5;
                }),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              onPressed: _isLoading ? null : _handleSignUp,
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.background),
                      ),
                    )
                  : Text(
                      'SIGN UP',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.background,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
