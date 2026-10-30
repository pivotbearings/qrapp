import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/services/web_image_picker.dart';
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

  // Advertisement Banner State
  final TextEditingController _adBannerUrlCtrl = TextEditingController();
  final TextEditingController _adBannerLinkCtrl = TextEditingController();
  String _adBannerImage = 'assets/ad_banner.webp';
  bool _adBannerActive = true;
  String _adBannerFitMode = 'cover';
  bool _isAdBannerWebPValid = true;
  String? _uploadedFileName;
  String? _uploadedFileSizeKb;
  String _simulatedDevice = 'standard'; // 'compact', 'standard', 'wide'
  bool _isSavingBanner = false;
  bool _isUploadingBanner = false;

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

    // Load Advertisement Banner Configuration
    try {
      final adConfig = await AdBannerService.fetchBannerConfig();
      _adBannerImage = adConfig.image;
      _adBannerLinkCtrl.text = adConfig.targetUrl;
      if (adConfig.image.startsWith('http')) {
        _adBannerUrlCtrl.text = adConfig.image;
      }
      _adBannerActive = adConfig.isActive;
      _adBannerFitMode = adConfig.fitMode;
      _isAdBannerWebPValid = adConfig.format.toLowerCase() == 'webp' ||
          adConfig.image.contains('.webp') ||
          adConfig.image.contains('image/webp');
    } catch (_) {}

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

    String targetImage = _adBannerImage;
    final typedUrl = _adBannerUrlCtrl.text.trim();
    if (typedUrl.isNotEmpty) {
      targetImage = _sanitizeUrl(typedUrl);
      _adBannerUrlCtrl.text = targetImage;
      _adBannerImage = targetImage;
    }

    final isWebP = targetImage.toLowerCase().contains('.webp') ||
        targetImage.startsWith('data:image/webp');

    // Save Advertisement Banner Configuration
    await AdBannerService.saveBannerConfig(
      AdBannerConfig(
        image: targetImage,
        targetUrl: _adBannerLinkCtrl.text.trim().isNotEmpty
            ? _adBannerLinkCtrl.text.trim()
            : 'https://www.pivotbearingsindia.com/',
        isActive: _adBannerActive,
        format: isWebP ? 'webp' : 'image',
        fitMode: _adBannerFitMode,
      ),
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        _isAdBannerWebPValid = isWebP;
        _statusMessage = ok ? 'CORPORATE SETTINGS & AD BANNER SAVED & SYNCHRONIZED' : 'SETTINGS PERSISTED TO CLIENT STATE';
      });

      AppSnackBar.showSuccess(context, _statusMessage!);
    }
  }

  /// Sanitizes any raw input URL ensuring protocol is present
  String _sanitizeUrl(String input) {
    String u = input.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') &&
        !u.startsWith('https://') &&
        !u.startsWith('assets/') &&
        !u.startsWith('data:')) {
      u = 'https://$u';
    }
    return u;
  }

  /// Handles picking and validating a banner from user storage, then auto-publishing in real-time
  Future<void> _pickWebPFile() async {
    try {
      if (kIsWeb) {
        final picked = await WebImagePicker.pickImage();
        if (picked == null) return;

        setState(() => _isUploadingBanner = true);

        final bytes = picked.bytes;
        final isWebP = AdBannerService.isWebPBytes(bytes) ||
            picked.name.toLowerCase().endsWith('.webp');
        final mimeType = isWebP ? 'image/webp' : picked.mimeType;

        // Upload binary to Supabase Storage (with fallback to data URI)
        final uploadedSource = await AdBannerService.uploadBannerBinary(
          bytes: bytes,
          filename: picked.name,
          mimeType: mimeType,
        );

        final newConfig = AdBannerConfig(
          image: uploadedSource,
          targetUrl: _adBannerLinkCtrl.text.trim().isNotEmpty
              ? _adBannerLinkCtrl.text.trim()
              : 'https://www.pivotbearingsindia.com/',
          isActive: _adBannerActive,
          format: isWebP ? 'webp' : 'image',
          fitMode: _adBannerFitMode,
        );

        // Auto-save and broadcast in real-time to all connected customer home screens
        await AdBannerService.saveBannerConfig(newConfig);

        setState(() {
          _adBannerImage = uploadedSource;
          _isAdBannerWebPValid = isWebP;
          _uploadedFileName = picked.name;
          _uploadedFileSizeKb = (bytes.lengthInBytes / 1024).toStringAsFixed(1);
          _adBannerUrlCtrl.clear();
          _isUploadingBanner = false;
        });

        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'BANNER UPLOADED & REFLECTING LIVE IN REAL-TIME!',
          );
        }
      } else {
        AppSnackBar.showInfo(context, 'On mobile, please configure the banner using the Image URL field below.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingBanner = false);
        AppSnackBar.showError(context, 'Upload error: $e');
      }
    }
  }

  /// Applies image URL entered directly into the URL controller
  void _applyUrlBanner() {
    final raw = _adBannerUrlCtrl.text.trim();
    if (raw.isEmpty) {
      AppSnackBar.showInfo(context, 'Please enter a valid image URL.');
      return;
    }
    final url = _sanitizeUrl(raw);
    _adBannerUrlCtrl.text = url;
    final isWebP = url.toLowerCase().contains('.webp');
    setState(() {
      _adBannerImage = url;
      _isAdBannerWebPValid = isWebP;
      _uploadedFileName = 'Remote Image URL';
      _uploadedFileSizeKb = null;
    });
    AppSnackBar.showSuccess(context, 'Image URL applied to live preview.');
  }

  /// Resets banner back to the default bundled Pivot Bearings WebP advertisement
  Future<void> _resetAdBannerToDefault() async {
    setState(() {
      _adBannerImage = 'assets/ad_banner.webp';
      _adBannerLinkCtrl.text = 'https://www.pivotbearingsindia.com/';
      _adBannerUrlCtrl.clear();
      _adBannerActive = true;
      _adBannerFitMode = 'cover';
      _isAdBannerWebPValid = true;
      _uploadedFileName = 'Default Bundled WebP';
      _uploadedFileSizeKb = '60.3';
    });

    await AdBannerService.resetToDefault();

    if (mounted) {
      AppSnackBar.showSuccess(context, 'Restored default Pivot Bearings WebP advertisement banner.');
    }
  }

  /// Standalone save for the Ad Banner card
  Future<void> _saveAdBannerOnly() async {
    setState(() => _isSavingBanner = true);

    String targetImage = _adBannerImage;
    final typedUrl = _adBannerUrlCtrl.text.trim();
    if (typedUrl.isNotEmpty) {
      targetImage = _sanitizeUrl(typedUrl);
      _adBannerUrlCtrl.text = targetImage;
      _adBannerImage = targetImage;
    }

    final isWebP = targetImage.toLowerCase().contains('.webp') ||
        targetImage.startsWith('data:image/webp');

    final ok = await AdBannerService.saveBannerConfig(
      AdBannerConfig(
        image: targetImage,
        targetUrl: _adBannerLinkCtrl.text.trim().isNotEmpty
            ? _adBannerLinkCtrl.text.trim()
            : 'https://www.pivotbearingsindia.com/',
        isActive: _adBannerActive,
        format: isWebP ? 'webp' : 'image',
        fitMode: _adBannerFitMode,
      ),
    );

    if (mounted) {
      setState(() {
        _isSavingBanner = false;
        _isAdBannerWebPValid = isWebP;
      });
      if (ok) {
        AppSnackBar.showSuccess(context, 'ADVERTISEMENT BANNER PUBLISHED & SYNCHRONIZED');
      } else {
        AppSnackBar.showInfo(context, 'Banner cached locally on device.');
      }
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

            const SizedBox(height: AppDimensions.spaceLg),

            // Customer Home Screen Advertisement Banner (WebP) Card
            _buildAdBannerSection(isMobile),
          ],
        ),
      ),
    );
      },
    );
  }

  /// Customer Advertisement section with clean mobile mockup preview
  Widget _buildAdBannerSection(bool isMobile) {
    return IndustrialCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title + Active Toggle (Zero clutter, zero subtext)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Customer Advertisement',
                style: AppTypography.headlineSm,
              ),
              Row(
                children: [
                  Text(
                    _adBannerActive ? 'Active' : 'Disabled',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _adBannerActive ? AppColors.primary : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _adBannerActive,
                    activeThumbColor: AppColors.primary,
                    onChanged: (val) => setState(() => _adBannerActive = val),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Responsive 2-column on desktop, stacked on mobile
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;

              // Left: Mobile Screen Preview (2:3 aspect ratio matching the customer home screen)
              final previewWidget = Center(
                child: Container(
                  width: 250,
                  height: 375, // 2:3 mobile ratio
                  decoration: BoxDecoration(
                    color: const Color(0xFF001F59),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.primary, width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildAdPreviewImage(),
                      // Subtle phone notch pill at top
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 50,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              // Right: Clean Controls
              final controlsWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dimension Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE), width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.aspect_ratio_rounded, size: 16, color: Color(0xFF1D4ED8)),
                        SizedBox(width: 8),
                        Text(
                          '1080 × 1620 px (2:3 Mobile) · WebP / PNG / JPG',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Upload & Reset buttons
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        icon: _isUploadingBanner
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_rounded, size: 18),
                        label: Text(_isUploadingBanner ? 'Uploading...' : 'Upload Image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isUploadingBanner ? null : _pickWebPFile,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Reset Default'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _resetAdBannerToDefault,
                      ),
                    ],
                  ),

                  if (_uploadedFileName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_uploadedFileName ${_uploadedFileSizeKb != null ? "($_uploadedFileSizeKb KB)" : ""}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Image URL input + Apply button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: IndustrialTextField(
                          controller: _adBannerUrlCtrl,
                          label: 'Image URL',
                          hintText: 'https://domain.com/banner.webp',
                          onChanged: (val) {
                            final trimmed = val.trim();
                            if (trimmed.startsWith('http://') ||
                                trimmed.startsWith('https://') ||
                                trimmed.startsWith('www.')) {
                              final sanitized = _sanitizeUrl(trimmed);
                              setState(() {
                                _adBannerImage = sanitized;
                                _isAdBannerWebPValid = sanitized.toLowerCase().contains('.webp');
                                _uploadedFileName = 'Custom Web Image';
                                _uploadedFileSizeKb = null;
                              });
                            }
                          },
                          onSubmitted: (val) => _applyUrlBanner(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2.0),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary, width: 1.2),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _applyUrlBanner,
                          child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Target Link
                  IndustrialTextField(
                    controller: _adBannerLinkCtrl,
                    label: 'Target Link (Optional)',
                    hintText: 'https://www.pivotbearingsindia.com',
                  ),

                  const SizedBox(height: 12),

                  // Display Mode
                  _buildFitModeSelector(),

                  const SizedBox(height: 18),

                  // Save & Publish
                  IndustrialButton(
                    label: _isSavingBanner ? 'Saving...' : 'Save & Publish',
                    width: double.infinity,
                    isLoading: _isSavingBanner,
                    icon: Icons.check_circle_rounded,
                    onPressed: _saveAdBannerOnly,
                  ),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 260,
                      child: previewWidget,
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      child: controlsWidget,
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  previewWidget,
                  const SizedBox(height: 20),
                  controlsWidget,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFitModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Display Mode',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _adBannerFitMode = 'cover'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _adBannerFitMode == 'cover' ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary, width: 1.2),
                  ),
                  child: Center(
                    child: Text(
                      'Cover (Full Screen)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _adBannerFitMode == 'cover' ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _adBannerFitMode = 'contain'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _adBannerFitMode == 'contain' ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary, width: 1.2),
                  ),
                  child: Center(
                    child: Text(
                      'Contain',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _adBannerFitMode == 'contain' ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdPreviewImage() {
    final fit = _adBannerFitMode == 'cover' ? BoxFit.cover : BoxFit.contain;

    if (_adBannerImage.startsWith('assets/')) {
      return Image.asset(
        _adBannerImage,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildFallbackPreview(),
      );
    }

    if (_adBannerImage.startsWith('data:')) {
      try {
        final raw = _adBannerImage.contains(',') ? _adBannerImage.split(',')[1] : _adBannerImage;
        final bytes = base64Decode(raw);
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildFallbackPreview(),
        );
      } catch (_) {
        return _buildFallbackPreview();
      }
    }

    if (_adBannerImage.startsWith('http')) {
      return Image.network(
        _adBannerImage,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFF001F59),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image_rounded, color: Colors.amber, size: 28),
              const SizedBox(height: 6),
              const Text(
                'Could not load image from URL',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                _adBannerImage,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return _buildFallbackPreview();
  }

  Widget _buildFallbackPreview() {
    return Container(
      color: const Color(0xFF001F59),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.precision_manufacturing_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            const Text(
              'PIVOT INDUSTRIAL BEARINGS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Heavy-Duty Precision Engineering',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


