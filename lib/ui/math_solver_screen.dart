import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/math_solver_service.dart';
import '../models/math_problem.dart';
import 'problem_detail_screen.dart' show ProblemDetailScreen, NaturalTheme;
import 'history_screen.dart' show HistoryScreen;
import '../widgets/math_markdown_widget.dart';

/// Main screen for the math solver application
class MathSolverScreen extends StatefulWidget {
  const MathSolverScreen({super.key});

  @override
  State<MathSolverScreen> createState() => _MathSolverScreenState();
}

class _MathSolverScreenState extends State<MathSolverScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final MathSolverService _mathSolver = MathSolverService();
  final ImagePicker _imagePicker = ImagePicker();

  Uint8List? _selectedImage;
  String? _selectedImageName;
  bool _isProcessing = false;
  String _statusMessage = '';
  List<MathProblem> _recentProblems = [];
  
  // Loading overlay state
  OverlayEntry? _loadingOverlay;
  String _loadingMessage = 'Processing your problem...';
  
  // Background processing state
  String? _currentProblemId;
  bool _isBackgroundProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeService();
    _loadRecentProblems();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _hideLoadingOverlay(); // Clean up overlay if still showing
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App is going to background
      if (_isProcessing && !_isBackgroundProcessing) {
        print('📱 App going to background during solving - transitioning to background processing');
        _transitionToBackgroundProcessing();
      }
    } else if (state == AppLifecycleState.resumed) {
      // App is coming back to foreground
      if (_isBackgroundProcessing) {
        print('📱 App resumed from background - checking background processing status');
        _checkBackgroundProcessingStatus();
      }
    }
  }

  Future<void> _initializeService() async {
    try {
      setState(() {
        _statusMessage = 'Initializing math solver...';
      });
      await _mathSolver.initialize();
      setState(() {
        _statusMessage = '';
      });
      _showStatusSnackBar('Ready to solve math problems!', isSuccess: true);
    } catch (e) {
      setState(() {
        _statusMessage = '';
      });
      _showErrorSnackBar('Error initializing: $e');
    }
  }

  Future<void> _loadRecentProblems() async {
    try {
      final problems = await _mathSolver.getHistory();
      setState(() {
        _recentProblems = problems.take(5).toList();
      });
    } catch (e) {
      debugPrint('Error loading recent problems: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final imageBytes = await image.readAsBytes();
        setState(() {
          _selectedImage = imageBytes;
          _selectedImageName = image.name;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final imageBytes = await image.readAsBytes();
        setState(() {
          _selectedImage = imageBytes;
          _selectedImageName = image.name;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<void> _solveProblem() async {
    final text = _textController.text.trim();
    final image = _selectedImage;

    if (text.isEmpty && image == null) {
      _showErrorSnackBar('Please enter a math problem or take a photo');
      return;
    }

    if (_isProcessing) return;

    // The actual problem ID will be set by the solving method
    _currentProblemId = null;
    
    // Always use foreground solving - background processing will be handled automatically
    // when the app is sent to background during solving
    await _startForegroundSolving(text, image);
  }

  /// Transition current foreground solving to background processing
  Future<void> _transitionToBackgroundProcessing() async {
    if (!_isProcessing || _isBackgroundProcessing) return;
    
    try {
      print('🔄 Transitioning to background processing...');
      
      // CRITICAL: Inform the service to preserve solving state for background continuation
      // This ensures _currentSolvingProblemId and _isBackgroundMode are set correctly
      String problemText = '';
      Uint8List? imageBytes;
      
      // Reconstruct problem context for service state preservation
      if (_selectedImage != null) {
        imageBytes = _selectedImage;
        problemText = _textController.text.trim();
      } else {
        problemText = _textController.text.trim();
      }
      
      // Call service method to preserve solving state and enable background mode
      await _mathSolver.continueInBackground(
        problemText, 
        imageBytes: imageBytes,
        problemId: _currentProblemId,
      );
      
      // Mark as background processing but keep the current process running
      setState(() {
        _isBackgroundProcessing = true;
        // Keep _isProcessing = true so the current solve continues
        _statusMessage = 'Solving continues in background! You\'ll get a notification when it\'s done.';
      });
      
      // Hide loading overlay since we're going to background
      // But remember that we had an active overlay for resume
      _hideLoadingOverlay();
      
      print('✅ Successfully transitioned to background - existing process continues');
    } catch (e) {
      print('❌ Error transitioning to background: $e');
      // If background transition fails, continue with foreground processing
      setState(() {
        _isBackgroundProcessing = false;
      });
    }
  }
  
  /// Check the status of background processing when app resumes
  Future<void> _checkBackgroundProcessingStatus() async {
    if (!_isBackgroundProcessing) return;
    
    try {
      print('🔍 Checking background processing status...');
      
      // First, restore the current problem ID from the service if we don't have it
      if (_currentProblemId == null) {
        _currentProblemId = _mathSolver.getCurrentSolvingProblemId();
        print('🔄 Restored current problem ID from service: $_currentProblemId');
      }
      
      // Check if the current problem is still being solved using the service method
      bool isSolveStillActive = _mathSolver.isCurrentlySolving(_currentProblemId);
      
      MathProblem? currentProblem;
      if (_currentProblemId != null) {
        // Get the current problem from database to check its status
        final problems = await _mathSolver.getRecentProblems(limit: 10);
        try {
          currentProblem = problems.firstWhere(
            (p) => p.id == _currentProblemId,
          );
          
          // If service says solving is active, trust that over database status
          if (isSolveStillActive) {
            print('🔄 Service confirms problem is still being solved - showing loading screen');
          } else if (currentProblem.status == ProblemStatus.solved) {
            print('✅ Background solving completed successfully');
            
            // Show success message and navigate to the solution
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Problem solved successfully in background!'),
                  backgroundColor: Colors.green,
                  action: SnackBarAction(
                    label: 'View Solution',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProblemDetailScreen(problem: currentProblem!),
                        ),
                      );
                    },
                  ),
                ),
              );
            }
          } else {
            print('⚠️ Problem found but status is ${currentProblem.status} and service says not solving');
          }
        } catch (e) {
          print('⚠️ Problem $_currentProblemId not found in recent problems: $e');
          // If problem not found but service says still solving, trust the service
          if (isSolveStillActive) {
            print('🔄 Service says still solving despite problem not found in recent list');
          }
        }
      }
      
      // Only reset processing state if solving is actually complete
      if (!isSolveStillActive) {
        setState(() {
          _isBackgroundProcessing = false;
          _isProcessing = false;
          _currentProblemId = null;
          _statusMessage = 'Ready to solve math problems!';
        });
      } else {
        // Solving is still active - show loading screen and keep processing state
        setState(() {
          _isProcessing = true; // Show loading screen
          _statusMessage = 'Continuing to solve in foreground...';
        });
        
        // Use a small delay to ensure the UI is ready before showing overlay
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _isProcessing) {
            print('🔄 Showing loading overlay on resume');
            _showLoadingOverlay();
          }
        });
      }
      
      // Refresh the recent problems list
      await _loadRecentProblems();
      
      print('✅ Background processing status check completed');
    } catch (e) {
      print('❌ Error checking background status: $e');
      
      // Reset state on error
      setState(() {
        _isBackgroundProcessing = false;
        _isProcessing = false;
        _currentProblemId = null;
        _statusMessage = 'Ready to solve math problems!';
      });
    }
  }



  Future<void> _startForegroundSolving(String text, Uint8List? image) async {
    // Show loading overlay
    _showLoadingOverlay();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing your problem...';
    });

    try {
      MathProblem problem;
      
      if (image != null && text.isNotEmpty) {
        // Mixed input mode: image + user text question
        _updateLoadingMessage('Analyzing image with your question...');
        problem = await _mathSolver.solveFromImageWithText(image, text, onStatusUpdate: _updateLoadingMessage);
      } else if (image != null) {
        // Image-only mode: extract problem from image
        _updateLoadingMessage('Extracting text from image...');
        problem = await _mathSolver.solveFromImage(image, onStatusUpdate: _updateLoadingMessage);
      } else {
        // Text-only mode: solve text problem
        _updateLoadingMessage('Solving your problem...');
        problem = await _mathSolver.solveFromText(text, onStatusUpdate: _updateLoadingMessage);
      }

      // Store the actual problem ID for tracking
    _currentProblemId = problem.id;
    
    // Clear inputs only if we're not in background processing mode
    if (!_isBackgroundProcessing) {
      _textController.clear();
      setState(() {
        _selectedImage = null;
        _selectedImageName = null;
        _statusMessage = '';
      });
      _showStatusSnackBar('Problem solved successfully!', isSuccess: true);
    } else {
      setState(() {
        _statusMessage = '';
      });
      _showStatusSnackBar('Problem solved successfully!', isSuccess: true);
    }

      // Hide loading overlay
      _hideLoadingOverlay();

      // Navigate to problem detail screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProblemDetailScreen(problem: problem),
          ),
        ).then((_) => _loadRecentProblems());
      }

    } catch (e) {
      _hideLoadingOverlay();
      _showErrorSnackBar('Failed to solve problem: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _currentProblemId = null; // Clear tracking ID when done
        _statusMessage = '';
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: NaturalTheme.errorRed,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showStatusSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.lato(
            color: NaturalTheme.creamButton,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isSuccess ? NaturalTheme.successGreen : NaturalTheme.mutedClay,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showLoadingOverlay() {
    // Don't show overlay if one is already active
    if (_loadingOverlay != null) {
      print('⚠️ Loading overlay already exists, skipping');
      return;
    }
    
    print('🔄 Creating and showing loading overlay');
    _loadingOverlay = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  strokeWidth: 3,
                ),
                const SizedBox(height: 24),
                Text(
                  _loadingMessage,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take a few minutes...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_loadingOverlay!);
    print('✅ Loading overlay inserted into overlay stack');
  }

  void _updateLoadingMessage(String message) {
    setState(() {
      _loadingMessage = message;
      _statusMessage = message;
    });
    
    // Update overlay if it exists
    if (_loadingOverlay != null) {
      _loadingOverlay!.markNeedsBuild();
    }
  }

  void _hideLoadingOverlay() {
    if (_loadingOverlay != null) {
      print('🔄 Hiding loading overlay');
      _loadingOverlay?.remove();
      _loadingOverlay = null;
      print('✅ Loading overlay removed and cleared');
    } else {
      print('⚠️ No loading overlay to hide');
    }
  }








  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NaturalTheme.artisanPaperLight,
              NaturalTheme.artisanPaperDark,
            ],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              'Gemmatry',
              style: GoogleFonts.lora(
                color: NaturalTheme.primaryText,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            backgroundColor: NaturalTheme.paperLight.withOpacity(0.85),
            foregroundColor: NaturalTheme.primaryText,
            elevation: 0,
            toolbarHeight: 60,
            flexibleSpace: ClipRRect(
              child: Container(
                decoration: BoxDecoration(
                  color: NaturalTheme.paperLight.withOpacity(0.85),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      offset: const Offset(0, 2),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      offset: const Offset(0, 4),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: NaturalTheme.dustyTerracotta.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.history_edu,
                    size: 20,
                    color: NaturalTheme.dustyTerracotta,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HistoryScreen(),
                      ),
                    );
                  },
                  tooltip: 'Problem History',
                ),
              ),
            ],
      ),
      body: Column(
        children: [
          // Status messages now handled by snackbars instead of header display

          // Main content
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NaturalTheme.paperWhite,
                    NaturalTheme.creamPaper.withOpacity(0.5),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main input section with book aesthetic
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: NaturalTheme.beigeCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: NaturalTheme.warmBeige.withOpacity(0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NaturalTheme.deepBlue.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: NaturalTheme.sandstone.withOpacity(0.3),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with book-style decoration
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        NaturalTheme.warmBeige.withOpacity(0.3),
                                        NaturalTheme.lightGold.withOpacity(0.3),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: NaturalTheme.warmBeige.withOpacity(0.6),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.calculate,
                                    color: NaturalTheme.deepEarth,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Problem Solver',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 24, // h2 size
                                          fontWeight: FontWeight.w700,
                                          color: NaturalTheme.deepEarth,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedImage != null
                                            ? 'Analyze image, text, or combine both for contextual solving'
                                            : 'Enter a problem or upload an image of it',
                                        style: GoogleFonts.lato(
                                          fontSize: 14,
                                          color: NaturalTheme.secondaryText,
                                          height: 1.4,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Decorative divider
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    NaturalTheme.warmBeige.withOpacity(0.4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                          
                            // Text input with book aesthetic
                            Container(
                              decoration: BoxDecoration(
                                color: NaturalTheme.paperWhite,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: NaturalTheme.academicBlue.withOpacity(0.2),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: NaturalTheme.deepBlue.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _textController,
                                maxLines: 4,
                                style: GoogleFonts.lato(
                                  fontSize: 16,
                                  color: NaturalTheme.primaryText,
                                  height: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: _selectedImage != null 
                                      ? 'Ask a question about the image below...\n\nExample: "What is the area of this triangle if the base is 5cm?"'
                                      : 'Enter your problem here...\n\nExample: "Solve for x: 2x + 5 = 13"',
                                  hintStyle: GoogleFonts.lato(
                                    fontSize: 15,
                                    color: NaturalTheme.mutedText,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.all(20),
                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: NaturalTheme.lightBlue.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.edit_note,
                                      color: NaturalTheme.academicBlue,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          
                          const SizedBox(height: 16),
                          
                            const SizedBox(height: 20),
                            
                            // Image section with book aesthetic
                            if (_selectedImage != null) ...[
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: NaturalTheme.creamPaper,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: NaturalTheme.warmBeige.withOpacity(0.5),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: NaturalTheme.deepBlue.withOpacity(0.1),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Image header
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: NaturalTheme.academicBlue.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.image,
                                              color: NaturalTheme.deepEarth,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Image',
                                              style: GoogleFonts.lato(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: NaturalTheme.deepEarth,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: NaturalTheme.errorRed.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: IconButton(
                                              onPressed: () {
                                                setState(() {
                                                  _selectedImage = null;
                                                  _selectedImageName = null;
                                                });
                                              },
                                              icon: Icon(
                                                Icons.close,
                                                color: NaturalTheme.errorRed,
                                                size: 18,
                                              ),
                                              tooltip: 'Remove image',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // Image display
                                      Container(
                                        width: double.infinity,
                                        height: 220,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: NaturalTheme.academicBlue.withOpacity(0.2),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: NaturalTheme.deepBlue.withOpacity(0.1),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.memory(
                                            _selectedImage!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      // Image info
                                      Text(
                                        _selectedImageName ?? 'Problem image',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: NaturalTheme.secondaryText,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          

                          
                          const SizedBox(height: 16),
                          
                            // Action buttons with book aesthetic
                            Column(
                              children: [
                                // Image input buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: NaturalTheme.warmBrown,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: NaturalTheme.warningAmber.withOpacity(0.4),
                                            width: 2.0,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.4),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3),
                                            ),
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: _isProcessing ? null : _pickImage,
                                            borderRadius: BorderRadius.circular(16),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: NaturalTheme.creamButton.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    Icons.camera_alt,
                                                    color: NaturalTheme.creamButton,
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Camera',
                                                  style: GoogleFonts.lato(
                                                    color: NaturalTheme.creamButton,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: NaturalTheme.warmBrown,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: NaturalTheme.warningAmber.withOpacity(0.4),
                                            width: 2.0,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.4),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3),
                                            ),
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: _isProcessing ? null : _pickImageFromGallery,
                                            borderRadius: BorderRadius.circular(16),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: NaturalTheme.creamButton.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    Icons.photo_library,
                                                    color: NaturalTheme.creamButton,
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Gallery',
                                                  style: GoogleFonts.lato(
                                                    color: NaturalTheme.creamButton,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                
                                // Solve button
                                Container(
                                  width: double.infinity,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: _isProcessing
                                        ? NaturalTheme.mutedText.withOpacity(0.4)
                                        : NaturalTheme.warmBrown, // Warm light brown solid color
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: NaturalTheme.warningAmber.withOpacity(0.4),
                                      width: 2.0,
                                    ),
                                    boxShadow: _isProcessing
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 16,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _isProcessing ? null : _solveProblem,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          if (_isProcessing) ...[
                                            Container(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  NaturalTheme.creamButton,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                          ] else ...[
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: NaturalTheme.creamButton.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.auto_awesome,
                                                color: NaturalTheme.creamButton,
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                          ],
                                          Text(
                                            _isProcessing 
                                                ? 'Analyzing Problem...' 
                                                : 'Solve the Problem',
                                            style: GoogleFonts.lato(
                                              color: NaturalTheme.creamButton,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                    // Recent problems section with book aesthetic
                    if (_recentProblems.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: NaturalTheme.warmBeige.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: NaturalTheme.warmBrown.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        NaturalTheme.richBrown.withOpacity(0.2),
                                        NaturalTheme.warmBrown.withOpacity(0.1),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.history_edu,
                                    color: NaturalTheme.richBrown,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Recent Problems',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: NaturalTheme.charcoalText,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      Text(
                                        'Review and ask follow-up questions',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: NaturalTheme.secondaryText,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Problems list
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recentProblems.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final problem = _recentProblems[index];
                                return Container(
                                  decoration: BoxDecoration(
                                    color: NaturalTheme.vintageWhite,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: problem.isSolved 
                                          ? NaturalTheme.successGreen.withOpacity(0.3)
                                          : NaturalTheme.warningAmber.withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: NaturalTheme.deepBlue.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ProblemDetailScreen(problem: problem),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            // Problem type indicator
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: problem.isSolved
                                                      ? [
                                                          NaturalTheme.successGreen.withOpacity(0.2),
                                                          NaturalTheme.successGreen.withOpacity(0.1),
                                                        ]
                                                      : [
                                                          NaturalTheme.warningAmber.withOpacity(0.2),
                                                          NaturalTheme.warningAmber.withOpacity(0.1),
                                                        ],
                                                ),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: problem.isSolved
                                                      ? NaturalTheme.successGreen.withOpacity(0.4)
                                                      : NaturalTheme.warningAmber.withOpacity(0.4),
                                                ),
                                              ),
                                              child: Icon(
                                                problem.inputType == ProblemInputType.image
                                                    ? Icons.image_outlined
                                                    : Icons.functions,
                                                color: problem.isSolved
                                                    ? NaturalTheme.successGreen
                                                    : NaturalTheme.warningAmber,
                                                size: 22,
                                              ),
                                            ),
                                            
                                            const SizedBox(width: 16),
                                            
                                            // Problem details
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    problem.displayTitle,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      color: NaturalTheme.primaryText,
                                                      height: 1.3,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.access_time,
                                                        size: 14,
                                                        color: NaturalTheme.mutedText,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        DateFormat('MMM d • h:mm a').format(problem.createdAt),
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: NaturalTheme.mutedText,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: problem.isSolved
                                                              ? NaturalTheme.successGreen.withOpacity(0.1)
                                                              : NaturalTheme.warningAmber.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          problem.isSolved ? 'Solved' : 'Pending',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: problem.isSolved
                                                                ? NaturalTheme.successGreen
                                                                : NaturalTheme.warningAmber,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            
                                            // Arrow indicator
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: NaturalTheme.academicBlue.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.arrow_forward_ios,
                                                size: 14,
                                                color: NaturalTheme.academicBlue,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }


}
