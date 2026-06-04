#!/usr/bin/env dart
// 数据库打包工具
// 将翻译和共现 CSV 数据打包为预构建的 SQLite 数据库
//
// 使用方法:
//   dart run tool/database/build_databases.dart
//
// 输出:
//   assets/databases/translation.db
//   assets/databases/cooccurrence.db

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

// 数据库大小限制: 100MB
const int _maxDatabaseSize = 100 * 1024 * 1024;

// 批次大小
const int _batchSize = 10000;

/// 构建翻译数据库
Future<void> buildTranslationDatabase() async {
  print('📦 Building translation database...');

  const csvPath = 'assets/translations/hf_danbooru_tags.csv';
  final outputDir = Directory('assets/databases');
  final outputPath = p.join(outputDir.path, 'translation.db');

  if (!await File(csvPath).exists()) {
    print('  ❌ CSV not found: $csvPath');
    return;
  }

  await outputDir.create(recursive: true);

  // 删除旧数据库
  final oldDb = File(outputPath);
  if (await oldDb.exists()) {
    await oldDb.delete();
    print('  🗑️  Deleted old database');
  }

  // 创建新数据库
  final db = await databaseFactoryFfi.openDatabase(
    outputPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        // 标签表
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            type INTEGER NOT NULL DEFAULT 0,
            count INTEGER NOT NULL DEFAULT 0
          )
        ''');

        // 翻译表
        await db.execute('''
          CREATE TABLE translations (
            tag_id INTEGER NOT NULL,
            language TEXT NOT NULL,
            translation TEXT NOT NULL,
            PRIMARY KEY (tag_id, language),
            FOREIGN KEY (tag_id) REFERENCES tags(id)
          )
        ''');

        // 索引
        await db.execute('CREATE INDEX idx_tags_name ON tags(name)');
        await db.execute('CREATE INDEX idx_tags_type ON tags(type)');
        await db.execute(
          'CREATE INDEX idx_translations_lang ON translations(language)',
        );

        print('  ✅ Tables created');
      },
    ),
  );

  try {
    // 解析 CSV
    print('  📖 Reading CSV...');
    final content = await File(csvPath).readAsString();
    final lines = content.split('\n');

    print('  📝 Total lines: ${lines.length}');

    var importedTags = 0;
    var importedTranslations = 0;
    var currentTagId = 1;

    // 使用事务批量导入
    await db.transaction((txn) async {
      final tagBatch = <Map<String, dynamic>>[];
      final translationBatch = <Map<String, dynamic>>[];

      for (var i = 1; i < lines.length; i++) {
        // 跳过表头
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = _parseCsvLine(line);
        if (parts.length < 4) continue;

        final name = parts[0].toLowerCase().trim();
        final type = int.tryParse(parts[1]) ?? 0;
        final count = int.tryParse(parts[2]) ?? 0;
        final cnTranslation = parts[3].trim();

        if (name.isEmpty) continue;

        // 添加标签
        tagBatch.add({
          'id': currentTagId,
          'name': name,
          'type': type,
          'count': count,
        });

        // 添加中文翻译
        if (cnTranslation.isNotEmpty) {
          translationBatch.add({
            'tag_id': currentTagId,
            'language': 'zh',
            'translation': cnTranslation,
          });
        }

        currentTagId++;

        // 批量提交
        if (tagBatch.length >= _batchSize) {
          await _insertBatch(txn, 'tags', tagBatch);
          await _insertBatch(txn, 'translations', translationBatch);
          importedTags += tagBatch.length;
          importedTranslations += translationBatch.length;
          tagBatch.clear();
          translationBatch.clear();

          if (importedTags % 50000 == 0) {
            print('    Imported $importedTags tags...');
          }
        }
      }

      // 提交剩余数据
      if (tagBatch.isNotEmpty) {
        await _insertBatch(txn, 'tags', tagBatch);
        await _insertBatch(txn, 'translations', translationBatch);
        importedTags += tagBatch.length;
        importedTranslations += translationBatch.length;
      }
    });

    print(
      '  ✅ Imported $importedTags tags, $importedTranslations translations',
    );

    // 验证数据库大小
    final dbFile = File(outputPath);
    final size = await dbFile.length();
    print('  📊 Database size: ${_formatFileSize(size)}');

    _checkSizeWarning(size, 'Translation');

    print('  ✅ Translation database built: $outputPath');
  } finally {
    await db.close();
  }
}

/// 构建共现数据库
Future<void> buildCooccurrenceDatabase() async {
  print('📦 Building cooccurrence database...');

  const csvPath = 'assets/translations/hf_danbooru_cooccurrence.csv';
  final outputDir = Directory('assets/databases');
  final outputPath = p.join(outputDir.path, 'cooccurrence.db');

  if (!await File(csvPath).exists()) {
    print('  ❌ CSV not found: $csvPath');
    return;
  }

  await outputDir.create(recursive: true);

  // 删除旧数据库
  final oldDb = File(outputPath);
  if (await oldDb.exists()) {
    await oldDb.delete();
    print('  🗑️  Deleted old database');
  }

  // 创建新数据库
  final db = await databaseFactoryFfi.openDatabase(
    outputPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cooccurrences (
            tag1 TEXT NOT NULL,
            tag2 TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0,
            cooccurrence_score REAL NOT NULL DEFAULT 0.0,
            PRIMARY KEY (tag1, tag2)
          )
        ''');

        // 索引
        await db.execute('''
          CREATE INDEX idx_cooccurrences_tag1_count 
          ON cooccurrences(tag1, count DESC, tag2)
        ''');

        print('  ✅ Table created');
      },
    ),
  );

  try {
    // 解析 CSV
    print('  📖 Reading CSV...');
    final content = await File(csvPath).readAsString();
    final lines = content.split('\n');

    print('  📝 Total lines: ${lines.length}');

    var importedCount = 0;

    // 使用事务批量导入
    await db.transaction((txn) async {
      final batch = <Map<String, dynamic>>[];

      for (var i = 1; i < lines.length; i++) {
        // 跳过表头
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length < 3) continue;

        final tag1 = parts[0].trim().toLowerCase();
        final tag2 = parts[1].trim().toLowerCase();
        final count = double.tryParse(parts[2].trim())?.toInt() ?? 0;

        if (tag1.isEmpty || tag2.isEmpty || count <= 0) continue;

        batch.add({
          'tag1': tag1,
          'tag2': tag2,
          'count': count,
          'cooccurrence_score': 0.0,
        });

        // 批量提交
        if (batch.length >= _batchSize) {
          await _insertBatch(txn, 'cooccurrences', batch);
          importedCount += batch.length;
          batch.clear();

          if (importedCount % 100000 == 0) {
            print('    Imported $importedCount records...');
          }
        }
      }

      // 提交剩余数据
      if (batch.isNotEmpty) {
        await _insertBatch(txn, 'cooccurrences', batch);
        importedCount += batch.length;
      }
    });

    print('  ✅ Imported $importedCount cooccurrence records');

    // 验证数据库大小
    final dbFile = File(outputPath);
    final size = await dbFile.length();
    print('  📊 Database size: ${_formatFileSize(size)}');

    _checkSizeWarning(size, 'Cooccurrence');

    print('  ✅ Cooccurrence database built: $outputPath');
  } finally {
    await db.close();
  }
}

/// 检查数据库大小并输出警告
void _checkSizeWarning(int size, String name) {
  if (size > _maxDatabaseSize) {
    print('  ⚠️  WARNING: $name database exceeds 100MB limit!');
  }
}

/// 格式化文件大小
String _formatFileSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(2)} MB';
}

/// 批量插入辅助函数
Future<void> _insertBatch(
  Transaction txn,
  String table,
  List<Map<String, dynamic>> records,
) async {
  if (records.isEmpty) return;

  final columns = records.first.keys.toList();
  final placeholders = records.map((record) {
    return '(${columns.map((_) => '?').join(', ')})';
  }).join(', ');

  final values = <dynamic>[];
  for (final record in records) {
    for (final col in columns) {
      values.add(record[col]);
    }
  }

  final sql = 'INSERT INTO $table (${columns.join(', ')}) VALUES $placeholders';
  await txn.execute(sql, values);
}

/// 解析 CSV 行（处理引号）
List<String> _parseCsvLine(String line) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];

    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        // 转义引号
        buffer.write('"');
        i++; // 跳过下一个引号
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      result.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }

  result.add(buffer.toString().trim());
  return result;
}

/// 主函数
Future<void> main() async {
  print('🔧 Database Build Tool');
  print('');

  // 初始化 FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final stopwatch = Stopwatch()..start();

  try {
    await buildTranslationDatabase();
    print('');
    await buildCooccurrenceDatabase();

    stopwatch.stop();
    print('');
    print('✨ All databases built in ${stopwatch.elapsedMilliseconds}ms');
    print('');
    print('📁 Output location: assets/databases/');
    print('   - translation.db');
    print('   - cooccurrence.db');
  } catch (e, stack) {
    print('');
    print('❌ Build failed: $e');
    print(stack);
    exit(1);
  }
}
