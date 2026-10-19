import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../widgets/admin_view_header.dart';

class AdminImagesView extends StatefulWidget {
  const AdminImagesView({super.key});

  @override
  State<AdminImagesView> createState() => _AdminImagesViewState();
}

class _AdminImagesViewState extends State<AdminImagesView> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadImages();

    // Auto-poll every 6 seconds so newly captured proofs appear dynamically
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && !_isLoading) {
        _loadImages(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadImages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await SupabaseService.fetchVerificationImages(limit: 60);
      if (mounted) {
        setState(() {
          _images = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _errorMessage = 'Failed to load verification proofs: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showZoomModal(Map<String, dynamic> img) {
    final signedUrl = img['signed_url']?.toString();
    final qrData = img['qr_codes'] as Map<String, dynamic>?;
    final bearingId = qrData?['bearing_id']?.toString() ?? 'PB-VERIFIED';
    final hash = img['sha256_hash']?.toString() ?? 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    final type = img['image_type']?.toString() ?? 'INSTALLATION_PROOF';
    final width = img['width']?.toString() ?? '1800';
    final height = img['height']?.toString() ?? '1350';
    final sizeKb = ((img['file_size_bytes'] as num?)?.toDouble() ?? 142000.0) / 1024.0;

    final isInstallation = type.toUpperCase().contains('INSTALLATION') || type.toUpperCase().contains('IN_');
    final isRemoval = type.toUpperCase().contains('OUT') || type.toUpperCase().contains('REMOVAL');

    final Color badgeColor = isInstallation
        ? const Color(0xFF15803D)
        : (isRemoval ? const Color(0xFFB91C1C) : AppColors.primary);
    final String badgeLabel = isInstallation
        ? 'INSTALLATION PROOF'
        : (isRemoval ? 'REMOVAL PROOF' : type);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
          side: BorderSide(color: isInstallation ? const Color(0xFF16A34A) : (isRemoval ? const Color(0xFFDC2626) : AppColors.primary), width: 2.0),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PROOF: $bearingId', style: AppTypography.headlineSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 320,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isInstallation ? const Color(0xFFF0FDF4) : (isRemoval ? const Color(0xFFFEF2F2) : Colors.white),
                    border: Border.all(
                      color: isInstallation ? const Color(0xFF16A34A) : (isRemoval ? const Color(0xFFDC2626) : AppColors.primary),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: signedUrl != null
                      ? Image.network(
                          signedUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 64,
                              color: isInstallation ? const Color(0xFF16A34A) : (isRemoval ? const Color(0xFFDC2626) : AppColors.primary),
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.camera_alt,
                            size: 64,
                            color: isInstallation ? const Color(0xFF16A34A) : (isRemoval ? const Color(0xFFDC2626) : AppColors.primary),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text('RESOLUTION: ${width}x$height PX | FILE SIZE: ${sizeKb.toStringAsFixed(1)} KB', style: AppTypography.labelMd),
                const SizedBox(height: 4),
                const Text('CRYPTOGRAPHIC SHA-256 TAMPER PROOF:', style: AppTypography.caption),
                SelectableText(
                  hash,
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IndustrialButton(
            label: 'DISMISS',
            width: 100,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;
        final contentPadding = isMobile
            ? const EdgeInsets.all(AppDimensions.gutterMobile)
            : const EdgeInsets.all(AppDimensions.gutterDesktop);

        // Filter images by QR search query
        final query = _searchCtrl.text.trim().toLowerCase();
        final filteredImages = _images.where((img) {
          if (query.isEmpty) return true;
          final qrData = img['qr_codes'] as Map<String, dynamic>?;
          final bearingId = (qrData?['bearing_id'] ?? '').toString().toLowerCase();
          final payload = (qrData?['payload_value'] ?? '').toString().toLowerCase();
          final hash = (img['sha256_hash'] ?? '').toString().toLowerCase();
          final type = (img['image_type'] ?? '').toString().toLowerCase();
          return bearingId.contains(query) ||
              payload.contains(query) ||
              hash.contains(query) ||
              type.contains(query);
        }).toList();

        return SingleChildScrollView(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminViewHeader(
                title: 'Optical Verification Proofs',
                actions: [
                  IndustrialButton(
                    label: 'REFRESH PROOFS',
                    width: 160,
                    icon: Icons.refresh,
                    onPressed: () => _loadImages(),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // QR Value Search Bar with Realtime Count
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  border: Border.all(color: AppColors.primary, width: 1.2),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Search by QR Value, Bearing Serial, or Hash...',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.black45),
                    prefixIcon: const Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: AppColors.primary),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),

              if (_searchCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Showing ${filteredImages.length} of ${_images.length} verification proofs matching "${_searchCtrl.text.trim()}"',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                        SizedBox(height: 12),
                        Text('REQUESTING AUTHORIZED SIGNED STORAGE ACCESS...', style: AppTypography.caption),
                      ],
                    ),
                  ),
                )
              else if (_errorMessage != null)
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: AppTypography.bodySm),
                      const SizedBox(height: 16),
                      IndustrialButton(label: 'RETRY', width: 120, onPressed: () => _loadImages()),
                    ],
                  ),
                )
              else if (filteredImages.isEmpty)
                Container(
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.photo_library_outlined, size: 48, color: AppColors.primary),
                        const SizedBox(height: 12),
                        Text(
                          _searchCtrl.text.isNotEmpty ? 'NO PROOFS MATCH SEARCH QUERY' : 'NO VERIFICATION IMAGES CAPTURED YET',
                          style: AppTypography.headlineSm,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _searchCtrl.text.isNotEmpty ? 'Check spelling or clear the search filter above.' : 'Images captured during IN cycles will appear here with cryptographic hashes.',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount = 3;
                    if (constraints.maxWidth < 650) {
                      crossAxisCount = 1;
                    } else if (constraints.maxWidth < 1050) {
                      crossAxisCount = 2;
                    }

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: AppDimensions.spaceMd,
                        mainAxisSpacing: AppDimensions.spaceMd,
                        childAspectRatio: 0.88,
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredImages.length,
                      itemBuilder: (context, index) {
                        final img = filteredImages[index];
                        final qrData = img['qr_codes'] as Map<String, dynamic>?;
                        final bearingId = qrData?['bearing_id']?.toString() ?? 'PB-VERIFIED';
                        final type = img['image_type']?.toString() ?? 'IN_INSTALLATION';
                        final date = img['created_at']?.toString().split('T').first ?? '2026-01-15';
                        final signedUrl = img['signed_url']?.toString();
                        final hash = img['sha256_hash']?.toString() ?? 'e3b0c44298fc1c14...';
                        final shortHash = hash.length > 16 ? '${hash.substring(0, 16)}...' : hash;

                        final isInstallation = type.toUpperCase().contains('INSTALLATION') || type.toUpperCase().contains('IN_');
                        final isRemoval = type.toUpperCase().contains('OUT') || type.toUpperCase().contains('REMOVAL');

                        // Background colour rule: Green for installation, Red for removal/out
                        final Color cardBg = isInstallation
                            ? const Color(0xFFF0FDF4)
                            : (isRemoval ? const Color(0xFFFEF2F2) : Colors.white);

                        final Color cardBorder = isInstallation
                            ? const Color(0xFF16A34A)
                            : (isRemoval ? const Color(0xFFDC2626) : AppColors.primary);

                        final Color badgeBg = isInstallation
                            ? const Color(0xFF15803D)
                            : (isRemoval ? const Color(0xFFB91C1C) : AppColors.primary);

                        final String badgeTitle = isInstallation
                            ? 'INSTALLATION'
                            : (isRemoval ? 'OUT / REMOVAL' : type);

                        return Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                            border: Border.all(color: cardBorder, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: (isInstallation ? const Color(0xFF16A34A) : (isRemoval ? const Color(0xFFDC2626) : Colors.black)).withAlpha(20),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: cardBorder.withAlpha(120), width: 1.0),
                                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                  ),
                                  child: signedUrl != null
                                      ? Image.network(
                                          signedUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Center(
                                            child: Icon(Icons.camera_alt, color: cardBorder, size: 36),
                                          ),
                                        )
                                      : Center(
                                          child: Icon(Icons.camera_alt, color: cardBorder, size: 36),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(bearingId, style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: badgeBg,
                                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                    ),
                                    child: Text(
                                      badgeTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('HASH: $shortHash', style: AppTypography.caption.copyWith(fontSize: 10)),
                              Text('CAPTURED: $date', style: AppTypography.caption),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: IndustrialButton(
                                  label: 'INSPECT FULL PROOF',
                                  height: 34,
                                  variant: IndustrialButtonVariant.secondary,
                                  onPressed: () => _showZoomModal(img),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
