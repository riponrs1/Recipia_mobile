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
            toolbarColor: const Color(0xFF1B4D3E),
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
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Edit profile',
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(30),
                              image: (_avatarImage != null ||
                                      currentAvatarUrl != null)
                                  ? DecorationImage(
                                      image: _avatarImage != null
                                          ? FileImage(_avatarImage!)
                                          : CachedNetworkImageProvider(
                                                  ApiService.getImageUrl(
                                                      currentAvatarUrl!))
                                              as ImageProvider,
                                      fit: BoxFit.cover)
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: (_avatarImage == null &&
                                    currentAvatarUrl == null)
                                ? const Icon(Icons.person_rounded,
                                    size: 48, color: Colors.white)
                                : null,
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                    color: _accent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: _bg, width: 2)),
                                child: const Icon(Icons.camera_alt_rounded,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: _pickImage,
                        child: const Text('Change photo',
                            style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _input(_usernameController, 'Username',
                        validator: (v) => (v != null && v.length > 255)
                            ? 'Too long'
                            : null),
                    const SizedBox(height: 16),
                    _input(_bioController, 'Bio',
                        maxLines: 4,
                        validator: (v) => (v != null && v.length > 500)
                            ? 'Too long'
                            : null),
                    const SizedBox(height: 16),
                    _input(_locationController, 'Location'),
                    const SizedBox(height: 16),
                    _input(_websiteController, 'Website',
                        keyboardType: TextInputType.url),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white))
                  : const Text('Save changes',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input(TextEditingController controller, String label,
      {int maxLines = 1,
      String? Function(String?)? validator,
      TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _muted)),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 15, color: _fg),
          decoration: InputDecoration(
            filled: true,
            fillColor: _surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _accent, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);
