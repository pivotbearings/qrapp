import 'package:flutter/material.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _companySettings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final profile = await SupabaseService.fetchUserProfile();
    final company = await SupabaseService.fetchCompanySettings();
    if (mounted) {
      setState(() {
        _userProfile = profile;
        _companySettings = company;
        _isLoading = false;
      });
    }
  }

  void _onLanguageSelected(String langCode) {
    LocaleController.setLanguageCode(langCode);
    final msg = langCode == 'hi'
        ? 'भाषा हिंदी में बदल दी गई है।'
        : (langCode == 'gu' ? 'ભાષા ગુજરાતીમાં બદલાઈ ગઈ છે.' : 'Language set to English.');
    AppSnackBar.showSuccess(context, msg);
  }

  void _showEditProfileDialog() {
    final auth = AuthController.instance;
    final currentName = (auth.userName?.isNotEmpty == true && auth.userName != 'Operator')
        ? auth.userName!
        : (_userProfile?['full_name']?.toString() ?? '');
    final currentCompany = auth.userCompany ?? (_userProfile?['company_name']?.toString() ?? '');
    final currentPhone = auth.userPhone ?? (_userProfile?['phone']?.toString() ?? '');

    final nameCtrl = TextEditingController(text: currentName);
    final companyCtrl = TextEditingController(text: currentCompany);
    final phoneCtrl = TextEditingController(text: currentPhone);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit Customer Profile',
                  style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Full Name / Customer Name *', style: AppTypography.caption),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Enter your name',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Company Name', style: AppTypography.caption),
                const SizedBox(height: 6),
                TextField(
                  controller: companyCtrl,
                  decoration: InputDecoration(
                    hintText: 'Enter company name',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Contact Phone', style: AppTypography.caption),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '+91 98765 43210',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.primary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                if (newName.isEmpty) {
                  AppSnackBar.showError(ctx, 'Name cannot be empty');
                  return;
                }
                Navigator.pop(ctx);
                final ok = await AuthController.instance.updateCustomerProfile(
                  fullName: newName,
                  companyName: companyCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                );
                if (mounted) {
                  if (ok) {
                    AppSnackBar.showSuccess(context, 'Profile updated successfully!');
                    _loadData();
                  } else {
                    AppSnackBar.showError(context, 'Failed to update profile');
                  }
                }
              },
              child: const Text('Save Profile'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSignOut() async {
    await AuthController.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.authLogin, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = AuthController.instance;
    final currentLang = LocaleController.locale.languageCode;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: IndustrialAppBar(
        title: loc.translate('customer_profile'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          loc.translate('customer_profile'),
                          style: AppTypography.headlineLgMobile,
                        ),
                        TextButton.icon(
                          onPressed: _showEditProfileDialog,
                          icon: const Icon(Icons.edit, size: 16, color: AppColors.primary),
                          label: const Text(
                            'EDIT PROFILE',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spaceMd),

                    // User Identity Card
                    IndustrialCard(
                      borderRadius: BorderRadius.circular(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Center(
                                  child: Icon(Icons.person, color: AppColors.background, size: 24),
                                ),
                              ),
                              const SizedBox(width: AppDimensions.spaceSm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (auth.userName?.isNotEmpty == true && auth.userName != 'Operator')
                                          ? auth.userName!
                                          : (_userProfile?['full_name']?.toString().isNotEmpty == true
                                              ? _userProfile!['full_name'].toString()
                                              : (auth.userEmail?.isNotEmpty == true ? auth.userEmail!.split('@').first : 'Operator')),
                                      style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      auth.userEmail?.isNotEmpty == true
                                          ? auth.userEmail!
                                          : (_userProfile?['email']?.toString() ?? '—'),
                                      style: AppTypography.bodySm.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IndustrialStatusBadge(
                                statusText: auth.isAdmin ? 'Admin' : 'User',
                              ),
                            ],
                          ),
                          const Divider(),
                          _buildDetailRow(
                            loc.translate('company_name'),
                            (_userProfile?['company_name']?.toString().isNotEmpty == true && _userProfile!['company_name'].toString() != '—')
                                ? _userProfile!['company_name'].toString()
                                : (auth.userCompany?.isNotEmpty == true ? auth.userCompany! : '—'),
                          ),
                          _buildDetailRow(
                            loc.translate('facility_code'),
                            (_userProfile?['facility_code']?.toString().isNotEmpty == true && _userProfile!['facility_code'].toString() != '—')
                                ? _userProfile!['facility_code'].toString()
                                : 'FAC-REG',
                            isMono: true,
                          ),
                          _buildDetailRow(
                            'Contact Phone',
                            (_userProfile?['phone']?.toString().isNotEmpty == true && _userProfile!['phone'].toString() != '—')
                                ? _userProfile!['phone'].toString()
                                : (auth.userPhone?.isNotEmpty == true ? auth.userPhone! : '—'),
                            isMono: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppDimensions.spaceLg),

                    // Tenant Workspace & Isolation Info
                    Text(
                      'Tenant Workspace & Isolation',
                      style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    IndustrialCard(
                      borderRadius: BorderRadius.circular(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _userProfile?['company_name']?.toString().isNotEmpty == true
                                      ? _userProfile!['company_name'].toString()
                                      : 'Corporate Tenant Partition',
                                  style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Text(
                                  'DATA ISOLATED',
                                  style: TextStyle(
                                    color: AppColors.background,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          _buildDetailRow(
                            'Tenant Partition ID',
                            auth.userId != null
                                ? (auth.userId!.length > 18 ? '${auth.userId!.substring(0, 18)}...' : auth.userId!)
                                : '—',
                            isMono: true,
                          ),
                          _buildDetailRow(
                            'Assigned Facility Code',
                            _userProfile?['facility_code']?.toString().isNotEmpty == true
                                ? _userProfile!['facility_code'].toString()
                                : 'FAC-REG',
                            isMono: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppDimensions.spaceLg),

                    // Centralized Language Settings Card
                    Text(
                      loc.translate('language_settings'),
                      style: AppTypography.headlineSm,
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    IndustrialCard(
                      borderRadius: BorderRadius.circular(28),
                      padding: const EdgeInsets.all(AppDimensions.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select interface language for field verification and telemetry:',
                            style: AppTypography.caption,
                          ),
                          const SizedBox(height: AppDimensions.spaceSm),
                          Row(
                            children: [
                              Expanded(
                                child: _buildLanguageOption(
                                  code: 'en',
                                  title: 'English',
                                  nativeTitle: 'English (UK/IN)',
                                  isSelected: currentLang == 'en',
                                ),
                              ),
                              const SizedBox(width: AppDimensions.spaceSm),
                              Expanded(
                                child: _buildLanguageOption(
                                  code: 'hi',
                                  title: 'Hindi',
                                  nativeTitle: 'हिंदी',
                                  isSelected: currentLang == 'hi',
                                ),
                              ),
                              const SizedBox(width: AppDimensions.spaceSm),
                              Expanded(
                                child: _buildLanguageOption(
                                  code: 'gu',
                                  title: 'Gujarati',
                                  nativeTitle: 'ગુજરાતી',
                                  isSelected: currentLang == 'gu',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppDimensions.spaceLg),

                    // Official Corporate & Registry Info (Loaded dynamically from Supabase)
                    Text(
                      'Corporate Registry & Authority',
                      style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    IndustrialCard(
                      borderRadius: BorderRadius.circular(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Entity', _companySettings?['company_name'] ?? 'Pivot Bearings India'),
                          _buildDetailRow(loc.translate('gst_number'), _companySettings?['gst_number'] ?? '27AABCP1234F1ZQ', isMono: true),
                          _buildDetailRow(loc.translate('contact_helpline'), _companySettings?['contact_phone'] ?? '+91 98988 57198', isMono: true),
                          _buildDetailRow('Support Email', _companySettings?['contact_email'] ?? 'pivotbearings@gmail.com'),
                          _buildDetailRow(loc.translate('official_website'), _companySettings?['website'] ?? 'https://www.pivotbearingsindia.com/', isMono: true),
                          const Divider(),
                          Text(
                            loc.translate('registered_office'),
                            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _companySettings?['address'] ?? 'Plot 42, Sector 10, Chakan MIDC Phase II, Pune, Maharashtra 410501',
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppDimensions.spaceLg),

                    // Actions Tray
                    if (auth.isAdmin) ...[
                      IndustrialButton(
                        label: 'OPEN ADMIN WORKSTATION',
                        icon: Icons.admin_panel_settings,
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.adminDashboard),
                      ),
                    ],

                    IndustrialButton.danger(
                      label: loc.translate('sign_out'),
                      icon: Icons.logout,
                      onPressed: _handleSignOut,
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    Center(
                      child: Text(
                        'Pivot Bearings Precision OS • v1.0.0 (Build 2026.10)',
                        style: AppTypography.caption.copyWith(fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceMd),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String code,
    required String title,
    required String nativeTitle,
    required bool isSelected,
  }) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => _onLanguageSelected(code),
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          border: Border.all(color: AppColors.primary, width: 1.5),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Column(
          children: [
            Text(
              nativeTitle,
              style: AppTypography.labelMd.copyWith(
                color: isSelected ? AppColors.background : AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: AppTypography.caption.copyWith(
                color: isSelected ? AppColors.background : AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppColors.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: (isMono ? AppTypography.mono : AppTypography.bodyMd).copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
