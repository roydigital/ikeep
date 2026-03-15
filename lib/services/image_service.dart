import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/storage_constants.dart';
import '../core/errors/app_exception.dart';

/// Wraps [ImagePicker] and handles saving images to the app's local directory.
class ImageService {
  ImageService() : _picker = ImagePicker();

  final ImagePicker _picker;

  Future<Directory> _imagesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, StorageConstants.itemImagesDir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    await dir.create(recursive: true);
    return dir;
  }

  /// Picks a single photo from the camera and saves it locally.
  Future<String> pickFromCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw const PermissionException('Camera permission denied');
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: AppConstants.imageCompressionQuality,
    );
    if (file == null) throw const ImageException('No image captured');
    return _saveToLocalStorage(file);
  }

  /// Picks a single photo from the gallery.
  Future<String> pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: AppConstants.imageCompressionQuality,
    );
    if (file == null) throw const ImageException('No image selected');
    return _saveToLocalStorage(file);
  }

  /// Picks multiple photos from the gallery (up to [AppConstants.maxImagesPerItem]).
  Future<List<String>> pickMultipleFromGallery() async {
    final files = await _picker.pickMultiImage(
      imageQuality: AppConstants.imageCompressionQuality,
      limit: AppConstants.maxImagesPerItem,
    );
    if (files.isEmpty) return [];
    final saved = <String>[];
    for (final file in files) {
      saved.add(await _saveToLocalStorage(file));
    }
    return saved;
  }

  /// Copies a picked [XFile] into the app's images directory with a unique name.
  Future<String> _saveToLocalStorage(XFile file) async {
    final dir = await _imagesDir();
    final ext = p.extension(file.path).isNotEmpty ? p.extension(file.path) : '.jpg';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(dir.path, fileName);
    await File(file.path).copy(destPath);
    return destPath;
  }

  /// Deletes a local image file. Silently ignores if not found.
  Future<void> deleteImage(String imagePath) async {
    final file = File(imagePath);
    if (file.existsSync()) await file.delete();
  }

  /// Deletes all images in a list of paths.
  Future<void> deleteImages(List<String> imagePaths) async {
    for (final path in imagePaths) {
      await deleteImage(path);
    }
  }
}
