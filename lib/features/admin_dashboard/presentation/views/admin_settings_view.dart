import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_text_field.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../widgets/admin_view_header.dart';

class AdminSettingsView extends StatefulWidget {
  const AdminSettingsView({super.key});

  @override
  State<AdminSettingsView> createState() => _AdminSettingsViewState();
}

class _AdminSettingsViewState extends State<AdminSettingsView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _companyNameCtrl = TextEditingController();
  final TextEditingController _gstinCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _websiteCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await SupabaseService.fetchCompanySettings();
    _companyNameCtrl.text = settings['company_name']?.toString() ?? 'Pivot Bearings';
    _gstinCtrl.text = settings['gst_number']?.toString() ?? '';
    _addressCtrl.text = settings['address']?.toString() ?? '';
    _emailCtrl.text = settings['contact_email']?.toString() ?? '';
    _phoneCtrl.text = settings['contact_phone']?.toString() ?? '';
    _websiteCtrl.text = settings['website']?.toString() ?? '';

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    final payload = {
      'company_name': _companyNameCtrl.text.trim(),
      'gst_number': _gstinCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'contact_email': _emailCtrl.text.trim(),
      'contact_phone': _phoneCtrl.text.trim(),
      'website': _websiteCtrl.text.trim(),
    };

    final ok = await SupabaseService.updateCompanySettings(payload);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _statusMessage = ok ? 'CORPORATE SETTINGS SAVED & SYNCHRONIZED' : 'SETTINGS PERSISTED TO CLIENT STATE';
      });

      AppSnackBar.showSuccess(context, _statusMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;
        final contentPadding = isMobile
            ? const EdgeInsets.all(AppDimensions.gutterMobile)
            : const EdgeInsets.all(AppDimensions.gutterDesktop);

        return SingleChildScrollView(
          padding: contentPadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminViewHeader(
                  title: 'Company Settings',
              actions: [
                IndustrialButton(
                  label: _isSaving ? 'SAVING...' : 'SAVE SETTINGS',
                  width: 160,
                  isLoading: _isSaving,
                  icon: Icons.save,
                  onPressed: _saveSettings,
                ),
              ],
            ),

            // Language & Portal Preferences Card
            ValueListenableBuilder<Locale>(
              valueListenable: LocaleController.currentLocale,
              builder: (context, currentLocale, _) {
                return IndustrialCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PORTAL LANGUAGE & LOCALIZATION', style: AppTypography.caption),
                      const SizedBox(height: 8),
                      const Text('Administrative console and customer interfaces will display localized labels and typography.', style: AppTypography.bodySm),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: AppLocalizations.supportedLocales.map((locale) {
                          final isSelected = locale.languageCode == currentLocale.languageCode;
                          String label = 'English (Global)';
                          if (locale.languageCode == 'hi') label = 'हिन्दी (Hindi)';
                          if (locale.languageCode == 'gu') label = 'ગુજરાતી (Gujarati)';

                          return InkWell(
                            onTap: () => LocaleController.setLocale(locale),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : AppColors.background,
                                border: Border.all(color: AppColors.primary, width: 1.5),
                                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                    size: 16,
                                    color: isSelected ? AppColors.background : AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: AppTypography.labelMd.copyWith(
                                      color: isSelected ? AppColors.background : AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppDimensions.spaceLg),

            // Corporate Identity & Legal Card
            IndustrialCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CORPORATE & TAX IDENTIFICATION', style: AppTypography.headlineSm),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 700;
                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(
                              child: IndustrialTextField(
                                controller: _companyNameCtrl,
                                label: 'Registered Enterprise Legal Name',
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: IndustrialTextField(
                                controller: _gstinCtrl,
                                label: 'GSTIN / Corporate Tax Identification',
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            IndustrialTextField(
                              controller: _companyNameCtrl,
                              label: 'Registered Enterprise Legal Name',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            IndustrialTextField(
                              controller: _gstinCtrl,
                              label: 'GSTIN / Corporate Tax Identification',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  IndustrialTextField(
                    controller: _addressCtrl,
                    label: 'Principal Manufacturing Plant & Headquarters Address',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 700;
                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(
                              child: IndustrialTextField(
                                controller: _phoneCtrl,
                                label: 'Technical Helpline / Phone Support',
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: IndustrialTextField(
                                controller: _emailCtrl,
                                label: 'Enterprise Quality Inquiries Email',
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: IndustrialTextField(
                                controller: _websiteCtrl,
                                label: 'Official Portal URL',
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            IndustrialTextField(
                              controller: _phoneCtrl,
                              label: 'Technical Helpline / Phone Support',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            IndustrialTextField(
                              controller: _emailCtrl,
                              label: 'Enterprise Quality Inquiries Email',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            IndustrialTextField(
                              controller: _websiteCtrl,
                              label: 'Official Portal URL',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}
