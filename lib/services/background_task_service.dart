import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';
import 'math_solver_service.dart';
import '../models/math_problem.dart';

/// Service for managing background math solving tasks
class BackgroundTaskService {
  static final BackgroundTaskService _instance = BackgroundTaskService._internal();
  factory BackgroundTaskService() => _instance;
  BackgroundTaskService._internal();

  static const String _mathSolvingTaskName = 'math_solving_task';
  bool _isInitialized = false;

  /// Initialize the background task service
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('Initializing BackgroundTaskService...');

    try {
      // First initialize WorkManager
      await Workmanager().initialize(
        _callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      
      _isInitialized = true;
      
      // Cancel any pending background tasks from previous app sessions
      // to prevent automatic solving on app startup
      print('Cancelling any pending background tasks from previous sessions...');
      try {
        await Workmanager().cancelAll();
        print('All background tasks cancelled successfully');
      } catch (cancelError) {
        print('Error cancelling background tasks: $cancelError');
      }
      
      print('BackgroundTaskService initialized successfully');
    } catch (e) {
      print('Error initializing BackgroundTaskService: $e');
    }
  }

  /// Start a background math solving task
  Future<void> startBackgroundSolving({
    required String problemId,
    required String problemText,
    required String problemType, // 'image', 'text', 'imageWithText'
    String? imagePath, // File path instead of base64 to avoid 10KB limit
    String? userQuestion,
  }) async {
    if (!_isInitialized) {
      print('BackgroundTaskService not initialized');
      return;
    }

    try {
      print('Starting background solving task for problem: $problemId');

      // Show progress notification
      await NotificationService().showSolvingProgressNotification(
        problemTitle: problemText.length > 50 ? '${problemText.substring(0, 50)}...' : problemText,
        status: 'Initializing...',
        problemId: problemId,
      );

      // Register the background task
      // Build input data map, only including non-null values to avoid WorkManager null handling issues
      final Map<String, dynamic> inputData = {
        'problemId': problemId,
        'problemText': problemText,
        'problemType': problemType,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Only add optional parameters if they're not null
      if (imagePath != null) {
        inputData['imagePath'] = imagePath; // Pass file path instead of base64
      }
      if (userQuestion != null) {
        inputData['userQuestion'] = userQuestion;
      }
      
      await Workmanager().registerOneOffTask(
        problemId, // Unique task ID
        _mathSolvingTaskName,
        inputData: inputData,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      print('Background solving task registered successfully');
    } catch (e) {
      print('Error starting background solving task: $e');
      
      // Show error notification
      await NotificationService().showSolvingFailedNotification(
        problemTitle: problemText.length > 50 ? '${problemText.substring(0, 50)}...' : problemText,
        errorMessage: 'Failed to start background task: $e',
        problemId: problemId,
      );
    }
  }

  /// Cancel a background solving task
  Future<void> cancelBackgroundSolving(String problemId) async {
    if (!_isInitialized) return;

    try {
      await Workmanager().cancelByUniqueName(problemId);
      await NotificationService().cancelProgressNotification();
      print('Background solving task cancelled: $problemId');
    } catch (e) {
      print('Error cancelling background solving task: $e');
    }
  }

  /// Cancel all background solving tasks
  Future<void> cancelAllBackgroundTasks() async {
    if (!_isInitialized) return;

    try {
      await Workmanager().cancelAll();
      await NotificationService().cancelProgressNotification();
      print('All background solving tasks cancelled');
    } catch (e) {
      print('Error cancelling all background tasks: $e');
    }
  }

  /// Check if background tasks are supported on this platform
  bool isBackgroundTaskSupported() {
    // Background tasks are supported on Android and iOS
    return defaultTargetPlatform == TargetPlatform.android || 
           defaultTargetPlatform == TargetPlatform.iOS;
  }
}

/// Background task callback dispatcher
/// This function runs in a separate isolate for background processing
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('Background task started: $task');
    print('Input data: $inputData');

    try {
      if (task == BackgroundTaskService._mathSolvingTaskName) {
        return await _handleMathSolvingTask(inputData);
      }
      
      return Future.value(true);
    } catch (e) {
      print('Error in background task: $e');
      return Future.value(false);
    }
  });
}

/// Handle math solving in background with true background processing
/// This runs in a separate isolate and performs actual math solving
Future<bool> _handleMathSolvingTask(Map<String, dynamic>? inputData) async {
  if (inputData == null) {
    print('No input data provided for math solving task');
    return false;
  }

  try {
    final String problemId = inputData['problemId'] ?? '';
    final String problemText = inputData['problemText'] ?? '';
    final String problemType = inputData['problemType'] ?? 'text';
    final String? imagePath = inputData['imagePath']; // File path instead of base64
    final String? userQuestion = inputData['userQuestion'];

    print('🔄 TRUE BACKGROUND SOLVING started for problem: $problemId');
    print('Problem type: $problemType');
    print('Problem text length: ${problemText.length}');
    print('Has image path: ${imagePath != null}');
    print('Has user question: ${userQuestion != null}');

    // Initialize services in background isolate
    final notificationService = NotificationService();
    await notificationService.initialize();

    // Show progress notification
    await notificationService.showSolvingProgressNotification(
      problemTitle: problemText.length > 50 ? '${problemText.substring(0, 50)}...' : problemText,
      status: 'Solving in background...',
      problemId: problemId,
    );

    // Initialize background math solver service
    final backgroundSolver = MathSolverService();
    await backgroundSolver.initialize();
    
    print('✅ Background Gemma model initialized successfully');

    // Perform actual solving based on problem type
    MathProblem? solvedProblem;
    
    switch (problemType) {
      case 'text':
        print('📝 Solving text problem in true background...');
        solvedProblem = await backgroundSolver.solveFromText(problemText);
        break;
        
      case 'image':
        if (imagePath != null) {
          print('🖼️ Solving image problem in true background...');
          final imageBytes = await _readImageFromFile(imagePath);
          solvedProblem = await backgroundSolver.solveFromImage(imageBytes);
        } else {
          throw Exception('Image path missing for image problem');
        }
        break;
        
      case 'imageWithText':
        if (imagePath != null && userQuestion != null) {
          print('🖼️📝 Solving mixed problem in true background...');
          final imageBytes = await _readImageFromFile(imagePath);
          solvedProblem = await backgroundSolver.solveFromImageWithText(imageBytes, userQuestion);
        } else {
          throw Exception('Image path or user question missing for mixed problem');
        }
        break;
        
      default:
        throw Exception('Unknown problem type: $problemType');
    }

    if (solvedProblem != null) {
      print('✅ Background solving completed successfully!');
      print('Solution length: ${solvedProblem.solution?.length ?? 0} characters');
      
      // Send completion notification
      await notificationService.showSolvingCompletedNotification(
        problemTitle: solvedProblem.title ?? problemText.substring(0, math.min(50, problemText.length)),
        answer: solvedProblem.solution ?? 'Solution completed',
        problemId: problemId,
      );
      
      print('✅ Background completion notification sent');
      return true;
    } else {
      throw Exception('Solving returned null result');
    }

  } catch (e) {
    print('❌ Error in true background solving: $e');
    
    // Send failure notification
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      await notificationService.showSolvingFailedNotification(
        problemTitle: 'Math Problem',
        errorMessage: 'Background solving failed: $e',
        problemId: inputData?['problemId'] ?? '',
      );
    } catch (notificationError) {
      print('Failed to send error notification: $notificationError');
    }
    
    return false;
  }
}

/// Read image data from file path
Future<Uint8List> _readImageFromFile(String imagePath) async {
  try {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image file not found at path: $imagePath');
    }
    final imageBytes = await file.readAsBytes();
    print('✅ Successfully read ${imageBytes.length} bytes from image file');
    return imageBytes;
  } catch (e) {
    print('❌ Error reading image from file: $e');
    throw Exception('Failed to read image file: $e');
  }
}

