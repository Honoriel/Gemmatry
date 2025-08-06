import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

/// Service for extracting text from images using OCR
class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  late final TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  /// Initialize the OCR service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _textRecognizer = TextRecognizer();
      _isInitialized = true;
    } catch (e) {
      throw OCRException('Failed to initialize OCR service: $e');
    }
  }

  /// Extract text from image bytes with enhanced preprocessing
  Future<OCRResult> extractTextFromImage(Uint8List imageBytes) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('=== OCR PREPROCESSING DEBUG ===');
      print('Original image size: ${imageBytes.length} bytes');
      
      // Preprocess image for better OCR accuracy
      final preprocessedBytes = await _preprocessImageForOCR(imageBytes);
      print('Preprocessed image size: ${preprocessedBytes.length} bytes');
      
      // Save preprocessed image to temporary file for ML Kit processing
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, 'temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg'));
      await tempFile.writeAsBytes(preprocessedBytes);
      
      // Create InputImage from file
      final inputImage = InputImage.fromFile(tempFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      print('OCR recognized ${recognizedText.blocks.length} text blocks');
      print('Total text length: ${recognizedText.text.length} characters');
      print('===============================');
      
      // Clean up temporary file
      try {
        await tempFile.delete();
      } catch (e) {
        // Ignore cleanup errors
      }
      
      return OCRResult(
        fullText: recognizedText.text,
        confidence: _calculateConfidence(recognizedText),
        blocks: recognizedText.blocks.map((block) => OCRTextBlock(
          text: block.text,
          boundingBox: block.boundingBox,
          confidence: 0.8, // Default confidence since ML Kit doesn't provide it
        )).toList(),
      );
    } catch (e) {
      throw OCRException('Failed to extract text from image: $e');
    }
  }

  /// Extract mathematical expressions specifically
  Future<MathExtractionResult> extractMathFromImage(Uint8List imageBytes) async {
    final ocrResult = await extractTextFromImage(imageBytes);
    
    // Enhanced processing to identify the main question vs answer choices
    final questionAnalysis = _analyzeQuestionStructure(ocrResult);
    final mathExpressions = _identifyMathExpressions(ocrResult);
    
    return MathExtractionResult(
      originalText: ocrResult.fullText,
      mathExpressions: mathExpressions,
      confidence: ocrResult.confidence,
      suggestedLatex: _convertToLatex(mathExpressions),
      extractedQuestion: questionAnalysis.mainQuestion,
      answerChoices: questionAnalysis.answerChoices,
    );
  }

  /// Analyze the structure of the OCR text to identify main question vs answer choices
  QuestionAnalysis _analyzeQuestionStructure(OCRResult ocrResult) {
    final fullText = ocrResult.fullText;
    final blocks = ocrResult.blocks;
    
    // Common patterns for answer choices
    final answerChoicePatterns = [
      RegExp(r'^[A-E]\)\s*(.+)', multiLine: true), // A) B) C) D) E)
      RegExp(r'^[A-E]\.\s*(.+)', multiLine: true), // A. B. C. D. E.
      RegExp(r'^\([A-E]\)\s*(.+)', multiLine: true), // (A) (B) (C) (D) (E)
      RegExp(r'^[1-5]\)\s*(.+)', multiLine: true), // 1) 2) 3) 4) 5)
      RegExp(r'^[1-5]\.\s*(.+)', multiLine: true), // 1. 2. 3. 4. 5.
    ];
    
    List<String> answerChoices = [];
    String mainQuestion = fullText;
    
    // Extract answer choices
    for (final pattern in answerChoicePatterns) {
      final matches = pattern.allMatches(fullText);
      if (matches.length >= 2) { // At least 2 choices to be considered multiple choice
        answerChoices = matches.map((match) => match.group(1)?.trim() ?? '').where((s) => s.isNotEmpty).toList();
        
        // Remove answer choices from main question
        String questionWithoutChoices = fullText;
        for (final match in matches) {
          questionWithoutChoices = questionWithoutChoices.replaceAll(match.group(0) ?? '', '');
        }
        mainQuestion = questionWithoutChoices.trim();
        break;
      }
    }
    
    // If no clear answer choices found, try to identify question by common question indicators
    if (answerChoices.isEmpty) {
      mainQuestion = _extractMainQuestion(fullText);
    }
    
    // Clean up the main question
    mainQuestion = _cleanupQuestion(mainQuestion);
    
    return QuestionAnalysis(
      mainQuestion: mainQuestion,
      answerChoices: answerChoices,
      hasMultipleChoice: answerChoices.isNotEmpty,
    );
  }
  
  /// Extract the main question from text using common question indicators
  String _extractMainQuestion(String text) {
    // Common question indicators
    final questionIndicators = [
      'What is',
      'Find',
      'Calculate',
      'Solve',
      'Determine',
      'Evaluate',
      'Simplify',
      'If',
      'Given',
      'A triangle',
      'A circle',
      'The equation',
      'The function',
    ];
    
    // Look for sentences that contain question indicators
    final sentences = text.split(RegExp(r'[.!?]\s*'));
    for (final sentence in sentences) {
      for (final indicator in questionIndicators) {
        if (sentence.toLowerCase().contains(indicator.toLowerCase())) {
          return sentence.trim();
        }
      }
    }
    
    // If no specific indicators found, return the first substantial sentence
    for (final sentence in sentences) {
      if (sentence.trim().length > 10) {
        return sentence.trim();
      }
    }
    
    return text.trim();
  }
  
  /// Clean up the extracted question text
  String _cleanupQuestion(String question) {
    // Remove common prefixes and suffixes
    question = question.replaceAll(RegExp(r'^(Question|Problem)\s*\d*[:.\s]*', caseSensitive: false), '');
    question = question.replaceAll(RegExp(r'\s*(Choose|Select)\s+the\s+correct\s+answer.*', caseSensitive: false), '');
    question = question.replaceAll(RegExp(r'\s*Which\s+of\s+the\s+following.*', caseSensitive: false), '');
    
    // Remove extra whitespace
    question = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return question;
  }

  /// Identify mathematical expressions from OCR text with enhanced patterns
  List<String> _identifyMathExpressions(OCRResult ocrResult) {
    final mathExpressions = <String>[];
    
    // Enhanced math patterns for better recognition
    final mathPatterns = [
      // Basic arithmetic with various spacing
      RegExp(r'[0-9]+\s*[\+\-\*×÷\/\=]\s*[0-9]+'),
      // Algebraic expressions
      RegExp(r'[a-zA-Z]\s*[\+\-\*×÷\/\=]\s*[0-9]+'),
      RegExp(r'[0-9]*[a-zA-Z]\^?[0-9]*'),
      // Polynomials and powers
      RegExp(r'[a-zA-Z]\^[0-9]+'),
      RegExp(r'[0-9]+[a-zA-Z]\^?[0-9]*'),
      // Roots and radicals
      RegExp(r'√\s*[0-9a-zA-Z]+'),
      RegExp(r'\\sqrt\{[^}]+\}'),
      // Trigonometric and logarithmic functions
      RegExp(r'(sin|cos|tan|cot|sec|csc|log|ln|exp)\s*\([^)]+\)'),
      RegExp(r'(sin|cos|tan|cot|sec|csc|log|ln|exp)\s*[0-9a-zA-Z]+'),
      // Fractions (various formats)
      RegExp(r'[0-9]+\/[0-9]+'),
      RegExp(r'\\frac\{[^}]+\}\{[^}]+\}'),
      // Parentheses and brackets
      RegExp(r'\([^)]+\)'),
      RegExp(r'\[[^\]]+\]'),
      RegExp(r'\{[^}]+\}'),
      // Inequalities
      RegExp(r'[0-9a-zA-Z]+\s*[<>≤≥≠]\s*[0-9a-zA-Z]+'),
      // Geometric expressions
      RegExp(r'(angle|triangle|circle|square|rectangle|area|perimeter|volume)\s*[A-Z]+'),
      // Mathematical symbols and operators
      RegExp(r'[∑∏∫∂∇±∞π∆θφλμσ]'),
      // Equations and formulas
      RegExp(r'[a-zA-Z0-9]+\s*=\s*[^\n]+'),
      // Coordinate expressions
      RegExp(r'\([0-9\-\.]+,\s*[0-9\-\.]+\)'),
      // Percentages
      RegExp(r'[0-9]+\.?[0-9]*%'),
      // Decimals and scientific notation
      RegExp(r'[0-9]+\.[0-9]+'),
      RegExp(r'[0-9]+\.?[0-9]*[eE][\+\-]?[0-9]+'),
    ];

    print('=== MATH EXPRESSION IDENTIFICATION ===');
    
    for (final block in ocrResult.blocks) {
      print('Processing block: "${block.text}"');
      
      for (final pattern in mathPatterns) {
        final matches = pattern.allMatches(block.text);
        for (final match in matches) {
          final expression = match.group(0);
          if (expression != null && expression.isNotEmpty && !mathExpressions.contains(expression)) {
            mathExpressions.add(expression);
            print('Found math expression: "$expression"');
          }
        }
      }
    }

    // If no specific math patterns found, return the full text
    if (mathExpressions.isEmpty && ocrResult.fullText.isNotEmpty) {
      mathExpressions.add(ocrResult.fullText);
      print('No specific patterns found, using full text');
    }
    
    print('Total math expressions found: ${mathExpressions.length}');
    print('=====================================');

    return mathExpressions;
  }

  /// Convert mathematical expressions to LaTeX format
  String _convertToLatex(List<String> mathExpressions) {
    if (mathExpressions.isEmpty) return '';
    
    String latex = mathExpressions.join(' ');
    
    // Basic LaTeX conversions
    latex = latex.replaceAll('√', '\\sqrt{');
    latex = latex.replaceAll(RegExp(r'(\d+)\/(\d+)'), r'\frac{$1}{$2}');
    latex = latex.replaceAll(RegExp(r'x\^(\d+)'), r'x^{$1}');
    latex = latex.replaceAll('*', ' \\cdot ');
    
    // Close any opened sqrt brackets
    final sqrtCount = '\\sqrt{'.allMatches(latex).length;
    latex += '}' * sqrtCount;
    
    return latex;
  }

  /// Calculate overall confidence from recognized text with math-specific heuristics
  double _calculateConfidence(RecognizedText recognizedText) {
    if (recognizedText.blocks.isEmpty) return 0.0;
    
    final fullText = recognizedText.text;
    final textLength = fullText.length;
    final blockCount = recognizedText.blocks.length;
    
    if (textLength == 0) return 0.0;
    
    double confidence = 0.5; // Base confidence
    
    // Length-based confidence
    if (textLength >= 50) confidence += 0.2;
    else if (textLength >= 20) confidence += 0.1;
    else if (textLength < 5) confidence -= 0.3;
    
    // Block structure confidence
    if (blockCount >= 3) confidence += 0.1;
    if (blockCount >= 5) confidence += 0.1;
    
    // Mathematical content indicators (boost confidence)
    final mathIndicators = [
      RegExp(r'[0-9]+'), // Numbers
      RegExp(r'[\+\-\*\/\=]'), // Basic operators
      RegExp(r'[a-zA-Z]'), // Variables
      RegExp(r'\([^)]+\)'), // Parentheses
      RegExp(r'[<>=]'), // Comparison operators
      RegExp(r'(sin|cos|tan|log|sqrt)'), // Math functions
    ];
    
    int mathMatches = 0;
    for (final pattern in mathIndicators) {
      if (pattern.hasMatch(fullText)) mathMatches++;
    }
    
    confidence += (mathMatches * 0.05); // Boost for math content
    
    // Quality indicators (reduce confidence for poor OCR)
    final qualityDetractors = [
      RegExp(r'[^a-zA-Z0-9\s\+\-\*\/\=\(\)\[\]\{\}<>≤≥≠√π∑∏∫∂∇±∞∆θφλμσ.,;:!?%]'), // Unusual characters
      RegExp(r'\s{3,}'), // Excessive whitespace
      RegExp(r'[a-zA-Z]{15,}'), // Very long words (likely OCR errors)
    ];
    
    for (final pattern in qualityDetractors) {
      final matches = pattern.allMatches(fullText).length;
      confidence -= (matches * 0.1);
    }
    
    // Ensure confidence stays within bounds
    confidence = confidence.clamp(0.0, 1.0);
    
    print('OCR Confidence Analysis:');
    print('- Text length: $textLength');
    print('- Block count: $blockCount');
    print('- Math indicators: $mathMatches');
    print('- Final confidence: ${confidence.toStringAsFixed(2)}');
    
    return confidence;
  }

  /// Preprocess image for better OCR accuracy on mathematical content
  Future<Uint8List> _preprocessImageForOCR(Uint8List imageBytes) async {
    try {
      // Decode the image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        print('Failed to decode image, using original');
        return imageBytes;
      }
      
      print('Original image dimensions: ${image.width}x${image.height}');
      
      // 1. Convert to grayscale for better text recognition
      image = img.grayscale(image);
      
      // 2. Scale up image if it's too small (OCR works better on larger images)
      if (image.width < 800 || image.height < 600) {
        final scaleFactor = (800 / image.width).clamp(1.0, 3.0);
        image = img.copyResize(image, 
          width: (image.width * scaleFactor).round(),
          height: (image.height * scaleFactor).round(),
          interpolation: img.Interpolation.cubic
        );
        print('Scaled image to: ${image.width}x${image.height} (factor: ${scaleFactor.toStringAsFixed(2)})');
      }
      
      // 3. Apply simple contrast enhancement
      image = img.adjustColor(image, contrast: 1.2);
      
      // 4. Apply brightness adjustment
      image = img.adjustColor(image, brightness: 1.1);
      
      // 5. Apply noise reduction
      image = img.gaussianBlur(image, radius: 1);
      
      // Encode back to bytes
      final processedBytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      print('Image preprocessing completed successfully');
      
      return processedBytes;
      
    } catch (e) {
      print('Error in image preprocessing: $e');
      print('Falling back to original image');
      return imageBytes;
    }
  }
  
  /// Dispose of resources
  Future<void> dispose() async {
    if (_isInitialized) {
      await _textRecognizer.close();
      _isInitialized = false;
    }
  }
}

/// Result of OCR text extraction
class OCRResult {
  final String fullText;
  final double confidence;
  final List<OCRTextBlock> blocks;

  OCRResult({
    required this.fullText,
    required this.confidence,
    required this.blocks,
  });
}

/// Analysis of question structure from OCR text
class QuestionAnalysis {
  final String mainQuestion;
  final List<String> answerChoices;
  final bool hasMultipleChoice;

  QuestionAnalysis({
    required this.mainQuestion,
    required this.answerChoices,
    required this.hasMultipleChoice,
  });
}

/// Result of mathematical expression extraction
class MathExtractionResult {
  final String originalText;
  final List<String> mathExpressions;
  final double confidence;
  final String suggestedLatex;
  final String extractedQuestion;
  final List<String> answerChoices;

  MathExtractionResult({
    required this.originalText,
    required this.mathExpressions,
    required this.confidence,
    required this.suggestedLatex,
    required this.extractedQuestion,
    required this.answerChoices,
  });
}

/// Represents a block of recognized text
class OCRTextBlock {
  final String text;
  final Rect boundingBox;
  final double confidence;

  OCRTextBlock({
    required this.text,
    required this.boundingBox,
    required this.confidence,
  });
}

/// Custom exception for OCR operations
class OCRException implements Exception {
  final String message;
  OCRException(this.message);
  
  @override
  String toString() => 'OCRException: $message';
}
