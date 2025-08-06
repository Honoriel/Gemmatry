import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// A widget that renders markdown with LaTeX math support
class MathMarkdownWidget extends StatelessWidget {
  final String data;
  final MarkdownStyleSheet? styleSheet;

  const MathMarkdownWidget({
    Key? key,
    required this.data,
    this.styleSheet,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _parseAndRenderMath(context, data),
      ),
    );
  }

  /// Parse text and render both markdown and LaTeX math
  List<Widget> _parseAndRenderMath(BuildContext context, String text) {
    final widgets = <Widget>[];
    
    // Split by display math ($$...$$) first, as these should be on separate lines
    final displayMathPattern = RegExp(r'\$\$([^$]*(?:\$(?!\$)[^$]*)*)\$\$');
    final displayMatches = displayMathPattern.allMatches(text);
    
    if (displayMatches.isEmpty) {
      // No display math, handle inline math within text
      widgets.add(_buildTextWithInlineMath(context, text));
    } else {
      // Process display math sections
      int lastEnd = 0;
      
      for (final match in displayMatches) {
        // Add text before display math (may contain inline math)
        if (match.start > lastEnd) {
          final beforeText = text.substring(lastEnd, match.start);
          if (beforeText.trim().isNotEmpty) {
            widgets.add(_buildTextWithInlineMath(context, beforeText));
          }
        }
        
        // Add display math as separate widget
        final mathExpression = match.group(1) ?? '';
        if (mathExpression.isNotEmpty) {
          widgets.add(_buildMathWidget(mathExpression, true)); // true = display math
        }
        
        lastEnd = match.end;
      }
      
      // Add remaining text (may contain inline math)
      if (lastEnd < text.length) {
        final remainingText = text.substring(lastEnd);
        if (remainingText.trim().isNotEmpty) {
          widgets.add(_buildTextWithInlineMath(context, remainingText));
        }
      }
    }
    
    // If no content was processed, render as pure markdown
    if (widgets.isEmpty) {
      widgets.add(_buildMarkdownWidget(text));
    }
    
    return widgets;
  }
  
  /// Build text with inline math and markdown formatting using RichText for proper flow
  Widget _buildTextWithInlineMath(BuildContext context, String text) {
    final inlineMathPattern = RegExp(r'\$([^$\n]+)\$');
    final mathMatches = inlineMathPattern.allMatches(text);
    
    if (mathMatches.isEmpty) {
      // No inline math, use regular markdown
      return _buildMarkdownWidget(text);
    }
    
    // Build a single RichText with both math and formatted text
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    
    for (final mathMatch in mathMatches) {
      // Add text before math (with markdown formatting)
      if (mathMatch.start > lastEnd) {
        final beforeText = text.substring(lastEnd, mathMatch.start);
        if (beforeText.isNotEmpty) {
          spans.addAll(_parseMarkdownToSpans(beforeText));
        }
      }
      
      // Add inline math as WidgetSpan
      final mathExpression = mathMatch.group(1) ?? '';
      if (mathExpression.isNotEmpty) {
        spans.add(_buildInlineMathSpan(mathExpression));
      }
      
      lastEnd = mathMatch.end;
    }
    
    // Add remaining text (with markdown formatting)
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        spans.addAll(_parseMarkdownToSpans(remainingText));
      }
    }
    
    return Container(
      width: double.infinity,
      child: RichText(
        text: TextSpan(
          children: spans,
          style: styleSheet?.p ?? DefaultTextStyle.of(context).style,
        ),
        softWrap: true,
      ),
    );
  }
  
  /// Parse markdown formatting and return list of TextSpans
  List<InlineSpan> _parseMarkdownToSpans(String text) {
    final spans = <InlineSpan>[];
    
    // Combined pattern for bold, italic, and code
    final formatPattern = RegExp(r'(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(\`([^`]+)\`)');
    final matches = formatPattern.allMatches(text);
    
    if (matches.isEmpty) {
      // No formatting, return plain text span
      spans.add(TextSpan(
        text: text,
        style: styleSheet?.p ?? const TextStyle(),
      ));
      return spans;
    }
    
    int lastEnd = 0;
    
    for (final match in matches) {
      // Add text before formatting
      if (match.start > lastEnd) {
        final beforeText = text.substring(lastEnd, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(
            text: beforeText,
            style: styleSheet?.p ?? const TextStyle(),
          ));
        }
      }
      
      // Determine formatting type and add styled text
      if (match.group(1) != null) {
        // Bold: **text**
        final boldText = match.group(2) ?? '';
        spans.add(TextSpan(
          text: boldText,
          style: (styleSheet?.p ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (match.group(3) != null) {
        // Italic: *text*
        final italicText = match.group(4) ?? '';
        spans.add(TextSpan(
          text: italicText,
          style: (styleSheet?.p ?? const TextStyle()).copyWith(
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (match.group(5) != null) {
        // Code: `text`
        final codeText = match.group(6) ?? '';
        spans.add(TextSpan(
          text: codeText,
          style: styleSheet?.code ?? const TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Colors.grey,
          ),
        ));
      }
      
      lastEnd = match.end;
    }
    
    // Add remaining text
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(
          text: remainingText,
          style: styleSheet?.p ?? const TextStyle(),
        ));
      }
    }
    
    return spans;
  }
  
  /// Build an inline math WidgetSpan with proper alignment
  WidgetSpan _buildInlineMathSpan(String expression) {
    try {
      return WidgetSpan(
        child: Math.tex(
          expression,
          mathStyle: MathStyle.text,
          textStyle: const TextStyle(
            fontSize: 15.0,
          ),
        ),
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
      );
    } catch (e) {
      // Fallback to styled text span if math parsing fails
      return WidgetSpan(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(3.0),
          ),
          child: Text(
            '\$\${expression}\$',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13.0,
            ),
          ),
        ),
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
      );
    }
  }

  /// Build a markdown widget for regular text
  Widget _buildMarkdownWidget(String text) {
    return Container(
      width: double.infinity,
      child: MarkdownBody(
        data: text,
        styleSheet: styleSheet,
        shrinkWrap: true,
        softLineBreak: true,
        selectable: true,
      ),
    );
  }

  /// Build a math widget for LaTeX expressions
  Widget _buildMathWidget(String expression, bool isDisplayMode) {
    try {
      if (isDisplayMode) {
        // Display math: centered on its own line with larger size
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: double.infinity),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  expression,
                  mathStyle: MathStyle.display,
                  textStyle: const TextStyle(
                    fontSize: 18.0, // Slightly smaller to prevent overflow
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        // Inline math: flows with text, smaller size
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: Math.tex(
              expression,
              mathStyle: MathStyle.text,
              textStyle: const TextStyle(
                fontSize: 15.0, // Slightly smaller to prevent overflow
              ),
            ),
          ),
        );
      }
    } catch (e) {
      // Fallback to showing the raw expression if LaTeX parsing fails
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(isDisplayMode ? 8.0 : 4.0),
        margin: EdgeInsets.symmetric(
          vertical: isDisplayMode ? 8.0 : 2.0,
          horizontal: isDisplayMode ? 0.0 : 2.0,
        ),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            isDisplayMode ? '\$\$$expression\$\$' : '\$$expression\$',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: isDisplayMode ? 15.0 : 13.0,
            ),
            textAlign: isDisplayMode ? TextAlign.center : TextAlign.left,
            overflow: TextOverflow.visible,
          ),
        ),
      );
    }
  }
}
