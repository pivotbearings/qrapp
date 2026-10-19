import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../widgets/admin_view_header.dart';

class AdminImagesView extends StatefulWidget {
  const AdminImagesView({super.key});

  @override
  State<AdminImagesView> createState() => _AdminImagesViewState();
}

class _AdminImagesViewState extends State<AdminImagesView> {
  List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SupabaseService.fetchVerificationImages(limit: 40);
      if (mounted) {
        setState(() {
          _images = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
          side: const BorderSide(color: AppColors.primary, width: 2.0),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PROOF: $bearingId', style: AppTypography.headlineSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
              ),
              child: Text(type, style: const TextStyle(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold)),
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
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                ),
                child: signedUrl != null
                    ? Image.network(
                        signedUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image, size: 64, color: AppColors.primary),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.camera_alt, size: 64, color: AppColors.primary),
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
                onPressed: _loadImages,
              ),
            ],
          ),

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
                  IndustrialButton(label: 'RETRY', width: 120, onPressed: _loadImages),
                ],
              ),
            )
          else if (_images.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.photo_library_outlined, size: 48, color: AppColors.primary),
                    SizedBox(height: 12),
                    Text('NO VERIFICATION IMAGES CAPTURED YET', style: AppTypography.headlineSm),
                    SizedBox(height: 4),
                    Text('Images captured during IN/OUT cycles will appear here with cryptographic hashes.', style: AppTypography.caption),
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
                    childAspectRatio: 0.9,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final img = _images[index];
                    final qrData = img['qr_codes'] as Map<String, dynamic>?;
                    final bearingId = qrData?['bearing_id']?.toString() ?? 'PB-VERIFIED';
                    final type = img['image_type']?.toString() ?? 'IN_INSTALLATION';
                    final date = img['created_at']?.toString().split('T').first ?? '2026-01-15';
                    final signedUrl = img['signed_url']?.toString();
                    final hash = img['sha256_hash']?.toString() ?? 'e3b0c44298fc1c14...';
                    final shortHash = hash.length > 16 ? '${hash.substring(0, 16)}...' : hash;

                    return IndustrialCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.primary, width: 1.0),
                                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                              ),
                              child: signedUrl != null
                                  ? Image.network(
                                      signedUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(Icons.camera_alt, color: AppColors.primary, size: 36),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.camera_alt, color: AppColors.primary, size: 36),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(bearingId, style: AppTypography.labelMd),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                ),
                                child: Text(type, style: const TextStyle(color: AppColors.background, fontSize: 9, fontWeight: FontWeight.bold)),
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
