import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Manager for Gemma model download and initialization
class GemmaModelManager {
  static final GemmaModelManager _instance = GemmaModelManager._internal();
  factory GemmaModelManager() => _instance;
  GemmaModelManager._internal();

  bool _isInitialized = false;
  String? _modelPath;
  
  /// Initialize the model manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('🚀 Initializing GemmaModelManager');
    _isInitialized = true;
  }

  /// Ensure the model is downloaded and available
  Future<String> ensureModelDownloaded() async {
    if (!_isInitialized) await initialize();
    
    // Check if model is already available locally
    final localPath = await _getLocalModelPath();
    if (await _isValidModelFile(localPath)) {
      debugPrint('✅ Model already available at: $localPath');
      _modelPath = localPath;
      return localPath;
    }
    
    // Try to find model in common locations
    final foundPath = await _findExistingModel();
    if (foundPath != null) {
      debugPrint('✅ Found existing model at: $foundPath');
      // Copy to app directory for consistent access
      await _copyModelToAppDirectory(foundPath);
      return _modelPath!;
    }
    
    throw Exception('Model not found. Please ensure the Gemma model file is available in the app directory or Download folder.');
  }

  /// Get the expected local model path
  Future<String> _getLocalModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/gemma-3n-E4B-it-int4.task';
  }

  /// Check if a model file is valid
  Future<bool> _isValidModelFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      
      final stat = await file.stat();
      if (stat.size < 1000000) return false; // Model should be at least 1MB
      
      // Check if it's a valid model file by reading the header
      final bytes = await file.openRead(0, 16).first;
      
      // Look for ZIP header (models might be compressed)
      for (int i = 0; i <= bytes.length - 4; i++) {
        if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && 
            bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04) {
          debugPrint('✅ Valid ZIP header found at offset $i');
          return true;
        }
      }
      
      // Also accept files that might be raw model files
      if (stat.size > 100000000) { // Large files are likely model files
        debugPrint('✅ Large file detected, assuming valid model');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Error validating model file: $e');
      return false;
    }
  }

  /// Find existing model in common locations
  Future<String?> _findExistingModel() async {
    final possiblePaths = await _getCommonModelPaths();
    
    for (final path in possiblePaths) {
      debugPrint('🔍 Checking for model at: $path');
      if (await _isValidModelFile(path)) {
        debugPrint('✅ Found valid model at: $path');
        return path;
      }
    }
    
    return null;
  }

  /// Get common paths where the model might be located
  Future<List<String>> _getCommonModelPaths() async {
    final paths = <String>[];
    
    try {
      // App-specific external files directory
      final appDir = await getExternalStorageDirectory();
      if (appDir != null) {
        paths.add('${appDir.path}/gemma-3n-E4B-it-int4.task');
        paths.add('${appDir.path}/gemma_model.task');
      }
      
      // Common download locations on Android
      paths.addAll([
        '/storage/emulated/0/Download/gemma-3n-E4B-it-int4.task',
        '/storage/emulated/0/Downloads/gemma-3n-E4B-it-int4.task',
        '/sdcard/Download/gemma-3n-E4B-it-int4.task',
        '/sdcard/Downloads/gemma-3n-E4B-it-int4.task',
      ]);
      
      // App-accessible directory (where we manually placed it)
      final appAccessibleDir = '/storage/emulated/0/Android/data/com.gerfalcon.example.gemmatry/files';
      paths.add('$appAccessibleDir/gemma-3n-E4B-it-int4.task');
      
    } catch (e) {
      debugPrint('❌ Error getting storage directories: $e');
    }
    
    return paths;
  }

  /// Copy model from found location to app directory
  Future<void> _copyModelToAppDirectory(String sourcePath) async {
    try {
      debugPrint('📋 Copying model to app directory...');
      final targetPath = await _getLocalModelPath();
      
      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);
      
      // Ensure target directory exists
      await targetFile.parent.create(recursive: true);
      
      // Copy file
      await sourceFile.copy(targetPath);
      
      // Verify copy
      if (await _isValidModelFile(targetPath)) {
        debugPrint('✅ Model successfully copied to: $targetPath');
        _modelPath = targetPath;
        
        // Model path is now ready for flutter_gemma to use
        debugPrint('✅ Model ready for flutter_gemma initialization');
      } else {
        throw Exception('Copied model file is invalid');
      }
      
    } catch (e) {
      debugPrint('❌ Error copying model: $e');
      throw Exception('Failed to copy model to app directory: $e');
    }
  }

  /// Get the current model path
  String? get modelPath => _modelPath;
  
  /// Check if model is ready
  bool get isModelReady => _modelPath != null;
}

/// Exception thrown by model manager
class ModelManagerException implements Exception {
  final String message;
  ModelManagerException(this.message);
  
  @override
  String toString() => 'ModelManagerException: $message';
}
