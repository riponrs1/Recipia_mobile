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
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 50,
                  backgroundImage: _avatarImage != null
                      ? FileImage(_avatarImage!)
                      : (currentAvatarUrl != null
                          ? CachedNetworkImageProvider(
                              ApiService.getImageUrl(currentAvatarUrl))
                          : null) as ImageProvider?,
                  child: (_avatarImage == null && currentAvatarUrl == null)
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: const Text('Change Avatar'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                    labelText: 'Username', border: OutlineInputBorder()),
                validator: (value) {
                  // Basic validation, uniqueness checked by server
                  if (value != null && value.length > 255) {
                    return 'Username too long';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                    labelText: 'Bio', border: OutlineInputBorder()),
                maxLines: 3,
                validator: (value) =>
                    value != null && value.length > 500 ? 'Bio too long' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                    labelText: 'Location', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                    labelText: 'Website', border: OutlineInputBorder()),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
