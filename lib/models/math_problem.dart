import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Represents a math problem with its solution and metadata
class MathProblem {
  final String id;
  final String originalInput;
  final String? extractedText;
  final String? latexFormat;
  final String? solution;
  final String? stepByStepExplanation;
  final String? title; // Generated/cleaned problem title
  final DateTime createdAt;
  final ProblemInputType inputType;
  final ProblemStatus status;
  final String? imageBase64; // Store image as base64 for persistence

  MathProblem({
    String? id,
    required this.originalInput,
    required this.inputType,
    this.extractedText,
    this.latexFormat,
    this.solution,
    this.stepByStepExplanation,
    this.title,
    DateTime? createdAt,
    this.status = ProblemStatus.pending,
    this.imageBase64,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  /// Create a copy with updated fields
  MathProblem copyWith({
    String? extractedText,
    String? latexFormat,
    String? solution,
    String? stepByStepExplanation,
    String? title,
    ProblemStatus? status,
  }) {
    return MathProblem(
      id: id,
      originalInput: originalInput,
      extractedText: extractedText ?? this.extractedText,
      latexFormat: latexFormat ?? this.latexFormat,
      solution: solution ?? this.solution,
      stepByStepExplanation: stepByStepExplanation ?? this.stepByStepExplanation,
      title: title ?? this.title,
      createdAt: createdAt,
      inputType: inputType,
      status: status ?? this.status,
      imageBase64: imageBase64,
    );
  }

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalInput': originalInput,
      'extractedText': extractedText,
      'latexFormat': latexFormat,
      'solution': solution,
      'stepByStepExplanation': stepByStepExplanation,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'inputType': inputType.name,
      'status': status.name,
      'imageBase64': imageBase64,
    };
  }

  /// Create from JSON for database retrieval
  factory MathProblem.fromJson(Map<String, dynamic> json) {
    return MathProblem(
      id: json['id'],
      originalInput: json['originalInput'],
      extractedText: json['extractedText'],
      latexFormat: json['latexFormat'],
      solution: json['solution'],
      stepByStepExplanation: json['stepByStepExplanation'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      inputType: ProblemInputType.values.firstWhere(
        (e) => e.name == json['inputType'],
      ),
      status: ProblemStatus.values.firstWhere(
        (e) => e.name == json['status'],
      ),
      imageBase64: json['imageBase64'],
    );
  }

  /// Check if the problem is fully solved
  bool get isSolved => status == ProblemStatus.solved && solution != null;

  /// Get a display title for the problem
  String get displayTitle {
    // Use cleaned title if available
    if (title != null && title!.isNotEmpty) {
      return title!.length > 50 
          ? '${title!.substring(0, 50)}...'
          : title!;
    }
    
    // Fallback to extracted text
    if (extractedText != null && extractedText!.isNotEmpty) {
      return extractedText!.length > 50 
          ? '${extractedText!.substring(0, 50)}...'
          : extractedText!;
    }
    
    // Final fallback to original input
    return originalInput.length > 50 
        ? '${originalInput.substring(0, 50)}...'
        : originalInput;
  }
}

/// Type of input for the math problem
enum ProblemInputType {
  text,
  image,
}

/// Status of a math problem
enum ProblemStatus {
  pending,
  solving,
  solved,
  error;
  
  String get displayName {
    switch (this) {
      case ProblemStatus.pending:
        return 'Pending';
      case ProblemStatus.solving:
        return 'Solving';
      case ProblemStatus.solved:
        return 'Solved';
      case ProblemStatus.error:
        return 'Error';
    }
  }
}
