import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'background_task_service.dart';
import 'notification_service.dart';
import 'database_service.dart';
import '../data/model_manager.dart';
import '../models/math_problem.dart';
import '../models/chat_message.dart';

/// Callback for status updates during problem solving
typedef StatusCallback = void Function(String status);

/// Service for solving math problems using Gemma model
class MathSolverService {
  static final MathSolverService _instance = MathSolverService._internal();
  factory MathSolverService() => _instance;
  MathSolverService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final GemmaModelManager _modelManager = GemmaModelManager();
  
  InferenceModel? _inferenceModel;
  bool _isInitialized = false;
  
  // Storage for essential context for follow-up questions (not full chat history)
  final Map<String, Map<String, dynamic>> _problemContexts = {};
  
  // Track active chat instances for proper cleanup
  final Set<dynamic> _activeChatInstances = {};
  
  // Essential context storage for follow-up questions
  final Map<String, Map<String, dynamic>> _essentialContexts = {};
  
  // Solving state management for seamless background/foreground transitions
  String? _currentSolvingProblemId;
  String? _lastProcessedProblemId; // Track last processed problem for cross-contamination prevention
  dynamic _currentSolvingChat;
  Stream<String>? _currentSolvingStream;
  StreamSubscription<String>? _currentStreamSubscription;
  String _accumulatedResponse = '';
  bool _isSolvingPaused = false;

  // Background processing support
  final BackgroundTaskService _backgroundTaskService = BackgroundTaskService();
  final NotificationService _notificationService = NotificationService();
  bool _backgroundServicesInitialized = false;
  bool _isBackgroundMode = false;

  /// Clean up all active chat instances to free memory
  void _cleanupChatInstances() {
    print('🧹 Cleaning up ${_activeChatInstances.length} active chat instances...');
    try {
      for (final chat in _activeChatInstances) {
        // Try to dispose if the chat has a dispose method
        if (chat != null) {
          try {
            // Note: flutter_gemma chat instances don't have explicit dispose,
            // but we clear our references to allow garbage collection
            print('Clearing reference to chat instance');
          } catch (e) {
            print('Warning: Could not dispose chat instance: $e');
          }
        }
      }
      _activeChatInstances.clear();
      
      // Also clear the current solving chat reference
      _currentSolvingChat = null;
      
      print('✅ Chat cleanup completed');
    } catch (e) {
      print('Warning: Error during chat cleanup: $e');
    }
  }
  
  /// Reset the inference model completely for a new problem
  Future<void> _resetModelForNewProblem() async {
    print('🔄 Resetting inference model for new problem...');
    
    try {
      // Close existing model if it exists
      if (_inferenceModel != null) {
        print('🔒 Closing existing inference model...');
        await _inferenceModel!.close();
        _inferenceModel = null;
        print('✅ Inference model closed');
      }
      
      // Clear any chat references
      _cleanupChatInstances();
      
      // Force garbage collection
      _forceGarbageCollection();
      
      // Mark as uninitialized to force re-initialization
      _isInitialized = false;
      
      // Re-initialize the model
      await initialize();
      
      print('✅ Model reset and re-initialized successfully');
      
    } catch (e) {
      print('❌ Error during model reset: $e');
      // Ensure we're marked as uninitialized if reset fails
      _isInitialized = false;
      _inferenceModel = null;
      throw MathSolverException('Failed to reset model: $e');
    }
  }

  /// Force garbage collection to free memory
  void _forceGarbageCollection() {
    print('🗑️ Forcing garbage collection...');
    // Clear any remaining references
    _activeChatInstances.clear();
    // Suggest garbage collection (Dart will decide when to actually run it)
    print('Garbage collection suggested');
  }

  /// Initialize background services for notifications and background tasks
  Future<void> initializeBackgroundServices() async {
    await _initializeBackgroundServices();
  }

  /// Get problem by ID from database
  Future<MathProblem?> getProblemById(String problemId) async {
    try {
      return await _databaseService.getMathProblem(problemId);
    } catch (e) {
      print('Error retrieving problem by ID: $e');
      return null;
    }
  }

  /// Enable seamless background solving without interrupting current process
  Future<void> continueInBackground(String problemText, {Uint8List? imageBytes, String? problemId}) async {
    try {
      print('🔄 Setting up seamless background continuation (no interruption)...');
      
      // Get or create problem ID for tracking
      final actualProblemId = problemId ?? _currentSolvingProblemId ?? const Uuid().v4();
      
      // Initialize background services for notifications
      await _initializeBackgroundServices();
      
      // Show notification that solving continues in background
      await _notificationService.showSolvingProgressNotification(
        problemTitle: problemText.isNotEmpty ? problemText : 'Image-based math problem',
        status: 'Solving continues in background...',
        problemId: actualProblemId,
      );
      
      // Mark that we're now in background mode (but don't pause solving)
      _isBackgroundMode = true;
      _currentSolvingProblemId = actualProblemId;
      
      // Save current state for potential recovery (but don't interrupt)
      await _saveSolvingState({
        'problemId': actualProblemId,
        'problemText': problemText,
        'imageBytes': imageBytes,
        'isBackgroundMode': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('✅ Background continuation enabled - solving continues uninterrupted');
      
    } catch (e) {
      print('❌ Error setting up seamless background continuation: $e');
      rethrow;
    }
  }
  
  /// Save solving state for background continuation
  Future<void> _saveSolvingState(Map<String, dynamic> state) async {
    // For now, we'll use a simple approach - in a full implementation,
    // you might want to use shared_preferences or a dedicated state store
    print('Saving solving state: ${state.keys.join(", ")}');
    // Implementation would save to persistent storage accessible by background isolate
  }
  
  /// Reset background mode after solving completion
  void _resetBackgroundMode() {
    print('🔄 Resetting background mode after solving completion');
    _isBackgroundMode = false;
    _currentSolvingProblemId = null;
    
    // Cancel any progress notifications
    try {
      _notificationService.cancelProgressNotification();
    } catch (e) {
      print('⚠️ Failed to cancel progress notification during reset: $e');
    }
  }
  
  /// Resume solving from saved state when app returns to foreground
  Future<void> resumeFromBackground(String problemId) async {
    try {
      print('🔄 Resuming from background for problem: $problemId');
      
      // First check if we have an active solving stream (most reliable indicator)
      if (_currentStreamSubscription != null && !_currentStreamSubscription!.isPaused && _isBackgroundMode) {
        print('✅ Active solving stream detected - background solving is continuing');
        print('🔄 Seamlessly continuing from background mode');
        _currentSolvingProblemId = problemId;
        return;
      }
      
      // Check if the problem was completed in background
      final problem = await _databaseService.getMathProblem(problemId);
      if (problem?.status == ProblemStatus.solved) {
        print('✅ Background solving completed successfully');
        // Reset background mode since solving is complete
        _isBackgroundMode = false;
        _currentSolvingProblemId = null;
        
        // Cancel any progress notifications
        try {
          await _notificationService.cancelProgressNotification();
        } catch (e) {
          print('⚠️ Failed to cancel progress notification: $e');
        }
        
        return;
      }
      
      // If we're in background mode but no active stream, check if solving is still in progress
      if (_isBackgroundMode && _currentSolvingProblemId == problemId) {
        print('🔄 Background mode active for this problem - continuing seamlessly');
        return;
      }
      
      // If solving is still in progress based on database status
      if (problem?.status == ProblemStatus.solving) {
        print('🔄 Database shows solving in progress - continuing seamlessly');
        _currentSolvingProblemId = problemId;
        return;
      }
      
      // If we reach here, background solving may have failed or completed without proper status update
      print('⚠️ Background solving status unclear - may have completed or failed');
      if (_isBackgroundMode) {
        print('🔄 Keeping background mode active as solving may still be in progress');
        _currentSolvingProblemId = problemId;
      } else {
        print('❌ No active background solving detected');
      }
      
    } catch (e) {
      print('❌ Error resuming from background: $e');
      // Don't reset background mode on error - solving might still be active
      print('⚠️ Keeping background mode active despite error to avoid interrupting solving');
    }
  }

  /// Internal method to initialize background services
  Future<void> _initializeBackgroundServices() async {
    if (_backgroundServicesInitialized) return;
    
    try {
      print('Initializing background services...');
      await _notificationService.initialize();
      await _backgroundTaskService.initialize();
      _backgroundServicesInitialized = true;
      print('Background services initialized successfully');
    } catch (e) {
      print('Warning: Failed to initialize background services: $e');
      // Continue without background services if initialization fails
    }
  }

  /// Solve problem in main app process (continues when backgrounded)
  void _solveInMainProcess(String problemId, Uint8List? imageBytes, String? userQuestion, String problemType) {
    // Run solving asynchronously without blocking
    () async {
      try {
        print('🔄 Starting main process solving for problem: $problemId');
        
        // Get the original problem from database
        final originalProblem = await _databaseService.getMathProblem(problemId);
        if (originalProblem == null) {
          throw Exception('Problem not found in database: $problemId');
        }
        
        // Show progress notification
        await _notificationService.showSolvingProgressNotification(
          problemTitle: 'Math Problem',
          status: 'Solving in progress...',
          problemId: problemId,
        );
        
        MathSolution solution;
        String? extractedQuestion;
        
        // Solve based on problem type - use internal solving methods to avoid creating new problems
        switch (problemType) {
          case 'image':
            if (imageBytes != null) {
              print('🖼️ Solving image problem in background...');
              // For image problems, we need to extract first then solve
              final extractionResult = await _extractQuestionWithGemmaAndChat(imageBytes);
              extractedQuestion = extractionResult['question'] as String;
              final extractionChat = extractionResult['chat'];
              solution = await _solveWithExistingChatOptimized(extractedQuestion, extractionChat, imageBytes: imageBytes);
            } else {
              throw Exception('Image bytes not available for image problem');
            }
            break;
          case 'text':
            print('📝 Solving text problem in background...');
            solution = await _solveWithFreshChat(originalProblem.originalInput);
            break;
          case 'imageWithText':
            if (imageBytes != null && userQuestion != null) {
              print('🖼️📝 Solving mixed problem in background...');
              solution = await _solveWithFreshChat(userQuestion, imageBytes: imageBytes);
            } else {
              throw Exception('Image bytes or user question not available for mixed problem');
            }
            break;
          default:
            throw Exception('Unknown problem type: $problemType');
        }
        
        // Update the original problem with the solution
        final updatedProblem = originalProblem.copyWith(
          extractedText: problemType == 'image' ? (extractedQuestion ?? originalProblem.originalInput) : originalProblem.originalInput,
          solution: solution.answer,
          stepByStepExplanation: solution.explanation,
          status: ProblemStatus.solved,
        );
        await _databaseService.updateMathProblem(updatedProblem);
        
        // Store essential context for follow-up questions
        _storeEssentialContext(problemId, originalProblem.originalInput, solution, imageBytes);
        
        // Cancel progress notification and show completion
        await _notificationService.cancelProgressNotification();
        await _notificationService.showSolvingCompletedNotification(
          problemTitle: originalProblem.originalInput.length > 50 
              ? '${originalProblem.originalInput.substring(0, 50)}...' 
              : originalProblem.originalInput,
          answer: solution.answer ?? 'Solution completed',
          problemId: problemId,
        );
        
        print('✅ Main process solving completed for problem: $problemId');
        
      } catch (e) {
        print('❌ Error in main process solving: $e');
        
        // Show error notification
        try {
          await _notificationService.cancelProgressNotification();
          await _notificationService.showSolvingFailedNotification(
            problemTitle: 'Math Problem',
            errorMessage: e.toString(),
            problemId: problemId,
          );
          
          // Update problem status to error
          final problem = await _databaseService.getMathProblem(problemId);
          if (problem != null) {
            final failedProblem = problem.copyWith(status: ProblemStatus.error);
            await _databaseService.updateMathProblem(failedProblem);
          }
        } catch (notificationError) {
          print('Error showing failure notification: $notificationError');
        }
      }
    }();
  }

  /// Initialize the math solver service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize model manager
      await _modelManager.initialize();
      
      // Ensure model is downloaded
      final modelPath = await _modelManager.ensureModelDownloaded();
      debugPrint('🔧 Model path obtained: $modelPath');
      
      // Register model path with flutter_gemma's ModelFileManager
      final gemma = FlutterGemmaPlugin.instance;
      final modelManager = gemma.modelManager;
      await modelManager.setModelPath(modelPath);
      debugPrint('✅ Model path registered with flutter_gemma');
      
      // Create inference model using flutter_gemma (GPU acceleration via TensorFlow Lite delegates)
      _inferenceModel = await gemma.createModel(
        modelType: ModelType.gemmaIt,
        supportImage: true,
        maxTokens: 4096,
      );
      debugPrint('✅ Inference model created successfully');
      
      _isInitialized = true;
    } catch (e) {
      debugPrint('❌ Failed to initialize math solver: $e');
      throw MathSolverException('Failed to initialize math solver: $e');
    }
  }

  /// Solve a math problem from image with user-provided text question
  Future<MathProblem> solveFromImageWithText(Uint8List imageBytes, String userQuestion, {StatusCallback? onStatusUpdate}) async {
    // Reset the inference model for a fresh start
    await _resetModelForNewProblem();
    
    try {
      onStatusUpdate?.call('Preparing your question...');
      debugPrint('🖼️📝 Solving problem from image with user question');
      debugPrint('User question: $userQuestion');
      debugPrint('Image size: ${imageBytes.length} bytes');
      
      // Create problem record with mixed input type
      final problemId = const Uuid().v4();
      final problem = MathProblem(
        id: problemId,
        originalInput: userQuestion, // Store user's text question as original input
        inputType: ProblemInputType.image, // Still image type since image is primary
        imageBase64: _encodeImageToBase64(imageBytes),
        createdAt: DateTime.now(),
        status: ProblemStatus.solving,
      );
      
      // Save initial problem to database
      await _databaseService.saveMathProblem(problem);
      debugPrint('✅ Problem saved to database with ID: $problemId');
      
      onStatusUpdate?.call('Analyzing image and question...');
      debugPrint('🤖 Using enhanced solving approach for mixed input');
      
      // Use the enhanced solving approach with fresh chat and improved prompt
      final solution = await _solveWithFreshChat(userQuestion, imageBytes: imageBytes);
      
      debugPrint('📝 Received solution: ${solution.answer}');
      // Use extraction output directly as title
      final generatedTitle = userQuestion;
      
      // Store essential context for follow-up questions (no chat instance since we use fresh chats)
      _storeEssentialContext(problemId, userQuestion, solution, imageBytes);
      
      // Update problem with solution and title
      final solvedProblem = MathProblem(
        id: problemId,
        originalInput: userQuestion,
        extractedText: userQuestion, // Set extracted text to user's question
        solution: solution.answer,
        stepByStepExplanation: solution.explanation,
        title: generatedTitle,
        createdAt: problem.createdAt,
        inputType: ProblemInputType.image,
        imageBase64: problem.imageBase64,
        status: ProblemStatus.solved,
      );
      
      await _databaseService.updateMathProblem(solvedProblem);
      debugPrint('✅ Problem updated with solution');
      
      // Reset background mode if solving was done in background
      if (_isBackgroundMode) {
        _resetBackgroundMode();
      }
      
      return solvedProblem;
      
    } catch (e) {
      debugPrint('❌ Error in solveFromImageWithText: $e');
      throw MathSolverException('Failed to solve problem from image with text: $e');
    }
  }

  /// Solve math problem from text input
  Future<MathProblem> solveFromText(String problemText, {StatusCallback? onStatusUpdate}) async {
    // Reset the inference model for a fresh start
    await _resetModelForNewProblem();
    
    try {
      onStatusUpdate?.call('Preparing problem for solving...');
      
      // Create initial problem record
      final problem = MathProblem(
        originalInput: problemText,
        inputType: ProblemInputType.text,
        extractedText: problemText,
        status: ProblemStatus.solving,
      );
      
      // Save to database
      await _databaseService.saveMathProblem(problem);
      
      onStatusUpdate?.call('Analyzing problem structure...');
      
      // Solve the problem using fresh chat to avoid context overload
      final solution = await _solveWithFreshChat(problemText);
      
      // Generate title from text directly (no separate Gemma call)
      String? generatedTitle;
      try {
        generatedTitle = _extractTitleFromText(problemText);
        print('Generated title from text: $generatedTitle');
      } catch (e) {
        print('Title extraction failed: $e');
        // Continue without title - not critical for solving
      }
      
      // Update problem with solution and title
      final solvedProblem = problem.copyWith(
        solution: solution.answer,
        stepByStepExplanation: solution.explanation,
        title: generatedTitle,
        status: ProblemStatus.solved,
      );
      
      await _databaseService.updateMathProblem(solvedProblem);
      
      // Store essential context for follow-up questions (no image for text problems)
      _storeEssentialContext(problem.id, problemText, solution, null);
      print('Stored essential context for text problem ID: ${problem.id}');
      
      // Reset background mode if solving was done in background
      if (_isBackgroundMode) {
        _resetBackgroundMode();
      }
      
      return solvedProblem;
      
    } catch (e) {
      // Update problem status to error
      final errorProblem = MathProblem(
        originalInput: problemText,
        inputType: ProblemInputType.text,
        extractedText: problemText,
        status: ProblemStatus.error,
      );
      
      await _databaseService.saveMathProblem(errorProblem);
      throw MathSolverException('Failed to solve problem from text: $e');
    }
  }

  /// Solve math problem from image using Gemma-only extraction
  Future<MathProblem> solveFromImage(Uint8List imageBytes, {StatusCallback? onStatusUpdate}) async {
    // Reset the inference model for a fresh start
    await _resetModelForNewProblem();
    
    try {
      onStatusUpdate?.call('Analyzing image content...');
      // Extract question directly using Gemma with structured prompt
      print('=== GEMMA-ONLY EXTRACTION ===');
      print('Bypassing OCR, using Gemma directly for question extraction');
      
      final extractionResult = await _extractQuestionWithGemmaAndChat(imageBytes);
      final extractedQuestion = extractionResult['question'] as String;
      final extractionChat = extractionResult['chat'];
      
      print('Gemma extraction completed');
      print('Extracted question length: ${extractedQuestion.length} characters');
      print('========================');
      
      // Validate extraction
      if (extractedQuestion.isEmpty || extractedQuestion.length < 10) {
        throw MathSolverException('Gemma extraction failed or returned insufficient content');
      }
      
      onStatusUpdate?.call('Problem extracted, preparing solution...');
      
      print('=== CREATING PROBLEM RECORD ===');
      // Create initial problem record
      final problem = MathProblem(
        originalInput: 'Image-based problem',
        inputType: ProblemInputType.image,
        extractedText: extractedQuestion,
        latexFormat: '', // Will be generated during solving if needed
        status: ProblemStatus.solving,
        imageBase64: _encodeImageToBase64(imageBytes),
      );
      
      print('=== SAVING TO DATABASE ===');
      // Save to database
      await _databaseService.saveMathProblem(problem);
      print('Problem saved to database with ID: ${problem.id}');
      
      onStatusUpdate?.call('Solving problem step by step...');
      
      print('=== STARTING SOLVING STEP ===');
      print('Cleaning up extraction chat to free memory before creating solving chat...');
      
      // Clean up the extraction chat instance to free memory before creating a fresh one
      if (extractionChat != null) {
        _activeChatInstances.remove(extractionChat);
        print('Removed extraction chat from active instances');
      }
      
      // Force cleanup of any accumulated chat instances
      _cleanupChatInstances();
      _forceGarbageCollection();
      
      print('Using optimized existing chat approach to avoid resource exhaustion...');
      print('Adding role-clearing mechanism to prevent extraction/solving confusion');
      
      // Use existing extraction chat with role-clearing approach (more memory efficient)
      final solution = await _solveWithExistingChatOptimized(extractedQuestion, extractionChat, imageBytes: imageBytes, onStatusUpdate: onStatusUpdate);
      print('Solving completed successfully with optimized existing chat approach');
      
      // Generate title from extraction output directly (no separate Gemma call)
      String? generatedTitle;
      try {
        generatedTitle = _extractTitleFromText(extractedQuestion);
        print('Generated title from extraction: $generatedTitle');
      } catch (e) {
        print('Title extraction failed: $e');
        // Continue without title - not critical for solving
      }
      
      // Update problem with solution and title
      final solvedProblem = problem.copyWith(
        solution: solution.answer,
        stepByStepExplanation: solution.explanation,
        title: generatedTitle,
        status: ProblemStatus.solved,
      );
      
      await _databaseService.updateMathProblem(solvedProblem);
      
      // Store essential context for follow-up questions (not the full chat history)
      _storeEssentialContext(problem.id, extractedQuestion, solution, imageBytes);
      print('Stored essential context for follow-up questions for problem ID: ${problem.id}');
      
      // Send background completion notification and reset background mode if solving was done in background
      if (_isBackgroundMode) {
        try {
          await _notificationService.showSolvingCompletedNotification(
            problemTitle: solvedProblem.title ?? 'Image-based math problem',
            answer: solution.answer ?? 'Solution completed',
            problemId: solvedProblem.id,
          );
          print('✅ Background completion notification sent for image problem');
        } catch (e) {
          print('⚠️ Failed to send background completion notification: $e');
        }
        _resetBackgroundMode();
      }
      
      return solvedProblem;
      
    } catch (e) {
      // Update problem status to error
      final errorProblem = MathProblem(
        originalInput: 'Error processing image',
        inputType: ProblemInputType.image,
        extractedText: 'Error processing image',
        status: ProblemStatus.error,
        imageBase64: _encodeImageToBase64(imageBytes),
      );
      
      await _databaseService.saveMathProblem(errorProblem);
      throw MathSolverException('Failed to solve problem from image: $e');
    }
  }

  /// Clean up OCR text by removing answer choices and formatting issues
  String _cleanupOCRText(String text, List<String> answerChoices) {
    String cleaned = text;
    
    // Remove answer choices (A), B), C), D), E) or 1), 2), 3), 4), 5)
    cleaned = cleaned.replaceAll(RegExp(r'[A-E]\)\s*[^\n]*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'[1-5]\)\s*[^\n]*', multiLine: true), '');
    
    // Remove specific answer choice text if detected
    for (final choice in answerChoices) {
      if (choice.isNotEmpty) {
        cleaned = cleaned.replaceAll(choice, '');
      }
    }
    
    // Remove common instruction phrases
    final instructionPhrases = [
      'choose the correct answer',
      'select the best option',
      'which of the following',
      'mark the correct answer',
      'pick the right answer',
    ];
    
    for (final phrase in instructionPhrases) {
      cleaned = cleaned.replaceAll(RegExp(phrase, caseSensitive: false), '');
    }
    
    // Clean extra whitespace and return
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clean additional response artifacts that might appear in parsed content
  String _cleanResponseArtifacts(String text) {
    if (text.isEmpty) return text;
    
    String cleaned = text;
    
    // Remove common response artifacts
    final artifactPatterns = [
      // Remove "ANSWER:" or "EXPLANATION:" prefixes that might remain
      RegExp(r'^\s*(?:ANSWER|EXPLANATION)\s*[:=]\s*', caseSensitive: false),
      
      // Remove "Step X:" prefixes at the beginning
      RegExp(r'^\s*Step\s+\d+\s*[:.]\s*', caseSensitive: false),
      
      // Remove "Solution:" or "Problem:" prefixes
      RegExp(r'^\s*(?:Solution|Problem|Question)\s*[:=]\s*', caseSensitive: false),
      
      // Remove "Therefore" or "Thus" at the beginning if it's the only content
      RegExp(r'^\s*(?:Therefore|Thus|Hence)\s*[,:.]?\s*', caseSensitive: false),
      
      // Remove multiple consecutive newlines
      RegExp(r'\n{3,}'),
      
      // Remove trailing punctuation artifacts
      RegExp(r'[.]{2,}\s*$'),
      
      // Remove incomplete sentences at the end
      RegExp(r'\s+(?:The|This|That|It|We)\s*$', caseSensitive: false),
    ];
    
    // Apply all cleaning patterns
    for (final pattern in artifactPatterns) {
      if (pattern.pattern.contains(r'\n{3,}')) {
        // Replace multiple newlines with double newlines
        cleaned = cleaned.replaceAll(pattern, '\n\n');
      } else {
        cleaned = cleaned.replaceAll(pattern, '');
      }
    }
    
    // Final cleanup
    cleaned = cleaned.trim();
    
    return cleaned;
  }

  /// Validate if the extracted question is a valid math question
  bool _isValidMathQuestion(String question) {
    if (question.isEmpty || question.length < 10) {
      return false;
    }
    
    // Check for generic/unhelpful responses
    final genericResponses = [
      'the relationship cannot be determined',
      'cannot be determined from the information given',
      'cannot be determined',
      'insufficient information',
      'not enough information',
      'unable to determine',
      'cannot solve',
      'unclear',
      'ambiguous',
      'more information needed',
      'additional information required',
      'context is missing',
      'incomplete problem',
      'need more details',
      'i cannot',
      'i am unable',
      'it is not possible',
      'this cannot be solved',
    ];
    
    final lowerQuestion = question.toLowerCase();
    for (final generic in genericResponses) {
      if (lowerQuestion.contains(generic)) {
        return false;
      }
    }
    
    // Check for mathematical content indicators
    final mathIndicators = [
      RegExp(r'\d+'), // Contains numbers
      RegExp(r'[+\-*/=]'), // Contains math operators
      RegExp(r'\b(find|solve|calculate|determine|evaluate|what is|if)\b', caseSensitive: false),
      RegExp(r'\b(triangle|circle|square|rectangle|angle|equation|function)\b', caseSensitive: false),
      RegExp(r'\b(x|y|z)\b'), // Contains variables
    ];
    
    // At least one math indicator should be present
    return mathIndicators.any((pattern) => pattern.hasMatch(question));
  }

  /// Extract question from image using Gemma with structured prompt and return both question and chat
  Future<Map<String, dynamic>> _extractQuestionWithGemmaAndChat(Uint8List imageBytes) async {
    try {
      // Create a fresh chat instance for extraction
      final chat = await _inferenceModel!.createChat(supportImage: true);
      
      // Track this chat instance for cleanup
      _activeChatInstances.add(chat);
      print('Added extraction chat to active instances (total: ${_activeChatInstances.length})');
      
      // Load the structured extraction prompt
      final extractionPrompt = '''

**Role:** You are a meticulous and precise AI assistant, a "Math Question Extractor."

**Your Task:** Your one and only task is to analyze the provided image of a math problem and convert it into a detailed, structured text format. You must capture every detail with perfect accuracy. This output will be fed into a separate AI math solver, so the completeness and accuracy of your extraction are critical for it to function correctly.

**Crucial Instruction:** You are strictly forbidden from solving the problem, providing hints, explaining concepts, or performing any calculations. Your function is to describe, not to solve.

**Instructions for Extraction:**

1.  **Full Transcription:** Transcribe all text from the image verbatim. This includes the main question, any instructions, and all parts of any sub-questions. If the question has preset answers, include them seperately as possible answers.
2.  **Given Information:** Create a clear, itemized list of all the data provided in the problem. This includes:
    *   Numerical values and their units (e.g., 10 cm, 5 kg, 25 m/s).
    *   Defined variables (e.g., let x = the number of apples).
    *   All given equations, inequalities, or formulas.
3.  **Visuals Description:** If the image contains any diagrams, graphs, geometric figures, or tables, describe them in exhaustive detail. Do not interpret them, only describe what you see. Do not make assumptions based on the visuals (e.g., if the problem has horizontal lines, do not assume they are parallel unless explicitly marked).
    *   **For Geometric Figures (triangles, circles, etc.):** Describe the shape. List all labels for points, vertices, and sides. State the given lengths, angles, and any markings indicating parallel lines, right angles, or congruent sides.
    *   **For Graphs (line graphs, bar charts, etc.):** Identify the type of graph. State the title, the labels for the X-axis and Y-axis (including units), and the scale. Describe the data points, lines, or bars shown.
    *   **For Tables:** Recreate the table structure, including all headers, rows, and data cells exactly as they appear.
4.  **Mathematical Notation:** Preserve all mathematical notation with extreme care.
    *   Use standard characters for basic operations (`+`, `-`, `*`, `/`, `=`).
    *   Use `^` for exponents (e.g., `x^2`).
    *   Clearly write out fractions (e.g., `3/4`).
    *   For complex expressions like square roots, integrals, or matrices, use LaTeX formatting to ensure there is no ambiguity. For example: `\\sqrt{16}`, `\\int_{0}^{1} x^2 dx`.
5.  **Structure and Sub-questions:** If the problem has multiple parts (e.g., Part a, Part b, Part i), list each one separately and transcribe its question precisely.

---

**Output Format:**

Follow this structure precisely for your response.

**[BEGIN OUTPUT]**

**AN APPROPRIATE TITLE FOR THE PROBLEM**

**Main Problem Statement:**
[Transcribe the main question or problem statement here.]

**Given Information:**
*   [List the first piece of given data, equation, or value.]
*   [List the second piece of given data, equation, or value.]
*   [Continue for all given data.]

**Visuals Description:**
[If there are no visuals, write "None." Otherwise, provide the detailed description of the diagram, graph, or table as instructed above.]

**Sub-questions:**
*   **Part a):** [Transcribe the full question for Part a).]
    Answer Options: [List the possible answers for Part a) ONLY IF given.]
*   **Part b):** [Transcribe the full question for Part b).]
    Answer Options: [List the possible answers for Part b) ONLY IF given.]
*   [Continue for all sub-questions.]

**[END OUTPUT]**

Now analyze this image and extract the mathematical question following the format above.
''';
      
      print('Sending extraction prompt to Gemma...');
      print('Extraction prompt length: ${extractionPrompt.length}');
      
      // Send message with image to Gemma
      final message = Message(
        text: extractionPrompt,
        isUser: true,
        imageBytes: imageBytes,
      );
      
      // Send to Gemma chat
      await chat.addQueryChunk(message);
      
      // Get response stream and collect all tokens
      final responseStream = chat.generateChatResponseAsync();
      String response = '';
      
      await for (final token in responseStream) {
        response += token;
      }
      
      print('Gemma response tokens: ${response.length}');
      print('Complete Gemma response: $response');
      print('=====================================');
      
      // Clean and validate the response
      final cleanedResponse = response.trim();
      
      return {
        'question': cleanedResponse,
        'chat': chat,
      };
      
    } catch (e) {
      print('Error in Gemma extraction: $e');
      throw MathSolverException('Failed to extract question with Gemma: $e');
    }
  }





  /// Store essential context for follow-up questions (not full chat history)
  void _storeEssentialContext(String problemId, String extractedText, MathSolution solution, Uint8List? imageBytes) {
    _problemContexts[problemId] = {
      'extractedText': extractedText,
      'solution': solution.answer,
      'explanation': solution.explanation,
      'imageBytes': imageBytes,
    };
  }

  /// Solve a math problem using a fresh chat instance (simplified with model reset)
  Future<MathSolution> _solveWithFreshChat(String problemText, {Uint8List? imageBytes}) async {
    print('=== _solveWithFreshChat CALLED ===');
    print('Problem text length: ${problemText.length}');
    print('Has image bytes: ${imageBytes != null}');

    if (_inferenceModel == null) {
      throw MathSolverException('Gemma model not initialized');
    }

    try {
      print('Creating fresh chat instance for solving...');
      // Create a fresh chat instance (model was already reset)
      final chat = await _inferenceModel!.createChat(supportImage: true);
      print('Chat instance created successfully');

      print('Creating math solving prompt...');
      // Create a structured prompt for math solving
      final prompt = _createMathSolvingPrompt(problemText, imageBytes: imageBytes);
      print('Prompt created, length: ${prompt.length}');
      
      print('Creating message for solving...');
      // Create a message for the chat with image if available
      final message = imageBytes != null 
          ? Message(text: prompt, isUser: true, imageBytes: imageBytes)
          : Message(text: prompt, isUser: true);
      print('Message created with image: ${imageBytes != null}');
      
      print('Sending solving message to fresh chat...');
      // Send to fresh chat
      await chat.addQueryChunk(message);
      print('Message sent successfully');
      
      print('Getting response stream for solving...');
      // Get response stream and collect all tokens
      final responseStream = chat.generateChatResponseAsync();
      
      // Track solving state for seamless background/foreground transitions
      _currentSolvingChat = chat;
      _currentSolvingStream = responseStream;
      _accumulatedResponse = '';
      _isSolvingPaused = false;
      
      String fullResponse = '';
      print('Starting to collect solving response tokens...');
      
      // Create pausable stream subscription
      final completer = Completer<String>();
      _currentStreamSubscription = responseStream.listen(
        (token) {
          if (!_isSolvingPaused) {
            fullResponse += token;
            _accumulatedResponse += token;
          }
        },
        onDone: () {
          if (!_isSolvingPaused) {
            completer.complete(fullResponse);
          }
        },
        onError: (error) {
          if (!_isSolvingPaused) {
            completer.completeError(error);
          }
        },
      );
      
      // Wait for completion or pause
      fullResponse = await completer.future;
      
      print('Solving response collected: ${fullResponse.length} characters');
      print('Complete solving response: $fullResponse');
      
      // Parse the response to extract answer and explanation
      final solution = _parseMathResponse(fullResponse);
      
      return solution;
      
    } catch (e) {
      print('Error in solving with fresh chat: $e');
      throw MathSolverException('Failed to solve problem with fresh chat: $e');
    }
  }

  /// Solve a math problem using existing chat instance with role-clearing optimization
  Future<MathSolution> _solveWithExistingChatOptimized(String problemText, dynamic existingChat, {Uint8List? imageBytes, StatusCallback? onStatusUpdate}) async {
    print('=== _solveWithExistingChatOptimized CALLED ===');
    print('Problem text length: ${problemText.length}');
    print('Has image bytes: ${imageBytes != null}');
    print('Using existing chat with role-clearing to prevent extraction/solving confusion');
    
    if (_inferenceModel == null) {
      throw MathSolverException('Gemma model not initialized');
    }
    
    try {
      onStatusUpdate?.call('Preparing AI solver...');
      
      // Send a role-clearing message to reset the chat context from extraction to solving
      print('Sending role-clearing message to reset chat context...');
      final roleClearMessage = Message(
        text: '''Now forget your previous extraction role. You are now a math problem solver. 
Focus only on solving the problem I will give you next. 
Ignore any previous instructions about "not solving" - you should now solve the problem completely.''',
        isUser: true,
      );
      
      await existingChat.addQueryChunk(roleClearMessage);
      
      // Get and discard the role-clearing response to clear the context
      print('Processing role-clearing response...');
      final roleClearStream = existingChat.generateChatResponseAsync();
      await for (final token in roleClearStream) {
        // Discard the response - we just want to clear the context
      }
      print('Role-clearing completed - chat is now ready for solving');
      
      onStatusUpdate?.call('Analyzing problem structure...');
      
      print('Creating enhanced math solving prompt...');
      // Create the enhanced solving prompt
      final prompt = _createMathSolvingPrompt(problemText, imageBytes: imageBytes);
      print('Enhanced prompt created, length: ${prompt.length}');
      
      print('Creating solving message...');
      // Create a message for solving with image if available
      final message = imageBytes != null 
          ? Message(text: prompt, isUser: true, imageBytes: imageBytes)
          : Message(text: prompt, isUser: true);
      print('Solving message created with image: ${imageBytes != null}');
      
      onStatusUpdate?.call('Computing solution...');
      
      print('Sending solving message to role-cleared chat...');
      // Send to the role-cleared chat
      await existingChat.addQueryChunk(message);
      print('Solving message sent successfully');
      
      print('Getting response stream for solving...');
      // Get response stream and collect all tokens
      final responseStream = existingChat.generateChatResponseAsync();
      String fullResponse = '';
      print('Starting to collect solving response tokens...');
      
      await for (final token in responseStream) {
        fullResponse += token;
      }
      
      print('Solving response collected: ${fullResponse.length} characters');
      print('Complete solving response: $fullResponse');
      
      onStatusUpdate?.call('Finalizing solution...');
    
    // Parse the response to extract answer and explanation
    final solution = _parseMathResponse(fullResponse);
    
    // If we're in background mode, send completion notification
    if (_isBackgroundMode && _currentSolvingProblemId != null) {
      try {
        await _notificationService.showSolvingCompletedNotification(
          problemTitle: problemText.length > 50 
              ? '${problemText.substring(0, 50)}...' 
              : problemText,
          answer: solution.answer ?? 'Solution completed',
          problemId: _currentSolvingProblemId!,
        );
        print('✅ Background completion notification sent');
      } catch (e) {
        print('⚠️ Failed to send background completion notification: $e');
      }
    }
    
    return solution;
      
    } catch (e) {
      print('Error in optimized existing chat solving: $e');
      throw MathSolverException('Failed to solve problem with existing chat: $e');
    }
  }

  /// Solve a math problem using existing chat instance from extraction (legacy method)
  Future<MathSolution> _solveWithExistingChat(String problemText, dynamic existingChat, {Uint8List? imageBytes}) async {
    print('=== _solveWithExistingChat CALLED ===');
    print('Problem text length: ${problemText.length}');
    print('Has image bytes: ${imageBytes != null}');
    print('Using existing chat instance from extraction');
    
    if (_inferenceModel == null) {
      throw MathSolverException('Gemma model not initialized');
    }
    
    try {
      print('Creating math solving prompt...');
      // Create a structured prompt for math solving
      final prompt = _createMathSolvingPrompt(problemText, imageBytes: imageBytes);
      print('Prompt created, length: ${prompt.length}');
      
      print('Creating message for solving...');
      // Create a message for the chat with image if available
      final message = imageBytes != null 
          ? Message(text: prompt, isUser: true, imageBytes: imageBytes)
          : Message(text: prompt, isUser: true);
      print('Message created with image: ${imageBytes != null}');
      
      print('Sending solving message to existing chat...');
      // Send to existing chat
      await existingChat.addQueryChunk(message);
      print('Message sent successfully');
      
      print('Getting response stream for solving...');
      // Get response stream and collect all tokens
      final responseStream = existingChat.generateChatResponseAsync();
      String fullResponse = '';
      print('Starting to collect solving response tokens...');
      
      await for (final token in responseStream) {
        fullResponse += token;
      }
      
      print('Solving response collected: ${fullResponse.length} characters');
      print('Complete solving response: $fullResponse');
      
      // Parse the response to extract answer and explanation
      final solution = _parseMathResponse(fullResponse);
      
      return solution;
      
    } catch (e) {
      print('Error in solving with existing chat: $e');
      throw MathSolverException('Failed to solve problem: $e');
    }
  }

  /// Solve a math problem using Gemma model and return both solution and chat instance
  Future<Map<String, dynamic>> _solveWithGemmaAndReturnChat(String problemText, {Uint8List? imageBytes}) async {
    print('=== _solveWithGemmaAndReturnChat CALLED ===');
    print('Problem text length: ${problemText.length}');
    print('Has image bytes: ${imageBytes != null}');
    
    if (_inferenceModel == null) {
      throw MathSolverException('Gemma model not initialized');
    }
    
    try {
      print('Creating fresh chat instance for solving...');
      // Create a fresh chat instance for solving with timeout
      final chat = await _inferenceModel!.createChat(supportImage: true).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          print('ERROR: Chat creation timed out after 60 seconds');
          print('This indicates severe memory/resource pressure from accumulated chat instances');
          throw MathSolverException('Chat creation timed out after 60s - memory exhaustion');
        },
      );
      print('Chat instance created successfully');
      
      print('Creating math solving prompt...');
      // Create a structured prompt for math solving
      final prompt = _createMathSolvingPrompt(problemText, imageBytes: imageBytes);
      print('Prompt created, length: ${prompt.length}');
      
      print('Creating message for chat...');
      // Create a message for the chat with image if available
      final message = imageBytes != null 
          ? Message(text: prompt, isUser: true, imageBytes: imageBytes)
          : Message(text: prompt, isUser: true);
      print('Message created with image: ${imageBytes != null}');
      
      print('Sending message to Gemma chat...');
      // Send to Gemma chat
      await chat.addQueryChunk(message);
      print('Message sent successfully');
      
      print('Getting response stream...');
      // Get response stream and collect all tokens
      final responseStream = chat.generateChatResponseAsync();
      String fullResponse = '';
      print('Starting to collect response tokens...');
      
      await for (final token in responseStream) {
        fullResponse += token;
      }
      
      // Parse the response to extract answer and explanation
      final solution = _parseMathResponse(fullResponse);
      
      // Return both solution and chat instance
      return {
        'solution': solution,
        'chat': chat,
      };
      
    } catch (e) {
      throw MathSolverException('Failed to solve with Gemma: $e');
    }
  }

  /// Solve a math problem using Gemma model (legacy method)
  Future<MathSolution> _solveWithGemma(String problemText, {Uint8List? imageBytes}) async {
    print('=== _solveWithGemma CALLED ===');
    print('Problem text length: ${problemText.length}');
    print('Has image bytes: ${imageBytes != null}');
    
    if (_inferenceModel == null) {
      throw MathSolverException('Gemma model not initialized');
    }
    
    try {
      print('Creating fresh chat instance for solving...');
      // Create a fresh chat instance for solving with timeout
      final chat = await _inferenceModel!.createChat(supportImage: true).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          print('ERROR: Chat creation timed out after 60 seconds');
          print('This indicates severe memory/resource pressure from accumulated chat instances');
          throw MathSolverException('Chat creation timed out after 60s - memory exhaustion');
        },
      );
      print('Chat instance created successfully');
      
      print('Creating math solving prompt...');
      // Create a structured prompt for math solving
      final prompt = _createMathSolvingPrompt(problemText, imageBytes: imageBytes);
      print('Prompt created, length: ${prompt.length}');
      
      print('Creating message for chat...');
      // Create a message for the chat with image if available
      final message = imageBytes != null 
          ? Message(text: prompt, isUser: true, imageBytes: imageBytes)
          : Message(text: prompt, isUser: true);
      print('Message created with image: ${imageBytes != null}');
      
      print('Sending message to Gemma chat...');
      // Send to Gemma chat
      await chat.addQueryChunk(message);
      print('Message sent successfully');
      
      print('Getting response stream...');
      // Get response stream and collect all tokens
      final responseStream = chat.generateChatResponseAsync();
      String fullResponse = '';
      print('Starting to collect response tokens...');
      
      await for (final token in responseStream) {
        fullResponse += token;
      }
      
      // Parse the response to extract answer and explanation
      return _parseMathResponse(fullResponse);
      
    } catch (e) {
      throw MathSolverException('Failed to solve with Gemma: $e');
    }
  }

  /// Create a structured prompt for math problem solving that preserves extraction details
  String _createMathSolvingPrompt(String problemText, {Uint8List? imageBytes}) {
    if (imageBytes != null) {
      // Enhanced prompt for image-based problems that references all extraction sections
      return '''
You are now a math problem solver. Below is a structured extraction of a math problem that was carefully analyzed from an image.

EXTRACTED PROBLEM DETAILS:
$problemText

SOLVING INSTRUCTIONS:
1. Read through ALL sections of the extracted problem carefully
2. Pay special attention to any "Given Information" section - use ALL provided data points
3. If there's a "Visuals Description" section, incorporate those visual elements into your solution
4. Address each sub-question if multiple parts exist
5. Reference specific given values, measurements, or visual elements in your calculations
6. If there are answer choices (A, B, C, D, etc.), include ALL of them in your response
7. Show your work step-by-step, citing the extracted information
8. Be concise but thorough!
9. Make sure your answer is correct!

IMPORTANT: Use these EXACT section markers for your response:

 

===STEP_BY_STEP_EXPLANATION_START===
[Your detailed step-by-step solution referencing the given information and visuals]

FORMATTING GUIDELINES:
- Use **bold** for important concepts and final answers
- Use `code formatting` for mathematical expressions and equations
- Use numbered lists (1., 2., 3.) for step-by-step solutions
- Use bullet points (-) for key information
- Use > blockquotes for important formulas or theorems
- Format fractions as `a/b` or use LaTeX-style notation
- Use clear headings (##) for major solution steps
===STEP_BY_STEP_EXPLANATION_END===

===FINAL_ANSWER_START===
[Your final answer here, make sure that your solution reaches this answer - if multiple choice, include the letter and full option]
===FINAL_ANSWER_END===

Be thorough and reference the extracted details explicitly.''';
    } else {
      // Enhanced prompt for text-based problems
      return '''
You are a math problem solver. Analyze this problem carefully and solve it step by step.

PROBLEM:
$problemText

SOLVING INSTRUCTIONS:
1. Identify all given information and constraints
2. Determine what needs to be found
3. Show your work step-by-step with clear reasoning
4. Use all provided data in your solution
5. If there are answer choices (A, B, C, D, etc.), include ALL of them in your response
6. Be concise but thorough!

IMPORTANT: Use these EXACT section markers for your response:

 

===STEP_BY_STEP_EXPLANATION_START===
[Your detailed step-by-step solution]

FORMATTING GUIDELINES:
- Use **bold** for important concepts and final answers
- Use `code formatting` for mathematical expressions and equations
- Use numbered lists (1., 2., 3.) for step-by-step solutions
- Use bullet points (-) for key information
- Use > blockquotes for important formulas or theorems
- Format fractions as `a/b` or use LaTeX-style notation
- Use clear headings (##) for major solution steps
===STEP_BY_STEP_EXPLANATION_END===

===FINAL_ANSWER_START===
[Your final answer here, make sure that your solution reaches this answer - if multiple choice, include the letter and full option]
===FINAL_ANSWER_END===

Be thorough but concise.''';
    }
  }

  /// Parse Gemma's response to extract structured solution with enhanced handling
  MathSolution _parseMathResponse(String response) {
    print('=== PARSING MATH RESPONSE (NEW FORMAT) ===');
    print('Response length: ${response.length} characters');
    print('Raw response: $response');
    print('=== CHECKING FOR STRUCTURED MARKERS ===');
    print('Contains STEP_BY_STEP_EXPLANATION_START: ${response.contains('===STEP_BY_STEP_EXPLANATION_START===')}');
    print('Contains STEP_BY_STEP_EXPLANATION_END: ${response.contains('===STEP_BY_STEP_EXPLANATION_END===')}');
    print('Contains FINAL_ANSWER_START: ${response.contains('===FINAL_ANSWER_START===')}');
    print('Contains FINAL_ANSWER_END: ${response.contains('===FINAL_ANSWER_END===')}');
    
    String answer = '';
    String explanation = '';
    
    // Parse using new structured format: EXPLANATION first, then FINAL_ANSWER
    final explanationMatch = RegExp(
      r'===STEP_BY_STEP_EXPLANATION_START===(.*?)===STEP_BY_STEP_EXPLANATION_END===',
      dotAll: true,
      caseSensitive: false
    ).firstMatch(response);
    
    final finalAnswerMatch = RegExp(
      r'===FINAL_ANSWER_START===(.*?)===FINAL_ANSWER_END===',
      dotAll: true,
      caseSensitive: false
    ).firstMatch(response);
  
    if (explanationMatch != null) {
      explanation = explanationMatch.group(1)?.trim() ?? '';
      // Clean any remaining section markers from explanation
      explanation = _cleanSectionMarkers(explanation);
      print('✅ Found structured STEP_BY_STEP_EXPLANATION: ${explanation.length} characters');
    }
  
    if (finalAnswerMatch != null) {
      answer = finalAnswerMatch.group(1)?.trim() ?? '';
      // Clean any remaining section markers from answer
      answer = _cleanSectionMarkers(answer);
      print('✅ Found structured FINAL_ANSWER: $answer');
    }
  
    // If structured format found, we have a complete solution
    if (finalAnswerMatch != null || explanationMatch != null) {
      print('✅ Successfully parsed new structured format (explanation → answer)');
    } else {
      print('⚠️ Structured format not found, trying legacy parsing...');
      
      // Fallback to legacy parsing for backward compatibility
      final lines = response.split('\n');
      bool inExplanation = false;
      bool foundAnswerSection = false;
      bool foundExplanationSection = false;
      
      for (final line in lines) {
        final trimmedLine = line.trim();
        
        // Look for ANSWER: section (case insensitive)
        if (RegExp(r'^ANSWER\s*:', caseSensitive: false).hasMatch(trimmedLine)) {
          answer = trimmedLine.replaceFirst(RegExp(r'^ANSWER\s*:', caseSensitive: false), '').trim();
          foundAnswerSection = true;
          print('Found legacy ANSWER section: $answer');
        }
        // Look for EXPLANATION: section (case insensitive)
        else if (RegExp(r'^EXPLANATION\s*:', caseSensitive: false).hasMatch(trimmedLine)) {
          inExplanation = true;
          foundExplanationSection = true;
          print('Found legacy EXPLANATION section start');
          // Check if there's content on the same line after EXPLANATION:
          final explanationContent = trimmedLine.replaceFirst(RegExp(r'^EXPLANATION\s*:', caseSensitive: false), '').trim();
          if (explanationContent.isNotEmpty) {
            explanation += '$explanationContent\n';
          }
        }
        // Collect explanation content
        else if (inExplanation && trimmedLine.isNotEmpty) {
          explanation += '$trimmedLine\n';
        }
        // If no structured sections found, look for inline patterns
        else if (!foundAnswerSection && !foundExplanationSection) {
          // Look for inline answer patterns like "The answer is X" or "Answer: X"
          final inlineAnswerMatch = RegExp(
            r'(?:the\s+)?(?:final\s+)?(?:answer|result|solution)(?:\s+is)?\s*[:=]?\s*([\d\.\-\+\/\*\^\(\)\s\w°%A-Z]+)',
            caseSensitive: false
          ).firstMatch(trimmedLine);
          if (inlineAnswerMatch != null && answer.isEmpty) {
            answer = inlineAnswerMatch.group(1)?.trim() ?? '';
            print('Found inline answer: $answer');
          }
        }
      }
      
      // Enhanced fallback parsing if no structured format found
      if (answer.isEmpty && explanation.isEmpty) {
        print('No legacy format found, using enhanced fallback parsing');
        
        // If response has substantial content, use it as explanation
        if (response.trim().length > 10) {
          explanation = response.trim();
          print('Using entire response as explanation: ${explanation.length} characters');
        }
        
        // Try multiple answer extraction patterns including multiple choice
        final answerPatterns = [
          // Multiple choice patterns (A, B, C, D, etc.)
          RegExp(r'(?:the\s+)?(?:correct\s+)?(?:answer|choice)(?:\s+is)?\s*[:=]?\s*([A-Z])\b', caseSensitive: false),
          RegExp(r'\b([A-Z])\s*[\.:)]\s*(?:is\s+)?(?:correct|right|the\s+answer)', caseSensitive: false),
          // Numerical patterns
          RegExp(r'(?:the\s+)?(?:final\s+)?(?:answer|result|solution)(?:\s+is)?\s*[:=]?\s*([\d\.\-\+\/\*\^\(\)\s\w°%]+)', caseSensitive: false),
          RegExp(r'(?:therefore|thus|hence)[\s,]*(?:the\s+)?(?:answer|result)?\s*[:=]?\s*([\d\.\-\+\/\*\^\(\)\s\w°%A-Z]+)', caseSensitive: false),
          RegExp(r'([\d\.\-\+]+(?:\s*[°%])?(?:\s*(?:cm|m|kg|g|seconds?|minutes?|hours?|degrees?))?)\s*$', multiLine: true),
        ];
        
        for (final pattern in answerPatterns) {
          final match = pattern.firstMatch(response);
          if (match != null) {
            answer = match.group(1)?.trim() ?? '';
            print('Extracted answer using fallback pattern: $answer');
            break;
          }
        }
      }
    }
    
    // Clean up the extracted answer and explanation
    answer = answer.trim();
    explanation = explanation.trim();
    
    // Final fallback: if explanation is empty but we have a response, use response as explanation
    if (explanation.isEmpty && response.trim().length > 5) {
      explanation = response.trim();
      print('⚠️ Using entire response as explanation due to parsing failure');
    }
    
    // Ensure we never return completely empty explanation if we have response content
    if (explanation.isEmpty && response.trim().isNotEmpty) {
      explanation = response.trim();
      print('⚠️ Final fallback: using response as explanation');
    }
    
    // CRITICAL: Apply comprehensive cleaning to both answer and explanation before returning
    // This ensures no parsing markers are visible in the UI
    answer = _cleanSectionMarkers(answer);
    explanation = _cleanSectionMarkers(explanation);
    
    // Additional cleaning for any remaining artifacts
    answer = _cleanResponseArtifacts(answer);
    explanation = _cleanResponseArtifacts(explanation);
    
    print('Final parsed answer: "$answer"');
    print('Final parsed explanation length: ${explanation.length} characters');
    print('=== PARSING COMPLETE ===');
    
    return MathSolution(
      answer: answer.isNotEmpty ? answer : 'Unable to determine final answer',
      explanation: explanation.isNotEmpty ? explanation : response.trim(),
    );
  }

  /// Convert text to LaTeX format for better math representation
  String _convertTextToLatex(String text) {
    String latex = text;
    
    // Basic LaTeX conversions
    latex = latex.replaceAll(RegExp(r'sqrt\(([^)]+)\)'), r'\\sqrt{$1}');
    latex = latex.replaceAll(RegExp(r'(\d+)\/(\d+)'), r'\\frac{$1}{$2}');
    latex = latex.replaceAll(RegExp(r'([a-zA-Z])\^(\d+)'), r'$1^{$2}');
    latex = latex.replaceAll('*', ' \\cdot ');
    latex = latex.replaceAll('+-', ' \\pm ');
    
    return latex;
  }

  /// Encode image to base64 for storage
  String _encodeImageToBase64(Uint8List imageBytes) {
    return base64Encode(imageBytes);
  }
  
  /// Generate a descriptive title for a math problem using AI
  Future<String> generateProblemTitle(String problemText) async {
    try {
      debugPrint('🏷️ Generating title for problem...');
      
      // Create a concise prompt for title generation
      final prompt = '''
Generate a short, descriptive title (max 6 words) for this math problem:

$problemText

Respond with only the title, no quotes or extra text.''';
      
      // Create a new chat instance for title generation
      final chat = await _inferenceModel!.createChat();
      final message = Message(text: prompt, isUser: true);
      
      // Send to Gemma
      await chat.addQueryChunk(message);
      
      // Get response stream and collect all tokens
      final responseStream = chat.generateChatResponseAsync();
      String response = '';
      
      await for (final token in responseStream) {
        response += token;
      }
      
      String title = response.trim();
    
    // Comprehensive title cleaning
    final cleaningPatterns = [
      // Remove quotes (single, double, backticks)
      RegExp(r'^["\047`]|["\047`]$'),
      
      // Remove common prefixes (case insensitive)
      RegExp(r'^Title:\s*', caseSensitive: false),
      RegExp(r'^Problem:\s*', caseSensitive: false),
      RegExp(r'^Question:\s*', caseSensitive: false),
      RegExp(r'^Math Problem:\s*', caseSensitive: false),
      
      // Remove "Problem Statement" variants
      RegExp(r'^\*\*Problem Statement\*\*:?\s*', caseSensitive: false),
      RegExp(r'^Problem Statement:?\s*', caseSensitive: false),
      RegExp(r'^\*\*Problem\*\*:?\s*', caseSensitive: false),
      RegExp(r'^Problem:?\s*', caseSensitive: false),
      
      // Remove markdown formatting
      RegExp(r'^\*\*|\*\*$'), // Bold
      RegExp(r'^\*|\*$'), // Italic
      RegExp(r'^__|__$'), // Underline
      RegExp(r'^`|`$'), // Code
      
      // Remove section markers that might leak into titles
      RegExp(r'^===.*?===\s*', caseSensitive: false),
      RegExp(r'^==.*?==\s*', caseSensitive: false),
      RegExp(r'^=.*?=\s*', caseSensitive: false),
      
      // Remove numbered prefixes
      RegExp(r'^\d+\.\s*'),
      RegExp(r'^\d+\)\s*'),
      
      // Remove dashes and bullets
      RegExp(r'^[-•*]\s*'),
      
      // Remove "The" at the beginning if it makes the title awkward
      RegExp(r'^The\s+(?=\w+\s+Problem)', caseSensitive: false),
    ];
    
    // Apply all cleaning patterns
    for (final pattern in cleaningPatterns) {
      title = title.replaceAll(pattern, '');
    }
    
    // Take only the first line and clean up
    title = title.split('\n').first.trim();
    
    // Remove extra whitespace
    title = title.replaceAll(RegExp(r'\s+'), ' ');
    
    // Capitalize first letter if it's lowercase
    if (title.isNotEmpty && title[0] == title[0].toLowerCase()) {
      title = title[0].toUpperCase() + title.substring(1);
    }
      
      // Validate title length and content
      if (title.isEmpty || title.length > 50) {
        // Fallback to extracting key mathematical terms
        title = _extractMathematicalConcept(problemText);
      }
      
      debugPrint('🏷️ Generated title: "$title"');
      return title;
      
    } catch (e) {
      debugPrint('❌ Error generating title: $e');
      return _extractMathematicalConcept(problemText);
    }
  }
  
  /// Delete a math problem from history
  Future<void> deleteProblem(String problemId) async {
    try {
      debugPrint('🗑️ Deleting problem: $problemId');
      await _databaseService.deleteMathProblem(problemId);
      debugPrint('✅ Problem deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting problem: $e');
      rethrow;
    }
  }
  
  /// Extract title from text using mathematical concept detection
  String _extractTitleFromText(String text) {
    return _extractMathematicalConcept(text);
  }

  /// Extract mathematical concept from problem text as fallback title
  String _extractMathematicalConcept(String text) {
    final concepts = {
      RegExp(r'\b(quadratic|parabola|x²|x\^2)\b', caseSensitive: false): 'Quadratic Equation',
      RegExp(r'\b(triangle|angle|degree|°)\b', caseSensitive: false): 'Triangle Problem',
      RegExp(r'\b(circle|radius|diameter|circumference)\b', caseSensitive: false): 'Circle Geometry',
      RegExp(r'\b(linear|slope|y\s*=|equation)\b', caseSensitive: false): 'Linear Equation',
      RegExp(r'\b(system|simultaneous|equations)\b', caseSensitive: false): 'System of Equations',
      RegExp(r'\b(derivative|differentiate|d/dx)\b', caseSensitive: false): 'Calculus Problem',
      RegExp(r'\b(integral|integrate|∫)\b', caseSensitive: false): 'Integration Problem',
      RegExp(r'\b(probability|chance|odds)\b', caseSensitive: false): 'Probability Problem',
      RegExp(r'\b(statistics|mean|median|mode)\b', caseSensitive: false): 'Statistics Problem',
      RegExp(r'\b(fraction|numerator|denominator)\b', caseSensitive: false): 'Fraction Problem',
      RegExp(r'\b(percentage|percent|%)\b', caseSensitive: false): 'Percentage Problem',
      RegExp(r'\b(algebra|variable|solve for)\b', caseSensitive: false): 'Algebra Problem',
      RegExp(r'\b(geometry|geometric|shape)\b', caseSensitive: false): 'Geometry Problem',
    };
    
    for (final entry in concepts.entries) {
      if (entry.key.hasMatch(text)) {
        return entry.value;
      }
    }
    
    // Default fallback
    return 'Math Problem';
  }

  /// Check if the OCR text contains indicators of visual elements that require image analysis
  bool _hasVisualElements(String text) {
    final visualIndicators = [
      // Geometric references
      RegExp(r'\b(diagram|figure|picture|image|graph|chart)\b', caseSensitive: false),
      RegExp(r'\b(above|below|left|right|shown|illustrated)\b', caseSensitive: false),
      RegExp(r'\b(triangle|circle|square|rectangle|polygon|angle|line)\b', caseSensitive: false),
      RegExp(r'\b(parallel|perpendicular|intersect|vertex|vertices)\b', caseSensitive: false),
      // Spatial relationships
      RegExp(r'\b(to the (left|right|above|below))\b', caseSensitive: false),
      RegExp(r'\b(in the (diagram|figure|picture|image))\b', caseSensitive: false),
      // Mathematical diagram elements
      RegExp(r'\b(coordinate|axis|axes|grid|scale)\b', caseSensitive: false),
      RegExp(r'\b(point [A-Z]|line [A-Z]|angle [A-Z])\b', caseSensitive: false),
      // Visual comparison indicators
      RegExp(r'\b(quantity [AB]|column [AB]|option [ABCD])\b', caseSensitive: false),
      RegExp(r'\b(compare|greater|less|equal|relationship)\b', caseSensitive: false),
      // Specific visual problem types
      RegExp(r'\b(shaded|highlighted|marked|labeled)\b', caseSensitive: false),
      RegExp(r'\b(table|chart|graph|plot)\b', caseSensitive: false),
    ];
    
    for (final pattern in visualIndicators) {
      if (pattern.hasMatch(text)) {
        print('Visual element detected: "${pattern.pattern}" in text');
        return true;
      }
    }
    
    return false;
  }

  /// Clean section markers from parsed content to prevent them from showing to users
  String _cleanSectionMarkers(String text) {
    if (text.isEmpty) return text;
    
    String cleaned = text;
    
    // Remove all possible section marker variants (case insensitive, flexible spacing)
    final markerPatterns = [
      // Standard format: ===SECTION_NAME_START/END===
      RegExp(r'===\s*[A-Z_]+\s*START\s*===', caseSensitive: false),
      RegExp(r'===\s*[A-Z_]+\s*END\s*===', caseSensitive: false),
      
      // Specific known markers
      RegExp(r'===\s*STEP_BY_STEP_EXPLANATION_START\s*===', caseSensitive: false),
      RegExp(r'===\s*STEP_BY_STEP_EXPLANATION_END\s*===', caseSensitive: false),
      RegExp(r'===\s*FINAL_ANSWER_START\s*===', caseSensitive: false),
      RegExp(r'===\s*FINAL_ANSWER_END\s*===', caseSensitive: false),
      RegExp(r'===\s*ANSWER_OPTIONS_START\s*===', caseSensitive: false),
      RegExp(r'===\s*ANSWER_OPTIONS_END\s*===', caseSensitive: false),
      
      // Any triple equals with content (more comprehensive)
      RegExp(r'===.*?===', caseSensitive: false, dotAll: true),
      RegExp(r'===.*?$', caseSensitive: false, multiLine: true), // Incomplete markers
      RegExp(r'^===.*', caseSensitive: false, multiLine: true), // Incomplete markers
      
      // Double equals variants
      RegExp(r'==\s*[A-Z_]+\s*START\s*==', caseSensitive: false),
      RegExp(r'==\s*[A-Z_]+\s*END\s*==', caseSensitive: false),
      RegExp(r'==.*?==', caseSensitive: false, dotAll: true),
      
      // Single equals variants
      RegExp(r'=\s*[A-Z_]+\s*START\s*=', caseSensitive: false),
      RegExp(r'=\s*[A-Z_]+\s*END\s*=', caseSensitive: false),
      
      // Bracket variants
      RegExp(r'\[\s*[A-Z_]+\s*START\s*\]', caseSensitive: false),
      RegExp(r'\[\s*[A-Z_]+\s*END\s*\]', caseSensitive: false),
      
      // Hash variants (markdown-style)
      RegExp(r'#{1,6}\s*[A-Z_]+\s*START\s*#{0,6}', caseSensitive: false),
      RegExp(r'#{1,6}\s*[A-Z_]+\s*END\s*#{0,6}', caseSensitive: false),
      
      // Dash/underscore variants
      RegExp(r'---+\s*[A-Z_]+\s*START\s*---+', caseSensitive: false),
      RegExp(r'---+\s*[A-Z_]+\s*END\s*---+', caseSensitive: false),
      RegExp(r'___+\s*[A-Z_]+\s*START\s*___+', caseSensitive: false),
      RegExp(r'___+\s*[A-Z_]+\s*END\s*___+', caseSensitive: false),
      
      // Asterisk variants
      RegExp(r'\*{2,}\s*[A-Z_]+\s*START\s*\*{2,}', caseSensitive: false),
      RegExp(r'\*{2,}\s*[A-Z_]+\s*END\s*\*{2,}', caseSensitive: false),
    ];
    
    // Apply all cleaning patterns
    for (final pattern in markerPatterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    
    // Remove any remaining structured markers that might be missed
    cleaned = cleaned.replaceAll(RegExp(r'^\s*[=\[\-\*]+.*?[=\]\-\*]+\s*$', multiLine: true), '');
    
    // Clean up excessive whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n'); // Remove triple+ newlines
    cleaned = cleaned.replaceAll(RegExp(r'^\s+', multiLine: true), ''); // Remove leading whitespace on lines
    cleaned = cleaned.replaceAll(RegExp(r'\s+$', multiLine: true), ''); // Remove trailing whitespace on lines
    cleaned = cleaned.trim();
    
    print('🧹 Section marker cleaning: ${text.length} → ${cleaned.length} characters');
    if (text != cleaned) {
      print('🧹 Removed markers from text');
    }
    
    return cleaned;
  }

  /// Continue conversation about a specific problem
  Future<String> continueConversation(String problemId, String userMessage) async {
    if (!_isInitialized) await initialize();
    
    final problem = await _databaseService.getMathProblem(problemId);
    if (problem == null) {
      throw MathSolverException('Problem not found');
    }

    try {
      print('=== CONTINUING CONVERSATION ===');
      print('Problem ID: $problemId');
      print('User message: $userMessage');
      
      // CRITICAL FIX: Reset model when switching to different problem to prevent cross-contamination
      if (_lastProcessedProblemId != null && _lastProcessedProblemId != problemId) {
        print('🔄 Switching to different problem - resetting model to prevent cross-contamination');
        print('Previous problem: $_lastProcessedProblemId, Current problem: $problemId');
        await _resetModelForNewProblem();
        print('✅ Model reset complete for problem switch');
      }
      _lastProcessedProblemId = problemId;
      
      // Get complete conversation history for this problem to provide full context
      final chatHistory = await _databaseService.getChatMessages(problemId);
      print('📚 Retrieved ${chatHistory.length} previous messages for context');
      
      // CRITICAL FIX: Add current user message to conversation history BEFORE generating response
      // This ensures the model has access to ALL messages including the current one
      final currentUserMessage = ChatMessage(
        id: const Uuid().v4(),
        problemId: problemId,
        message: userMessage,
        isUser: true,
        createdAt: DateTime.now(),
      );
      
      // Save current user message immediately so it's included in context
      await _databaseService.saveChatMessage(currentUserMessage);
      print('💾 Saved current user message to database for context inclusion');
      
      // Update chat history to include the current user message
      final updatedChatHistory = [...chatHistory, currentUserMessage];
      print('📚 Updated conversation history now includes ${updatedChatHistory.length} messages');
      
      // Check if we have stored essential context for this problem
    final storedContext = _problemContexts[problemId];
    
    // Re-enabled stored context path with proper context storage
    if (storedContext != null) {
        print('Using stored essential context for follow-up question');
        
        final extractedText = storedContext['extractedText'] as String;
        final solution = storedContext['solution'] as String;
        final explanation = storedContext['explanation'] as String;
        final imageBytes = storedContext['imageBytes'] as Uint8List?;
        
        print('Has stored image: ${imageBytes != null}');
        
        // Build conversation history context using updated history (includes current message)
        String conversationHistory = '';
        if (updatedChatHistory.isNotEmpty) {
          conversationHistory = '\nPREVIOUS CONVERSATION:\n';
          for (final msg in updatedChatHistory) {
            final role = msg.isUser ? 'USER' : 'AI';
            conversationHistory += '$role: ${msg.message}\n';
          }
        }
        
        // FULL context prompt with complete conversation history
        final contextPrompt = '''
You are a math tutor helping with a follow-up question about a previously solved problem.

ORIGINAL PROBLEM:
$extractedText

PREVIOUS SOLUTION:
$solution

PREVIOUS EXPLANATION:
$explanation$conversationHistory

FOLLOW-UP QUESTION:
$userMessage

Please provide a helpful response based on the complete context above. Be concise and focus on the specific follow-up question.
''';

        print('📋 Context prompt length: ${contextPrompt.length} characters');
        
        // CRITICAL FIX: Reset model state before creating chat to prevent hanging
        print('🔄 Resetting model state before stored context chat...');
        await _resetModelForNewProblem();
        print('✅ Model state reset complete');
        
        // Create a fresh chat instance for the follow-up (avoids context overload)
        final chat = await _inferenceModel!.createChat(supportImage: true);
        
        // Track chat instance for proper cleanup
        _activeChatInstances.add(chat);
        print('Added follow-up chat to active instances (total: ${_activeChatInstances.length})');
        
        try {
          print('📝 Creating message for stored context chat...');
          
          // Create a message for the chat with image if available
          final message = imageBytes != null 
              ? Message(text: contextPrompt, isUser: true, imageBytes: imageBytes)
              : Message(text: contextPrompt, isUser: true);
          
          print('📤 Sending message to chat instance...');
          
          // Send to fresh chat
          await chat.addQueryChunk(message);
          
          print('🔄 Starting response generation...');
          
          // Get response stream and collect all tokens
          final responseStream = chat.generateChatResponseAsync();
          String response = '';
          
          print('📥 Collecting response tokens...');
          
          await for (final token in responseStream) {
            response += token;
            if (response.length % 50 == 0) {
              print('📊 Response progress: ${response.length} characters');
            }
          }
          
          print('Follow-up response generated: ${response.length} characters');
          
          // Save only AI response to database (user message already saved at beginning)
          final aiChatMessage = ChatMessage(
            id: const Uuid().v4(),
            problemId: problemId,
            message: response,
            isUser: false,
            createdAt: DateTime.now(),
          );
          
          await _databaseService.saveChatMessage(aiChatMessage);
          print('💾 Saved AI response to database');
          
          return response;
          
        } finally {
          // Always clean up the chat instance
          _activeChatInstances.remove(chat);
          print('Removed follow-up chat from active instances (remaining: ${_activeChatInstances.length})');
        }
        
      } else {
        print('No stored context found, using database fallback');
        
        // Build conversation history context for database fallback using updated history
        String conversationHistory = '';
        if (updatedChatHistory.isNotEmpty) {
          conversationHistory = '\nPREVIOUS CONVERSATION:\n';
          for (final msg in updatedChatHistory) {
            final role = msg.isUser ? 'USER' : 'AI';
            conversationHistory += '$role: ${msg.message}\n';
          }
        }
        
        // Fallback: Create context-aware prompt from database with full conversation history
        final contextPrompt = '''
You are a math tutor helping with a follow-up question about a previously solved problem.

ORIGINAL PROBLEM:
${problem.extractedText ?? problem.originalInput}

PREVIOUS SOLUTION:
${problem.solution ?? 'Not solved yet'}

PREVIOUS EXPLANATION:
${problem.stepByStepExplanation ?? 'No explanation available'}$conversationHistory

FOLLOW-UP QUESTION:
$userMessage

Please provide a helpful response based on the complete context above. Be concise and focus on the specific follow-up question.
''';

        // Create a fresh chat instance for continuation
        final chat = await _inferenceModel!.createChat(supportImage: true);
        
        // Track chat instance for proper cleanup
        _activeChatInstances.add(chat);
        print('Added fallback follow-up chat to active instances (total: ${_activeChatInstances.length})');
        
        try {
          // Create a message for the chat
          final message = Message(text: contextPrompt, isUser: true);
          
          // Send to Gemma chat
          await chat.addQueryChunk(message);
          
          // Get response stream and collect all tokens
          final responseStream = chat.generateChatResponseAsync();
          String response = '';
          
          await for (final token in responseStream) {
            response += token;
          }
          
          // Save only AI response to database (user message already saved at beginning)
          final aiChatMessage = ChatMessage(
            id: const Uuid().v4(),
            problemId: problemId,
            message: response,
            isUser: false,
            createdAt: DateTime.now(),
          );
          
          await _databaseService.saveChatMessage(aiChatMessage);
          print('💾 Saved AI response to database (fallback path)');
          
          // CRITICAL FIX: Store context after successful follow-up for future use
          print('✅ Stored database context for future follow-ups');
          _problemContexts[problemId] = {
            'extractedText': problem.extractedText ?? problem.originalInput,
            'solution': problem.solution ?? 'Not solved yet',
            'explanation': problem.stepByStepExplanation ?? 'No explanation available',
            'imageBytes': null, // No image in database fallback
          };
          
          return response;
          
        } finally {
          // Always clean up the chat instance
          _activeChatInstances.remove(chat);
          print('Removed fallback follow-up chat from active instances (remaining: ${_activeChatInstances.length})');
        }
      }
      
    } catch (e) {
      print('Error in continueConversation: $e');
      throw MathSolverException('Failed to continue conversation: $e');
    }
  }

  /// Get problem history
  Future<List<MathProblem>> getHistory() async {
    return await _databaseService.getRecentMathProblems();
  }

  /// Get recent problems with optional limit
  Future<List<MathProblem>> getRecentProblems({int? limit}) async {
    return await _databaseService.getRecentMathProblems(limit: limit ?? 50);
  }

  /// Get the current solving problem ID
  String? getCurrentSolvingProblemId() {
    return _currentSolvingProblemId;
  }

  /// Check if currently solving a problem
  bool isCurrentlySolving(String? problemId) {
    print('🔍 Checking if currently solving problem: $problemId');
    print('🔍 Service current solving problem ID: $_currentSolvingProblemId');
    print('🔍 Background mode: $_isBackgroundMode');
    print('🔍 Stream subscription active: ${_currentStreamSubscription != null && !_currentStreamSubscription!.isPaused}');
    
    // Check if we have an active solving stream
    if (_currentStreamSubscription != null && !_currentStreamSubscription!.isPaused) {
      print('✅ Active solving stream detected');
      return true;
    }
    
    // Check if we're in background mode with matching problem ID
    if (_isBackgroundMode && _currentSolvingProblemId != null) {
      if (problemId == null || _currentSolvingProblemId == problemId) {
        print('✅ Background solving active for problem: $_currentSolvingProblemId');
        return true;
      }
    }
    
    print('❌ No active solving detected');
    return false;
  }

  /// Search problems
  Future<List<MathProblem>> searchProblems(String query) async {
    return await _databaseService.searchMathProblems(query);
  }

  /// Get chat history for a problem
  Future<List<ChatMessage>> getChatHistory(String problemId) async {
    return await _databaseService.getChatMessages(problemId);
  }

  // ========== BACKGROUND SOLVING METHODS ==========

  /// Start background solving for image-only problem
  Future<void> solveFromImageInBackground(Uint8List imageBytes, {String? title}) async {
    await _initializeBackgroundServices();
    
    try {
      // Create problem record for tracking
      final problemId = const Uuid().v4();
      final problem = MathProblem(
        id: problemId,
        originalInput: 'Image-based math problem',
        inputType: ProblemInputType.image,
        imageBase64: _encodeImageToBase64(imageBytes),
        createdAt: DateTime.now(),
        status: ProblemStatus.solving,
      );
      
      // Save initial problem to database
      await _databaseService.saveMathProblem(problem);
      print('✅ Background problem saved with ID: $problemId');
      
      // Store image data in temporary file to avoid WorkManager 10KB limit
      final imagePath = await _storeImageTemporarily(imageBytes, problemId);
      print('📁 Image stored temporarily at: $imagePath');
      
      // Register background task for true background solving
      await _backgroundTaskService.startBackgroundSolving(
        problemId: problemId,
        problemText: 'Image-based math problem',
        problemType: 'image',
        imagePath: imagePath, // Pass file path instead of base64 data
      );
      
      // Background solving now happens entirely in background isolate
      // No need for main process solving - background isolate handles everything
      
      print('🚀 Background solving started for image problem');
      
    } catch (e) {
      print('❌ Failed to start background solving: $e');
      throw MathSolverException('Failed to start background solving: $e');
    }
  }

  /// Start background solving for text-only problem
  Future<void> solveFromTextInBackground(String problemText, {String? title}) async {
    await _initializeBackgroundServices();
    
    try {
      // Create problem record for tracking
      final problemId = const Uuid().v4();
      final problem = MathProblem(
        id: problemId,
        originalInput: problemText,
        inputType: ProblemInputType.text,
        createdAt: DateTime.now(),
        status: ProblemStatus.solving,
      );
      
      // Save initial problem to database
      await _databaseService.saveMathProblem(problem);
      print('✅ Background problem saved with ID: $problemId');
      
      // Register background task for true background solving
      await _backgroundTaskService.startBackgroundSolving(
        problemId: problemId,
        problemText: problemText,
        problemType: 'text',
      );
      
      // Background solving now happens entirely in background isolate
      // No need for main process solving - background isolate handles everything
      
      print('🚀 Background solving started for text problem');
      
    } catch (e) {
      print('❌ Failed to start background solving: $e');
      throw MathSolverException('Failed to start background solving: $e');
    }
  }

  /// Start background solving for mixed image+text problem
  Future<void> solveFromImageWithTextInBackground(Uint8List imageBytes, String userQuestion, {String? title}) async {
    await _initializeBackgroundServices();
    
    try {
      // Create problem record for tracking
      final problemId = const Uuid().v4();
      final problem = MathProblem(
        id: problemId,
        originalInput: userQuestion,
        inputType: ProblemInputType.image,
        imageBase64: _encodeImageToBase64(imageBytes),
        createdAt: DateTime.now(),
        status: ProblemStatus.solving,
      );
      
      // Save initial problem to database
      await _databaseService.saveMathProblem(problem);
      print('✅ Background problem saved with ID: $problemId');
      
      // Store image data in temporary file to avoid WorkManager 10KB limit
      final imagePath = await _storeImageTemporarily(imageBytes, problemId);
      print('📁 Image stored temporarily at: $imagePath');
      
      // Register background task for true background solving
      await _backgroundTaskService.startBackgroundSolving(
        problemId: problemId,
        problemText: userQuestion,
        problemType: 'imageWithText',
        imagePath: imagePath, // Pass file path instead of base64 data
        userQuestion: userQuestion,
      );
      
      // Background solving now happens entirely in background isolate
      // No need for main process solving - background isolate handles everything
      
      print('🚀 Background solving started for mixed image+text problem');
      
    } catch (e) {
      print('❌ Failed to start background solving: $e');
      throw MathSolverException('Failed to start background solving: $e');
    }
  }

  /// Cancel background solving task
  Future<void> cancelBackgroundSolving() async {
    try {
      await _backgroundTaskService.cancelAllBackgroundTasks();
      print('🛑 All background solving tasks cancelled');
    } catch (e) {
      print('⚠️ Failed to cancel background tasks: $e');
    }
  }

  /// Store image data temporarily to avoid WorkManager 10KB limit
  Future<String> _storeImageTemporarily(Uint8List imageBytes, String problemId) async {
    try {
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(tempDir.path, 'background_images');
      
      // Create directory if it doesn't exist
      final directory = Directory(tempPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // Create unique filename
      final fileName = '${problemId}_image.jpg';
      final filePath = path.join(tempPath, fileName);
      
      // Write image data to file
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      
      print('📁 Image stored temporarily: $filePath (${imageBytes.length} bytes)');
      return filePath;
    } catch (e) {
      print('❌ Failed to store image temporarily: $e');
      throw MathSolverException('Failed to store image temporarily: $e');
    }
  }

  /// Clean up temporary image files
  Future<void> _cleanupTemporaryImages() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(tempDir.path, 'background_images');
      final directory = Directory(tempPath);
      
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        print('🧹 Temporary image files cleaned up');
      }
    } catch (e) {
      print('⚠️ Failed to cleanup temporary images: $e');
    }
  }

  /// Check if background services are available
  bool get isBackgroundSolvingAvailable => _backgroundServicesInitialized;

  /// Dispose resources
  Future<void> dispose() async {
    await _cleanupTemporaryImages();
    await _databaseService.close();
    _isInitialized = false;
  }
}

/// Represents a structured math solution
class MathSolution {
  final String answer;
  final String explanation;

  MathSolution({
    required this.answer,
    required this.explanation,
  });
}

/// Custom exception for math solver operations
class MathSolverException implements Exception {
  final String message;
  MathSolverException(this.message);
  
  @override
  String toString() => 'MathSolverException: $message';
}
