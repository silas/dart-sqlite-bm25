# SQLite BM25

An [Okapi BM25][bm25] implementation for the SQLite [FTS4][fts4]
(full-text search) extension.

## Example

``` dart
import 'package:sqflite/sqflite.dart';
import 'package:sqlite_bm25/sqlite_bm25.dart';

example() async {
  final table = 'bm25_test';

  final db = await openDatabase(':memory:', version: 1,
      onCreate: (Database db, int version) async {
    await db.execute('CREATE VIRTUAL TABLE $table USING fts4(name)');
  });

  await db.insert(table, {'rowid': 1, 'name': 'Sam Rivers'});
  await db.insert(table, {'rowid': 2, 'name': 'Samwise "Sam" Gamgee'});
  await db.insert(table, {'rowid': 3, 'name': 'Sam'});
  await db.insert(table, {'rowid': 4, 'name': 'Sam Seaborn'});
  await db.insert(table, {'rowid': 5, 'name': 'Samwell "Sam" Tarly'});

  var rows = await db.query(
    table,
    columns: [
      'name',
      'matchinfo($table, "$bm25FormatString") as info',
    ],
    where: '$table MATCH ?',
    whereArgs: ['sam'],
  );

  rows = rows.map((row) {
    return {
      'name': row['name'],
      'rank': bm25(row['info']),
    };
  }).toList();

  rows.sort((a, b) => a['rank'].compareTo(b['rank']));

  final names = rows.take(3).map((r) => r['name']).join(', ');

  print(names);

  await db.close();
}
```

[bm25]: https://en.wikipedia.org/wiki/Okapi_BM25
[fts4]: https://www.sqlite.org/fts3.html
