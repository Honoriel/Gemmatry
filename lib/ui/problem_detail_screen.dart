import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';
import '../models/math_problem.dart';
import '../models/chat_message.dart';
import '../services/math_solver_service.dart';
import '../widgets/math_markdown_widget.dart';

// Book Theme Colors
class NaturalTheme {
  // Professional artisan paper design - gradient backgrounds
  static const Color artisanPaperLight = Color(0xFFFDFBF8); // Light artisan paper
  static const Color artisanPaperDark = Color(0xFFF8F5F2);  // Dark artisan paper
  static const Color creamPaper = Color(0xFFFDFBF8);        // Primary background
  static const Color vintageWhite = Color(0xFFFAF8F3);      // Soft vintage white
  static const Color paperWhite = Color(0xFFF7F4EF);        // Natural paper tone
  static const Color softIvory = Color(0xFFF2EFE8);         // Muted ivory
  
  // Professional color palette
  static const Color charcoalText = Color(0xFF333333);      // Dark charcoal text
  static const Color terracottaAccent = Color(0xFFB87A6D);  // Dusty terracotta primary
  static const Color dustyTerracotta = Color(0xFFB87A6D);   // Alias for terracotta
  static const Color paperLight = Color(0xFFFDFBF8);        // Light paper background
  static const Color oliveAccent = Color(0xFF6A7A63);       // Deep olive green
  static const Color beigeCard = Color(0xFFEAE6E1);         // Light beige for cards
  static const Color creamButton = Color(0xFFFDFBF8);       // Light cream for button text
  
  // Legacy earth tones - for existing compatibility
  static const Color warmBeige = Color(0xFFD4C4A8);         // Header beige
  static const Color richTerracotta = terracottaAccent;     // Primary accent
  static const Color mutedClay = Color(0xFF8B6F47);         // Muted clay brown
  static const Color darkWarmBrown = Color(0xFF6B4E32);     // Darker, warmer brown
  static const Color warmerBrown = Color(0xFF65350F);       // Even warmer brown
  static const Color deepEarth = charcoalText;              // Dark text
  
  // Sophisticated accent colors
  static const Color dustyGold = Color(0xFFB8A082);         // Refined gold
  static const Color sageGreen = oliveAccent;               // Natural sage
  static const Color clayRose = Color(0xFFAA8B7A);          // Warm clay rose
  static const Color sandstone = Color(0xFFC4B59C);         // Light sandstone
  
  // Text colors - professional hierarchy
  static const Color primaryText = charcoalText;            // Dark charcoal (#333333)
  static const Color secondaryText = Color(0xFF6B5B4F);     // Medium earth
  static const Color mutedText = Color(0xFF9A8B7D);         // Muted earth
  
  // Functional colors - earth-toned versions
  static const Color successGreen = Color(0xFF6B8E5A);      // Natural green
  static const Color warningAmber = Color(0xFFB8956B);      // Earth amber
  static const Color errorRed = Color(0xFFA67C7C);          // Muted terracotta red
  
  // Additional theme properties for history screen
  static const Color paperBorder = Color(0xFFE5DDD5);       // Subtle paper border
  static const Color shadowColor = Color(0xFF8B7355);       // Natural shadow
  
  // Status color gradients
  static const Color successLight = Color(0xFF8FAF7A);      // Light success green
  static const Color successDark = Color(0xFF5A7A4A);       // Dark success green
  static const Color errorLight = Color(0xFFB89C9C);        // Light error red
  static const Color errorDark = Color(0xFF8B5A5A);         // Dark error red
  static const Color warningLight = Color(0xFFD4B885);      // Light warning amber
  static const Color warningDark = Color(0xFF9A7B4B);       // Dark warning amber
  
  // Legacy compatibility - map old names to new professional colors
  static const Color deepBlue = charcoalText;               // Dark charcoal instead of blue
  static const Color academicBlue = mutedClay;              // Clay brown instead of blue
  static const Color lightBlue = sageGreen;                 // Sage green accent
  static const Color softBlue = clayRose;                   // Clay rose accent
  static const Color richBrown = richTerracotta;            // Rich terracotta
  static const Color warmBrown = warmerBrown;               // Even warmer brown
  static const Color goldAccent = dustyGold;                // Refined gold
  static const Color lightGold = sandstone;                 // Light sandstone
}

class ProblemDetailScreen extends StatefulWidget {
  final MathProblem problem;

  const ProblemDetailScreen({
    Key? key,
    required this.problem,
  }) : super(key: key);

  @override
  State<ProblemDetailScreen> createState() => _ProblemDetailScreenState();
}

class _ProblemDetailScreenState extends State<ProblemDetailScreen> {
  final MathSolverService _mathSolver = MathSolverService();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<ChatMessage> _chatMessages = [];
  bool _isSendingMessage = false;
  bool _isLoadingSolution = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    // Removed automatic solving to prevent loops on app startup
    // Problems should already be solved when navigating to this screen
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    try {
      final messages = await _mathSolver.getChatHistory(widget.problem.id);
      setState(() {
        _chatMessages = messages;
      });
    } catch (e) {
      print('Error loading chat history: $e');
    }
  }

  // Note: Automatic solving removed to prevent loops
  // Problems should be solved before navigating to this screen

  Future<void> _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty || _isSendingMessage) return;

    setState(() {
      _isSendingMessage = true;
    });

    // Clear input immediately and show user message
    _chatController.clear();
    
    // Create user message and add to UI immediately
    final userMessage = ChatMessage(
      id: const Uuid().v4(),
      problemId: widget.problem.id,
      message: message,
      isUser: true,
      createdAt: DateTime.now(),
    );
    
    // Create AI placeholder message
    final aiPlaceholderId = const Uuid().v4();
    final aiPlaceholder = ChatMessage(
      id: aiPlaceholderId,
      problemId: widget.problem.id,
      message: '🤔 Thinking about your question...',
      isUser: false,
      createdAt: DateTime.now(),
    );
    
    setState(() {
      _chatMessages.addAll([userMessage, aiPlaceholder]);
    });
    
    // Scroll to bottom to show new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      print('🔄 Sending follow-up message: $message');
      
      // Send message to service (which handles AI response and database saving)
      final response = await _mathSolver.continueConversation(
        widget.problem.id,
        message,
      );
      
      print('✅ Follow-up response received: ${response.length} characters');
      
      // Replace placeholder with actual AI response
      final aiResponse = ChatMessage(
        id: aiPlaceholderId, // Keep same ID to replace placeholder
        problemId: widget.problem.id,
        message: response,
        isUser: false,
        createdAt: DateTime.now(),
      );
      
      setState(() {
        // Find and replace the placeholder message
        final placeholderIndex = _chatMessages.indexWhere((msg) => msg.id == aiPlaceholderId);
        if (placeholderIndex != -1) {
          _chatMessages[placeholderIndex] = aiResponse;
        }
      });
      
      print('✅ AI response displayed in chat');

      // Scroll to bottom to show the response
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      
    } catch (e) {
      print('❌ Error sending follow-up message: $e');
      
      // Replace placeholder with error message
      setState(() {
        final placeholderIndex = _chatMessages.indexWhere((msg) => msg.id == aiPlaceholderId);
        if (placeholderIndex != -1) {
          _chatMessages[placeholderIndex] = ChatMessage(
            id: aiPlaceholderId,
            problemId: widget.problem.id,
            message: '❌ Sorry, I encountered an error while processing your question. Please try again.',
            isUser: false,
            createdAt: DateTime.now(),
          );
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: $e'),
          backgroundColor: NaturalTheme.errorRed,
        ),
      );
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Widget _buildProblemCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: NaturalTheme.vintageWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: NaturalTheme.goldAccent.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: NaturalTheme.deepBlue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with book aesthetic
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  NaturalTheme.richBrown.withOpacity(0.1),
                  NaturalTheme.warmBrown.withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        NaturalTheme.richBrown.withOpacity(0.2),
                        NaturalTheme.richBrown.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.quiz_outlined,
                    color: NaturalTheme.richBrown,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Problem Statement',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NaturalTheme.deepBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.problem.displayTitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: NaturalTheme.secondaryText,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: NaturalTheme.academicBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.content_copy_outlined,
                      color: NaturalTheme.academicBlue,
                      size: 18,
                    ),
                    onPressed: () => _copyToClipboard(widget.problem.originalInput),
                    tooltip: 'Copy problem text',
                  ),
                ),
              ],
            ),
          ),
          
          // Content area
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display image if available with book aesthetic
                if (widget.problem.inputType == ProblemInputType.image && 
                    widget.problem.imageBase64 != null) ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          NaturalTheme.creamPaper.withOpacity(0.3),
                          NaturalTheme.creamPaper.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: NaturalTheme.goldAccent.withOpacity(0.4),
                        width: 2,
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
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Image.memory(
                          base64Decode(widget.problem.imageBase64!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Problem text with book aesthetic
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        NaturalTheme.paperWhite,
                        NaturalTheme.creamPaper.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: NaturalTheme.academicBlue.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: NaturalTheme.deepBlue.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            color: NaturalTheme.academicBlue,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Problem',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: NaturalTheme.academicBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      MathMarkdownWidget(
                        data: widget.problem.originalInput,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            height: 1.6,
                            fontSize: 15,
                            color: NaturalTheme.primaryText,
                            letterSpacing: 0.2,
                          ),
                          code: TextStyle(
                            backgroundColor: NaturalTheme.creamPaper.withOpacity(0.5),
                            color: NaturalTheme.richBrown,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSolutionCard() {
    if (!widget.problem.isSolved) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: NaturalTheme.vintageWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: NaturalTheme.goldAccent.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: NaturalTheme.deepBlue.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      NaturalTheme.academicBlue.withOpacity(0.1),
                      NaturalTheme.academicBlue.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(NaturalTheme.academicBlue),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Analyzing the Problem',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: NaturalTheme.deepBlue,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Our AI companion is carefully working through\nyour problem step by step...',
                style: TextStyle(
                  fontSize: 14,
                  color: NaturalTheme.secondaryText,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: NaturalTheme.vintageWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: NaturalTheme.goldAccent.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: NaturalTheme.deepBlue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with book aesthetic
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  NaturalTheme.academicBlue.withOpacity(0.1),
                  NaturalTheme.academicBlue.withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        NaturalTheme.academicBlue.withOpacity(0.2),
                        NaturalTheme.academicBlue.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lightbulb_outline,
                    color: NaturalTheme.academicBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solution',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NaturalTheme.deepBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Complete answer with detailed explanation',
                        style: TextStyle(
                          fontSize: 13,
                          color: NaturalTheme.secondaryText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: NaturalTheme.richBrown.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.content_copy_outlined,
                      color: NaturalTheme.richBrown,
                      size: 18,
                    ),
                    onPressed: () => _copyToClipboard(widget.problem.solution ?? ''),
                    tooltip: 'Copy solution',
                  ),
                ),
              ],
            ),
          ),
          
          // Content area
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Answer section with book aesthetic
                if (widget.problem.solution?.isNotEmpty == true) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFE8F5E8),
                          const Color(0xFFF0F8F0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.check_circle_outline,
                                color: const Color(0xFF2E7D32),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Final Answer',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2E7D32),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF4CAF50).withOpacity(0.2),
                            ),
                          ),
                          child: MathMarkdownWidget(
                            data: widget.problem.solution!,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: NaturalTheme.primaryText,
                                height: 1.4,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Explanation section with book aesthetic
                if (widget.problem.stepByStepExplanation?.isNotEmpty == true) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          NaturalTheme.paperWhite,
                          NaturalTheme.creamPaper.withOpacity(0.3),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: NaturalTheme.warmBrown.withOpacity(0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: NaturalTheme.deepBlue.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: NaturalTheme.warmBrown.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.auto_stories_outlined,
                                color: NaturalTheme.warmBrown,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Step-by-Step Explanation',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: NaturalTheme.warmBrown,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(
                            maxWidth: double.infinity,
                          ),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: NaturalTheme.warmBrown.withOpacity(0.2),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: MathMarkdownWidget(
                              data: widget.problem.stepByStepExplanation!,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  height: 1.6,
                                  fontSize: 14,
                                  color: NaturalTheme.primaryText,
                                  letterSpacing: 0.2,
                                ),
                                code: TextStyle(
                                  fontFamily: 'monospace',
                                  backgroundColor: NaturalTheme.creamPaper.withOpacity(0.5),
                                  color: NaturalTheme.richBrown,
                                  fontSize: 13,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: NaturalTheme.creamPaper.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: NaturalTheme.goldAccent.withOpacity(0.3),
                                  ),
                                ),
                                blockquote: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: NaturalTheme.secondaryText,
                                  fontSize: 14,
                                ),
                                h1: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: NaturalTheme.deepBlue,
                                  fontSize: 18,
                                ),
                                h2: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: NaturalTheme.academicBlue,
                                  fontSize: 16,
                                ),
                                h3: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: NaturalTheme.richBrown,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection() {
    if (_chatMessages.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: NaturalTheme.vintageWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: NaturalTheme.goldAccent.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: NaturalTheme.deepBlue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with book aesthetic
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7B1FA2).withOpacity(0.1),
                  const Color(0xFF7B1FA2).withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF7B1FA2).withOpacity(0.2),
                        const Color(0xFF7B1FA2).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.forum_outlined,
                    color: const Color(0xFF7B1FA2),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Academic Discussion',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NaturalTheme.deepBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Follow-up questions and clarifications',
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
          ),
          
          // Chat messages with book aesthetic
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: _chatMessages.map((message) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: message.isUser 
                            ? [
                                NaturalTheme.academicBlue.withOpacity(0.2),
                                NaturalTheme.academicBlue.withOpacity(0.1),
                              ]
                            : [
                                NaturalTheme.richBrown.withOpacity(0.2),
                                NaturalTheme.richBrown.withOpacity(0.1),
                              ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: message.isUser 
                            ? NaturalTheme.academicBlue.withOpacity(0.3)
                            : NaturalTheme.richBrown.withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        message.isUser ? Icons.person_outline : Icons.auto_awesome_outlined,
                        color: message.isUser ? NaturalTheme.academicBlue : NaturalTheme.richBrown,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Message bubble
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: message.isUser 
                              ? [
                                  const Color(0xFFE3F2FD),
                                  const Color(0xFFF3F9FF),
                                ]
                              : [
                                  NaturalTheme.creamPaper.withOpacity(0.4),
                                  NaturalTheme.paperWhite,
                                ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: message.isUser 
                              ? NaturalTheme.academicBlue.withOpacity(0.2)
                              : NaturalTheme.warmBrown.withOpacity(0.2),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: NaturalTheme.deepBlue.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sender label
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: message.isUser 
                                      ? NaturalTheme.academicBlue.withOpacity(0.1)
                                      : NaturalTheme.richBrown.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    message.isUser ? 'Student' : 'AI Tutor',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: message.isUser 
                                        ? NaturalTheme.academicBlue
                                        : NaturalTheme.richBrown,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Message content
                            MathMarkdownWidget(
                              data: message.message,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  height: 1.5,
                                  fontSize: 14,
                                  color: NaturalTheme.primaryText,
                                  letterSpacing: 0.2,
                                ),
                                code: TextStyle(
                                  fontFamily: 'monospace',
                                  backgroundColor: Colors.white.withOpacity(0.8),
                                  color: NaturalTheme.richBrown,
                                  fontSize: 13,
                                  letterSpacing: 0.1,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: NaturalTheme.goldAccent.withOpacity(0.3),
                                  ),
                                ),
                                blockquote: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: NaturalTheme.secondaryText,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            NaturalTheme.paperWhite,
            NaturalTheme.creamPaper.withOpacity(0.3),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: NaturalTheme.goldAccent.withOpacity(0.3),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: NaturalTheme.deepBlue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      NaturalTheme.paperWhite,
                      NaturalTheme.vintageWhite,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: NaturalTheme.academicBlue.withOpacity(0.3),
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
                  controller: _chatController,
                  style: TextStyle(
                    color: NaturalTheme.primaryText,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask a follow-up question about this problem...',
                    hintStyle: TextStyle(
                      color: NaturalTheme.secondaryText,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    prefixIcon: Container(
                      margin: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        color: NaturalTheme.academicBlue.withOpacity(0.6),
                        size: 20,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _sendChatMessage(),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    NaturalTheme.academicBlue,
                    NaturalTheme.deepBlue,
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: NaturalTheme.academicBlue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _isSendingMessage ? null : _sendChatMessage,
                icon: _isSendingMessage
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            NaturalTheme.paperWhite,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: NaturalTheme.paperWhite,
                        size: 20,
                      ),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  minimumSize: const Size(44, 44),
                ),
                tooltip: 'Send message',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NaturalTheme.paperWhite,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    NaturalTheme.goldAccent.withOpacity(0.2),
                    NaturalTheme.goldAccent.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.auto_stories,
                color: NaturalTheme.deepBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.problem.displayTitle.isNotEmpty 
                        ? widget.problem.displayTitle 
                        : 'Problem',
                    style: TextStyle(
                      color: NaturalTheme.paperWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Problem Analysis & Solution',
                    style: TextStyle(
                      color: NaturalTheme.paperWhite.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: NaturalTheme.deepBlue,
        foregroundColor: NaturalTheme.paperWhite,
        elevation: 0,
        toolbarHeight: 70,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: NaturalTheme.paperWhite.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(
                Icons.share_outlined,
                color: NaturalTheme.paperWhite,
                size: 20,
              ),
              onPressed: () {
                final shareText = '''Problem: ${widget.problem.originalInput}
                
${widget.problem.isSolved ? 'Answer: ${widget.problem.solution}\n\nExplanation: ${widget.problem.stepByStepExplanation}' : 'Solution pending...'}''';
                
                Clipboard.setData(ClipboardData(text: shareText));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Problem copied to clipboard',
                      style: TextStyle(color: NaturalTheme.paperWhite),
                    ),
                    backgroundColor: NaturalTheme.deepBlue,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NaturalTheme.paperWhite,
                    NaturalTheme.creamPaper.withOpacity(0.3),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Problem info header with book aesthetic
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            NaturalTheme.academicBlue.withOpacity(0.1),
                            NaturalTheme.academicBlue.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: NaturalTheme.academicBlue.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NaturalTheme.deepBlue.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  NaturalTheme.academicBlue.withOpacity(0.2),
                                  NaturalTheme.academicBlue.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              widget.problem.inputType == ProblemInputType.image 
                                  ? Icons.image_outlined 
                                  : Icons.functions,
                              color: NaturalTheme.academicBlue,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.problem.inputType == ProblemInputType.image 
                                      ? 'Visual Problem' 
                                      : 'Textual Problem',
                                  style: TextStyle(
                                    color: NaturalTheme.academicBlue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Problem ID: ${widget.problem.id.substring(0, 8)}',
                                  style: TextStyle(
                                    color: NaturalTheme.mutedText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: widget.problem.isSolved
                                  ? NaturalTheme.successGreen.withOpacity(0.1)
                                  : NaturalTheme.warningAmber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: widget.problem.isSolved
                                    ? NaturalTheme.successGreen.withOpacity(0.3)
                                    : NaturalTheme.warningAmber.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              widget.problem.isSolved ? 'Solved' : 'Pending',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: widget.problem.isSolved
                                    ? NaturalTheme.successGreen
                                    : NaturalTheme.warningAmber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Problem content card with book aesthetic
                    _buildProblemCard(),
                    
                    const SizedBox(height: 20),
                    
                    // Solution card with book aesthetic
                    _buildSolutionCard(),
                    
                    const SizedBox(height: 20),
                    
                    // Chat section with book aesthetic
                    _buildChatSection(),
                    
                    // Add some bottom padding for better scrolling
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
          
          // Chat input at bottom with book aesthetic
          _buildChatInput(),
        ],
      ),
    );
  }
}
