import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  bool _isLoading = false;

  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late TextEditingController _locationController;
  late TextEditingController _websiteController;

  File? _avatarImage;

  @override
  void initState() {
    super.initState();
    final profile = widget.userData['profile'] ?? {};
    _usernameController =
        TextEditingController(text: profile['username'] ?? '');
    _bioController = TextEditingController(text: profile['bio'] ?? '');
    _locationController =
        TextEditingController(text: profile['location'] ?? '');
    _websiteController = TextEditingController(text: profile['website'] ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<File?> _compressImage(File file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          "${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";

      var result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 75,
        minWidth: 1200,
        minHeight: 1200,
      );

      if (result == null) return null;
      return File(result.path);
    } catch (e) {
      return null;
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Edit Photo',
            toolbarColor: const Color(0xFFE74C3C),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Edit Photo',
            aspectRatioLockEnabled: true,
            aspectRatioPickerButtonHidden: true,
            minimumAspectRatio: 1.0,
          ),
        ],
      );
      if (croppedFile != null) {
        return File(croppedFile.path);
      }
    } catch (e) {
      debugPrint('Crop error: $e');
    }
    return null;
  }

  Future<void> _pickImage() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      bool granted = false;
      if (Platform.isAndroid) {
        if (source == ImageSource.camera) {
          final status = await Permission.camera.request();
          granted = status.isGranted;
        } else {
          Map<Permission, PermissionStatus> statuses = await [
            Permission.photos,
            Permission.storage,
          ].request();
          if ((statuses[Permission.photos]?.isGranted ?? false) ||
              (statuses[Permission.storage]?.isGranted ?? false)) {
            granted = true;
          }
        }
      } else {
        final status = source == ImageSource.camera
            ? await Permission.camera.request()
            : await Permission.photos.request();
        granted = status.isGranted || status.isLimited;
      }

      if (!granted && Platform.isAndroid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Permission not granted. Action might fail.')));
        }
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        File originalFile = File(pickedFile.path);

        // Crop the image first
        File? croppedFile = await _cropImage(originalFile);

        // Then compress the cropped image (or original if cropping failed/cancelled)
        File? compressedFile =
            await _compressImage(croppedFile ?? originalFile);

        setState(() {
          _avatarImage = compressedFile ?? originalFile;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final data = {
      'username': _usernameController.text,
      'bio': _bioController.text,
      'location': _locationController.text,
      'website': _websiteController.text,
    };

    final error =
        await _apiService.updateProfile(data, avatarPath: _avatarImage?.path);

    setState(() => _isLoading = false);

    if (error == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to trigger refresh
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Current avatar from network
    final String? currentAvatarUrl = widget.userData['profile']?['avatar'];

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        title: const Text('EDIT PROFILE',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2, color: Colors.white)),
        backgroundColor: const Color(0xFF1B4D3E),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Center(
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE1B12C), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: const Color(0xFF1B4D3E).withOpacity(0.1),
                        backgroundImage: _avatarImage != null
                            ? FileImage(_avatarImage!)
                            : (currentAvatarUrl != null
                                ? CachedNetworkImageProvider(
                                    ApiService.getImageUrl(currentAvatarUrl))
                                : null) as ImageProvider?,
                        child: (_avatarImage == null && currentAvatarUrl == null)
                            ? const Icon(Icons.person_rounded, size: 60, color: Color(0xFF1B4D3E))
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1B4D3E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildModernInput(
                controller: _usernameController,
                label: 'ARTISAN NAME',
                icon: Icons.person_outline_rounded,
                validator: (value) => (value != null && value.length > 255) ? 'Too long' : null,
              ),
              const SizedBox(height: 20),
              _buildModernInput(
                controller: _bioController,
                label: 'CULINARY PHILOSOPHY',
                icon: Icons.auto_awesome_rounded,
                maxLines: 4,
                validator: (value) => (value != null && value.length > 500) ? 'Too long' : null,
              ),
              const SizedBox(height: 20),
              _buildModernInput(
                controller: _locationController,
                label: 'HEADQUARTERS',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 20),
              _buildModernInput(
                controller: _websiteController,
                label: 'FOLIO / WEBSITE',
                icon: Icons.language_rounded,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4D3E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('SAVE IDENTITY', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.5, color: Color(0xFFE1B12C))),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1B4D3E), fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFF1B4D3E).withOpacity(0.3), size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }
}
