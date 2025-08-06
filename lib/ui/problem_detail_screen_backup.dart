import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/math_problem.dart';
import '../models/chat_message.dart';
import '../services/math_solver_service.dart';
import 'dart:math' as math;

/// Screen showing detailed view of a math problem and its solution
class ProblemDetailScreen extends StatefulWidget {
  final MathProblem problem;

  const ProblemDetailScreen({
    super.key,
    required this.problem,
  });

  @override
  State<ProblemDetailScreen> createState() => _ProblemDetailScreenState();
}

class _ProblemDetailScreenState extends State<ProblemDetailScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MathSolverService _mathSolver = MathSolverService();

  List<ChatMessage> _chatMessages = [];
  bool _isLoadingChat = false;
  bool _isSendingMessage = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    try {
      setState(() {
        _isLoadingChat = true;
      });
      
      final messages = await _mathSolver.getChatHistory(widget.problem.id);
      setState(() {
        _chatMessages = messages;
        _isLoadingChat = false;
      });
      
      // Scroll to bottom after loading
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
      setState(() {
        _isLoadingChat = false;
      });
      debugPrint('Error loading chat history: $e');
    }
  }

  Future<void> _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty || _isSendingMessage) return;

    setState(() {
      _isSendingMessage = true;
    });

    try {
      final response = await _mathSolver.continueConversation(
        widget.problem.id,
        message,
      );

      _chatController.clear();
      await _loadChatHistory(); // Reload to get the new messages

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Parse structured extractor output
  Map<String, dynamic> _parseExtractorOutput(String extractedText) {
    final result = {
      'title': 'Math Problem',
      'mainProblem': extractedText,
      'givenInfo': <String>[],
      'visualsDescription': 'None',
      'subQuestions': <Map<String, String>>[],
    };

    try {
      // Extract title (first line if it looks like a title)
      final lines = extractedText.split('\n');
      if (lines.isNotEmpty) {
        final firstLine = lines[0].trim();
        if (firstLine.startsWith('**') && firstLine.endsWith('**') && firstLine.length < 100) {
          result['title'] = firstLine.replaceAll('*', '').trim();
        } else if (!firstLine.contains('Problem Statement') && firstLine.length < 80) {
          result['title'] = firstLine;
        }
      }

      // Extract main problem statement
      final mainProblemMatch = RegExp(r'\*\*Main Problem Statement:\*\*\s*([\s\S]*?)(?=\*\*|$)', multiLine: true)
          .firstMatch(extractedText);
      if (mainProblemMatch != null) {
        result['mainProblem'] = mainProblemMatch.group(1)?.trim() ?? extractedText;
      }

      // Extract given information
      final givenInfoMatch = RegExp(r'\*\*Given Information:\*\*\s*([\s\S]*?)(?=\*\*|$)', multiLine: true)
          .firstMatch(extractedText);
      if (givenInfoMatch != null) {
        final givenText = givenInfoMatch.group(1)?.trim() ?? '';
        result['givenInfo'] = givenText.split('\n')
            .where((line) => line.trim().startsWith('*'))
            .map((line) => line.replaceFirst('*', '').trim())
            .where((line) => line.isNotEmpty)
            .toList();
      }

      // Extract visuals description
      final visualsMatch = RegExp(r'\*\*Visuals Description:\*\*\s*([\s\S]*?)(?=\*\*|$)', multiLine: true)
          .firstMatch(extractedText);
      if (visualsMatch != null) {
        final visualsText = visualsMatch.group(1)?.trim() ?? 'None';
        if (visualsText.isNotEmpty && visualsText.toLowerCase() != 'none') {
          result['visualsDescription'] = visualsText;
        }
      }

      // Extract sub-questions
      final subQuestionsMatch = RegExp(r'\*\*Sub-questions:\*\*\s*([\s\S]*?)(?=\*\*\[END OUTPUT\]\*\*|$)', multiLine: true)
          .firstMatch(extractedText);
      if (subQuestionsMatch != null) {
        final subQuestionsText = subQuestionsMatch.group(1)?.trim() ?? '';
        final subQuestions = <Map<String, String>>[];
        
        final partMatches = RegExp(r'\*\s*\*\*Part ([^:]+):\*\*\s*([^\n]+)(?:\n\s*Answer Options:\s*([^\n]*?))?', multiLine: true)
            .allMatches(subQuestionsText);
        
        for (final match in partMatches) {
          subQuestions.add({
            'part': match.group(1)?.trim() ?? '',
            'question': match.group(2)?.trim() ?? '',
            'options': match.group(3)?.trim() ?? '',
          });
        }
        result['subQuestions'] = subQuestions;
      }
    } catch (e) {
      debugPrint('Error parsing extractor output: $e');
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final parsedOutput = _parseExtractorOutput(widget.problem.extractedText ?? widget.problem.originalInput);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          parsedOutput['title'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              final shareText = '''
Problem: ${widget.problem.extractedText ?? widget.problem.originalInput}

Solution: ${widget.problem.solution ?? 'Not solved yet'}

Explanation:
${widget.problem.stepByStepExplanation ?? 'No explanation available'}
''';
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Problem copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey.shade50, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Problem info header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.blue.shade50, Colors.indigo.shade50],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.problem.inputType == ProblemInputType.image
                            ? Icons.image_outlined
                            : Icons.text_fields_outlined,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.problem.inputType == ProblemInputType.image
                                ? 'Image Problem'
                                : 'Text Problem',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${DateFormat('MMM d, y • h:mm a').format(widget.problem.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.problem.isSolved
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.problem.isSolved ? 'Solved' : 'Processing',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: widget.problem.isSolved
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Problem content card with integrated image
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.quiz_outlined,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Problem Statement',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Show image prominently with problem statement for image problems
                      if (widget.problem.imageBytes != null) ...[
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade100.withOpacity(0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              widget.problem.imageBytes!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Add a visual separator
                        Container(
                          width: double.infinity,
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Colors.blue.shade200, Colors.transparent],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Problem content sections
                      _buildSectionCard(
                        context,
                        'Main Problem',
                        Icons.quiz_outlined,
                        Colors.green,
                        parsedOutput['mainProblem'] as String,
                      ),
                      
                      // Given Information (if available)
                      if ((parsedOutput['givenInfo'] as List<String>).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildListSectionCard(
                          context,
                          'Given Information',
                          Icons.info_outline,
                          Colors.orange,
                          parsedOutput['givenInfo'] as List<String>,
                        ),
                      ],
                      
                      // Visuals Description (if not 'None')
                      if (parsedOutput['visualsDescription'] != 'None') ...[
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          context,
                          'Visual Elements',
                          Icons.visibility_outlined,
                          Colors.purple,
                          parsedOutput['visualsDescription'] as String,
                        ),
                      ],
                      
                      // Sub-questions (if available)
                      if ((parsedOutput['subQuestions'] as List<Map<String, String>>).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSubQuestionsCard(
                          context,
                          parsedOutput['subQuestions'] as List<Map<String, String>>,
                        ),
                      ],
                      
                      // LaTeX format if available
                      if (widget.problem.latexFormat != null && 
                          widget.problem.latexFormat!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.code,
                                    color: Colors.blue.shade700,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'LaTeX Format',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.problem.latexFormat!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Solution card
              if (widget.problem.isSolved) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Solution',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () => _copyToClipboard(widget.problem.solution!),
                              tooltip: 'Copy answer',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Final answer
                        Text(
                          'Answer:',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text(
                            widget.problem.solution!,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Step-by-step explanation
                        if (widget.problem.stepByStepExplanation != null) ...[
                          Text(
                            'Step-by-Step Explanation:',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              widget.problem.stepByStepExplanation!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Chat section
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Ask Follow-up Questions',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Chat messages
                        if (_isLoadingChat) ...[
                          const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ] else if (_chatMessages.isNotEmpty) ...[
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _chatMessages.length,
                              itemBuilder: (context, index) {
                                final message = _chatMessages[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: message.isUser 
                                        ? Colors.blue.shade50 
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message.isUser ? 'You' : 'AI Assistant',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: message.isUser 
                                              ? Colors.blue.shade700 
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        message.message,
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Chat input
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: TextField(
                                  controller: _chatController,
                                  decoration: InputDecoration(
                                    hintText: 'Ask a follow-up question...',
                                    hintStyle: TextStyle(color: Colors.grey.shade600),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendChatMessage(),
                                  maxLines: null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue.shade600, Colors.blue.shade700],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                onPressed: _isSendingMessage ? null : _sendChatMessage,
                                icon: _isSendingMessage
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, color: Colors.white),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Problem not solved yet
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 48,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Problem is being processed...',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please wait while we solve your math problem.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              
              // Add some bottom padding for better scrolling
              const SizedBox(height: 24),
            ],
          ),
        ),
    );
  }

  // Helper method to build section cards
  Widget _buildSectionCard(BuildContext context, String title, IconData icon, 
      MaterialColor color, String content) {
    return Card(
      elevation: 3,
      shadowColor: color.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, color.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color.shade700, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.shade200),
                ),
                child: Text(
                  content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build list section cards
  Widget _buildListSectionCard(BuildContext context, String title, IconData icon, 
      MaterialColor color, List<String> items) {
    return Card(
      elevation: 3,
      shadowColor: color.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, color.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color.shade700, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: color.shade600,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.4,
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
        ),
      ),
    );
  }

  // Helper method to build sub-questions card
  Widget _buildSubQuestionsCard(BuildContext context, List<Map<String, String>> subQuestions) {
    return Card(
      elevation: 3,
      shadowColor: Colors.teal.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.teal.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.list_alt_outlined, color: Colors.teal.shade700, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Sub-questions',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...subQuestions.asMap().entries.map((entry) {
                final index = entry.key;
                final subQ = entry.value;
                return Container(
                  margin: EdgeInsets.only(bottom: index < subQuestions.length - 1 ? 12 : 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Part ${subQ['part']}:',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.teal.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subQ['question'] ?? '',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                      if (subQ['options']?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Options: ${subQ['options']}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.teal.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
