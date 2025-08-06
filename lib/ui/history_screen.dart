import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/math_problem.dart';
import '../services/math_solver_service.dart';
import '../services/database_service.dart';
import 'problem_detail_screen.dart' show ProblemDetailScreen, NaturalTheme;

/// Screen showing history of solved math problems
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MathSolverService _mathSolver = MathSolverService();

  List<MathProblem> _problems = [];
  List<MathProblem> _filteredProblems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  DatabaseStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadStats();
  }

  Future<void> _loadHistory() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final problems = await _mathSolver.getHistory();
      setState(() {
        _problems = problems;
        _filteredProblems = problems;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load history: $e'),
            backgroundColor: NaturalTheme.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await DatabaseService().getDatabaseStats();
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      debugPrint('Failed to load stats: $e');
    }
  }

  Future<void> _deleteProblem(MathProblem problem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Problem'),
        content: Text('Are you sure you want to delete "${problem.displayTitle}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _mathSolver.deleteProblem(problem.id);
        _loadHistory();
        _loadStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Problem deleted successfully'),
              backgroundColor: NaturalTheme.successGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete problem: $e'),
              backgroundColor: NaturalTheme.errorRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _generateTitle(MathProblem problem) async {
    try {
      final problemText = problem.extractedText ?? problem.originalInput;
      final newTitle = await _mathSolver.generateProblemTitle(problemText);
      
      // Update the problem in database with new title
      final updatedProblem = MathProblem(
        id: problem.id,
        originalInput: newTitle.isNotEmpty ? newTitle : problem.originalInput,
        extractedText: problem.extractedText,
        latexFormat: problem.latexFormat,
        solution: problem.solution,
        stepByStepExplanation: problem.stepByStepExplanation,
        createdAt: problem.createdAt,
        inputType: problem.inputType,
        status: problem.status,
        imageBase64: problem.imageBase64,
      );
      
      await DatabaseService().updateMathProblem(updatedProblem);
      _loadHistory();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated title: "$newTitle"'),
            backgroundColor: NaturalTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate title: $e'),
            backgroundColor: NaturalTheme.errorRed,
          ),
        );
      }
    }
  }

  void _filterProblems(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProblems = _problems;
      } else {
        _filteredProblems = _problems.where((problem) {
          final searchLower = query.toLowerCase();
          return (problem.extractedText?.toLowerCase().contains(searchLower) ?? false) ||
                 (problem.originalInput.toLowerCase().contains(searchLower)) ||
                 (problem.solution?.toLowerCase().contains(searchLower) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _searchProblems(String query) async {
    if (query.isEmpty) {
      _filterProblems('');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final searchResults = await _mathSolver.searchProblems(query);
      setState(() {
        _filteredProblems = searchResults;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatsCard() {
    if (_stats == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NaturalTheme.paperWhite,
            NaturalTheme.vintageWhite,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NaturalTheme.goldAccent.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: NaturalTheme.deepEarth.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: NaturalTheme.terracottaAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.analytics_rounded,
                    color: NaturalTheme.terracottaAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Your Mathematical Journey',
                  style: GoogleFonts.lora(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: NaturalTheme.primaryText,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total Problems',
                    _stats!.totalProblems.toString(),
                    Icons.auto_stories_rounded,
                    NaturalTheme.mutedClay,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Solved',
                    _stats!.solvedProblems.toString(),
                    Icons.check_circle_rounded,
                    NaturalTheme.successGreen,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Success Rate',
                    '${_stats!.solvedPercentage.toStringAsFixed(1)}%',
                    Icons.trending_up_rounded,
                    NaturalTheme.terracottaAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.lora(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.lato(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: NaturalTheme.secondaryText,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProblemCard(MathProblem problem) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NaturalTheme.paperWhite,
            NaturalTheme.creamPaper,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NaturalTheme.paperBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: NaturalTheme.shadowColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProblemDetailScreen(problem: problem),
              ),
            ).then((_) {
              // Refresh the list when returning from detail screen
              _loadHistory();
              _loadStats();
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status indicator
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: problem.isSolved 
                          ? [NaturalTheme.successLight, NaturalTheme.successDark]
                          : problem.status == ProblemStatus.error
                              ? [NaturalTheme.errorLight, NaturalTheme.errorDark]
                              : [NaturalTheme.warningLight, NaturalTheme.warningDark],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: problem.isSolved 
                          ? NaturalTheme.successDark.withOpacity(0.3)
                          : problem.status == ProblemStatus.error
                              ? NaturalTheme.errorDark.withOpacity(0.3)
                              : NaturalTheme.warningDark.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    problem.inputType == ProblemInputType.image
                        ? Icons.image_outlined
                        : Icons.text_fields_outlined,
                    color: problem.isSolved 
                        ? NaturalTheme.successDark
                        : problem.status == ProblemStatus.error
                            ? NaturalTheme.errorDark
                            : NaturalTheme.warningDark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        problem.displayTitle,
                        style: GoogleFonts.lora(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: NaturalTheme.primaryText,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Answer preview
                      if (problem.solution != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: NaturalTheme.successLight.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: NaturalTheme.successDark.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'Answer: ${problem.solution}',
                            style: GoogleFonts.lato(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: NaturalTheme.successDark,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Footer row
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 14,
                            color: NaturalTheme.secondaryText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d, y • h:mm a').format(problem.createdAt),
                            style: GoogleFonts.lato(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: NaturalTheme.secondaryText,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: problem.isSolved 
                                    ? [NaturalTheme.successLight, NaturalTheme.successDark]
                                    : problem.status == ProblemStatus.error
                                        ? [NaturalTheme.errorLight, NaturalTheme.errorDark]
                                        : [NaturalTheme.warningLight, NaturalTheme.warningDark],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              problem.status.displayName,
                              style: GoogleFonts.lato(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Menu button
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: NaturalTheme.secondaryText,
                    size: 20,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'generate_title':
                        _generateTitle(problem);
                        break;
                      case 'delete':
                        _deleteProblem(problem);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'generate_title',
                      child: Row(
                        children: [
                          Icon(
                            Icons.title_outlined,
                            size: 18,
                            color: NaturalTheme.primaryText,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Generate Title',
                            style: GoogleFonts.lato(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: NaturalTheme.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: NaturalTheme.errorDark,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: GoogleFonts.lato(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: NaturalTheme.errorDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NaturalTheme.artisanPaperLight,
      appBar: AppBar(
        title: Text(
          'Problem History',
          style: GoogleFonts.lora(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: NaturalTheme.primaryText,
            letterSpacing: 0.3,
          ),
        ),
        backgroundColor: NaturalTheme.creamPaper,
        foregroundColor: NaturalTheme.primaryText,
        elevation: 0,
        shadowColor: NaturalTheme.mutedText.withOpacity(0.1),
        surfaceTintColor: Colors.transparent,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: NaturalTheme.terracottaAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                color: NaturalTheme.terracottaAccent,
                size: 22,
              ),
              onPressed: () {
                _loadHistory();
                _loadStats();
              },
              tooltip: 'Refresh history',
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NaturalTheme.artisanPaperLight,
              NaturalTheme.artisanPaperDark,
            ],
          ),
        ),
        child: Column(
          children: [
            // Search bar with natural design
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: NaturalTheme.creamPaper.withOpacity(0.8),
                border: Border(
                  bottom: BorderSide(
                    color: NaturalTheme.goldAccent.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      NaturalTheme.paperWhite,
                      NaturalTheme.vintageWhite,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: NaturalTheme.mutedClay.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: NaturalTheme.deepEarth.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.lato(
                    color: NaturalTheme.primaryText,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search through your mathematical journey...',
                    hintStyle: GoogleFonts.lato(
                      color: NaturalTheme.secondaryText,
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                    ),
                    prefixIcon: Container(
                      margin: const EdgeInsets.only(left: 16, right: 12),
                      child: Icon(
                        Icons.search_rounded,
                        color: NaturalTheme.mutedClay.withOpacity(0.7),
                        size: 22,
                      ),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: NaturalTheme.mutedText,
                                size: 20,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _filterProblems('');
                              },
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  onChanged: _filterProblems,
                  onSubmitted: _searchProblems,
                ),
              ),
            ),

            // Statistics card
            _buildStatsCard(),

            // Problems list with natural styling
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          NaturalTheme.terracottaAccent,
                        ),
                        strokeWidth: 3,
                      ),
                    )
                  : _filteredProblems.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: NaturalTheme.beigeCard.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: NaturalTheme.goldAccent.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    _searchQuery.isNotEmpty 
                                        ? Icons.search_off_rounded 
                                        : Icons.auto_stories_rounded,
                                    size: 64,
                                    color: NaturalTheme.mutedClay.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  _searchQuery.isNotEmpty 
                                      ? 'No problems found for "$_searchQuery"'
                                      : 'Your Mathematical Journey Awaits',
                                  style: GoogleFonts.lora(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: NaturalTheme.primaryText,
                                    letterSpacing: 0.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isNotEmpty 
                                      ? 'Try adjusting your search terms or explore different mathematical concepts'
                                      : 'Start solving mathematical problems to build your personal collection of solutions and insights',
                                  style: GoogleFonts.lato(
                                    fontSize: 15,
                                    color: NaturalTheme.secondaryText,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          color: NaturalTheme.terracottaAccent,
                          backgroundColor: NaturalTheme.creamPaper,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: _filteredProblems.length,
                            itemBuilder: (context, index) {
                              return _buildProblemCard(_filteredProblems[index]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
