import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  bool _isSavingName = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _nameController.text = user?.name ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingName = true);
    final auth = context.read<AuthService>();
    final result = await auth.updateDisplayName(_nameController.text);

    if (!mounted) return;
    setState(() => _isSavingName = false);

    if (!result.success) {
      AppSnackBar.showError(context, result.message);
      return;
    }

    if (result.deferred) {
      AppSnackBar.showInfo(context, result.message);
    } else {
      AppSnackBar.showSuccess(context, result.message);
    }

    if (!mounted) return;
    context.pop();
  }

  Future<void> _pickAndUploadPhoto() async {
    setState(() => _isUploadingPhoto = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (file == null) {
        setState(() => _isUploadingPhoto = false);
        return;
      }

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      final extension = file.path.split('.').last;
      final auth = context.read<AuthService>();
      final result = await auth.updateProfilePhoto(
        bytes: bytes,
        fileExtension: extension,
      );

      if (!mounted) return;
      if (result.success) {
        AppSnackBar.showSuccess(context, result.message);
      } else {
        AppSnackBar.showError(context, result.message);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.showError(context, 'Could not access gallery. Please retry.');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Name cannot be empty';
    if (name.length < 3) return 'Name must be at least 3 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.darkCard,
                          border: Border.all(color: AppTheme.darkDivider),
                        ),
                        child: ClipOval(
                          child: _buildAvatar(user.profileImageUrl, user.displayName),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: IconButton.filled(
                          onPressed: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            minimumSize: const Size(34, 34),
                            padding: const EdgeInsets.all(7),
                          ),
                          icon: _isUploadingPhoto
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.edit_rounded, size: 16),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 280.ms),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Enter your name',
                  prefixIcon: Icons.person_outline_rounded,
                  validator: _validateName,
                ).animate().fadeIn(delay: 100.ms),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Save Changes',
                  icon: Icons.save_outlined,
                  onPressed: (_isSavingName || _isUploadingPhoto) ? null : _saveName,
                  isLoading: _isSavingName,
                ).animate().fadeIn(delay: 170.ms),
                const SizedBox(height: 12),
                Text(
                  'Tip: updates sync across dashboard and profile instantly.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? imageUrl, String fallbackName) {
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackAvatar(fallbackName),
      );
    }
    return _fallbackAvatar(fallbackName);
  }

  Widget _fallbackAvatar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: AppTheme.primaryColor,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 34,
        ),
      ),
    );
  }
}
