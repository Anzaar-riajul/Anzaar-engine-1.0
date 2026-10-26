import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../models.dart';
import 'app_database.dart';

class SnippetRepository {
  SnippetRepository._() : _database = null;
  SnippetRepository.forDatabase(Database database) : _database = database;

  final Database? _database;
  static final SnippetRepository instance = SnippetRepository._();

  Future<Database> get _db async =>
      _database ?? await AppDatabase.instance.database;

  final _changeController =
      StreamController<List<SnippetFolderItem>>.broadcast();
  Stream<List<SnippetFolderItem>> get onSnippetsChanged =>
      _changeController.stream;

  void _notify() async {
    final list = await fetchAllFolders();
    _changeController.add(list);
  }

  Future<List<SnippetFolderItem>> fetchAllFolders() async {
    final db = await _db;
    final folderRows = await db.query(
      'snippet_folders',
      orderBy: 'sort_order ASC, updated_at DESC',
    );
    final snippetRows = await db.query(
      'snippets',
      orderBy: 'sort_order ASC, updated_at DESC',
    );

    final snippetsByFolder = <String, List<SnippetItem>>{};
    for (final row in snippetRows) {
      final item = SnippetItem(
        id: row['id'] as String,
        folderId: row['folder_id'] as String,
        title: row['title'] as String,
        content: row['content'] as String,
        updatedAt: row['updated_at'] as int,
        sortOrder: row['sort_order'] as int? ?? 0,
      );
      snippetsByFolder.putIfAbsent(item.folderId, () => []).add(item);
    }

    return folderRows.map((row) {
      final fId = row['id'] as String;
      return SnippetFolderItem(
        id: fId,
        title: row['title'] as String,
        isEnabled: (row['is_enabled'] as int? ?? 1) == 1,
        updatedAt: row['updated_at'] as int,
        sortOrder: row['sort_order'] as int? ?? 0,
        snippets: snippetsByFolder[fId] ?? const [],
      );
    }).toList();
  }

  Future<void> saveFolder(SnippetFolderItem folder) async {
    final db = await _db;
    await db.insert('snippet_folders', {
      'id': folder.id,
      'title': folder.title,
      'is_enabled': folder.isEnabled ? 1 : 0,
      'updated_at': folder.updatedAt,
      'sort_order': folder.sortOrder,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notify();
  }

  Future<void> deleteFolder(String folderId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'snippets',
        where: 'folder_id = ?',
        whereArgs: [folderId],
      );
      await txn.delete(
        'snippet_folders',
        where: 'id = ?',
        whereArgs: [folderId],
      );
    });
    _notify();
  }

  Future<void> saveSnippet(SnippetItem snippet) async {
    final db = await _db;
    await db.insert('snippets', {
      'id': snippet.id,
      'folder_id': snippet.folderId,
      'title': snippet.title,
      'content': snippet.content,
      'updated_at': snippet.updatedAt,
      'sort_order': snippet.sortOrder,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notify();
  }

  Future<void> deleteSnippet(String snippetId) async {
    final db = await _db;
    await db.delete('snippets', where: 'id = ?', whereArgs: [snippetId]);
    _notify();
  }

  Future<bool> mergeRemoteFolders(List<SnippetFolderItem> remoteFolders) async {
    final db = await _db;
    bool changed = false;

    await db.transaction((txn) async {
      for (final remoteFolder in remoteFolders) {
        final existing = await txn.query(
          'snippet_folders',
          where: 'id = ?',
          whereArgs: [remoteFolder.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          await txn.insert('snippet_folders', {
            'id': remoteFolder.id,
            'title': remoteFolder.title,
            'is_enabled': remoteFolder.isEnabled ? 1 : 0,
            'updated_at': remoteFolder.updatedAt,
            'sort_order': remoteFolder.sortOrder,
          });
          changed = true;
        } else {
          final localUpdated = existing.first['updated_at'] as int;
          if (remoteFolder.updatedAt > localUpdated) {
            await txn.update(
              'snippet_folders',
              {
                'title': remoteFolder.title,
                'is_enabled': remoteFolder.isEnabled ? 1 : 0,
                'updated_at': remoteFolder.updatedAt,
                'sort_order': remoteFolder.sortOrder,
              },
              where: 'id = ?',
              whereArgs: [remoteFolder.id],
            );
            changed = true;
          }
        }

        // Process snippets inside this folder
        for (final remoteSnippet in remoteFolder.snippets) {
          final existingSnippet = await txn.query(
            'snippets',
            where: 'id = ?',
            whereArgs: [remoteSnippet.id],
            limit: 1,
          );

          if (existingSnippet.isEmpty) {
            await txn.insert('snippets', {
              'id': remoteSnippet.id,
              'folder_id': remoteSnippet.folderId,
              'title': remoteSnippet.title,
              'content': remoteSnippet.content,
              'updated_at': remoteSnippet.updatedAt,
              'sort_order': remoteSnippet.sortOrder,
            });
            changed = true;
          } else {
            final localSnippetUpdated =
                existingSnippet.first['updated_at'] as int;
            if (remoteSnippet.updatedAt > localSnippetUpdated) {
              await txn.update(
                'snippets',
                {
                  'folder_id': remoteSnippet.folderId,
                  'title': remoteSnippet.title,
                  'content': remoteSnippet.content,
                  'updated_at': remoteSnippet.updatedAt,
                  'sort_order': remoteSnippet.sortOrder,
                },
                where: 'id = ?',
                whereArgs: [remoteSnippet.id],
              );
              changed = true;
            }
          }
        }
      }
    });

    if (changed) {
      _notify();
    }
    return changed;
  }
}
