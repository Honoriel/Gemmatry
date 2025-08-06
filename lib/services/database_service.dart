import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/math_problem.dart';
import '../models/chat_message.dart';

/// Service for managing local database operations
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static const String _databaseName = 'math_solver.db';
  static const int _databaseVersion = 2;

  /// Get database instance
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  /// Create database tables
  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE math_problems (
        id TEXT PRIMARY KEY,
        originalInput TEXT NOT NULL,
        extractedText TEXT,
        latexFormat TEXT,
        solution TEXT,
        stepByStepExplanation TEXT,
        title TEXT,
        createdAt TEXT NOT NULL,
        inputType TEXT NOT NULL,
        status TEXT NOT NULL,
        imageBase64 TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        problemId TEXT NOT NULL,
        message TEXT NOT NULL,
        isUser INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (problemId) REFERENCES math_problems (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_problems_created_at ON math_problems(createdAt DESC)');
    await db.execute('CREATE INDEX idx_chat_problem_id ON chat_messages(problemId)');
  }

  /// Upgrade database schema
  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades
    if (oldVersion < 2 && newVersion >= 2) {
      // Add title column to existing math_problems table
      await db.execute('ALTER TABLE math_problems ADD COLUMN title TEXT');
      print('Added title column to math_problems table');
    }
  }

  /// Save a math problem to the database
  Future<void> saveMathProblem(MathProblem problem) async {
    final db = await database;
    await db.insert(
      'math_problems',
      problem.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update an existing math problem
  Future<void> updateMathProblem(MathProblem problem) async {
    final db = await database;
    await db.update(
      'math_problems',
      problem.toJson(),
      where: 'id = ?',
      whereArgs: [problem.id],
    );
  }

  /// Get a math problem by ID
  Future<MathProblem?> getMathProblem(String id) async {
    final db = await database;
    final results = await db.query(
      'math_problems',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isNotEmpty) {
      return MathProblem.fromJson(results.first);
    }
    return null;
  }

  /// Get all math problems ordered by creation date
  Future<List<MathProblem>> getAllMathProblems() async {
    final db = await database;
    final results = await db.query(
      'math_problems',
      orderBy: 'createdAt DESC',
    );

    return results.map((json) => MathProblem.fromJson(json)).toList();
  }

  /// Get recent math problems (last 50)
  Future<List<MathProblem>> getRecentMathProblems({int limit = 50}) async {
    final db = await database;
    final results = await db.query(
      'math_problems',
      orderBy: 'createdAt DESC',
      limit: limit,
    );

    return results.map((json) => MathProblem.fromJson(json)).toList();
  }

  /// Search math problems by text content
  Future<List<MathProblem>> searchMathProblems(String query) async {
    final db = await database;
    final results = await db.query(
      'math_problems',
      where: '''
        originalInput LIKE ? OR 
        extractedText LIKE ? OR 
        solution LIKE ?
      ''',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'createdAt DESC',
    );

    return results.map((json) => MathProblem.fromJson(json)).toList();
  }

  /// Delete a math problem
  Future<void> deleteMathProblem(String id) async {
    final db = await database;
    await db.delete(
      'math_problems',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Save a chat message
  Future<void> saveChatMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      'chat_messages',
      message.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get chat messages for a specific problem
  Future<List<ChatMessage>> getChatMessages(String problemId) async {
    final db = await database;
    final results = await db.query(
      'chat_messages',
      where: 'problemId = ?',
      whereArgs: [problemId],
      orderBy: 'createdAt ASC',
    );

    return results.map((json) => ChatMessage.fromJson(json)).toList();
  }

  /// Delete all chat messages for a problem
  Future<void> deleteChatMessages(String problemId) async {
    final db = await database;
    await db.delete(
      'chat_messages',
      where: 'problemId = ?',
      whereArgs: [problemId],
    );
  }

  /// Get database statistics
  Future<DatabaseStats> getDatabaseStats() async {
    final db = await database;
    
    final problemCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM math_problems')
    ) ?? 0;
    
    final solvedCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM math_problems WHERE status = ?', ['solved'])
    ) ?? 0;
    
    final chatCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM chat_messages')
    ) ?? 0;

    return DatabaseStats(
      totalProblems: problemCount,
      solvedProblems: solvedCount,
      totalChatMessages: chatCount,
    );
  }

  /// Clear all data (for testing or reset)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('chat_messages');
    await db.delete('math_problems');
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

/// Database statistics
class DatabaseStats {
  final int totalProblems;
  final int solvedProblems;
  final int totalChatMessages;

  DatabaseStats({
    required this.totalProblems,
    required this.solvedProblems,
    required this.totalChatMessages,
  });

  double get solvedPercentage {
    if (totalProblems == 0) return 0.0;
    return (solvedProblems / totalProblems) * 100;
  }
}
