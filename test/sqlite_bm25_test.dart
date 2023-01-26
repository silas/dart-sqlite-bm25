import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart' show hex;
import 'package:sqlite_bm25/sqlite_bm25.dart';
import 'package:sqlite_bm25/src/matchinfo.dart';
import 'package:test/test.dart';

void main() {
  test('bm25FormatString', () {
    expect(bm25FormatString, 'pcnalx');
  });

  test('bm25', () {
    final matchinfo1 =
        Matchinfo.encode(Uint32List.fromList([1, 1, 5, 17, 14, 1, 3, 2]));
    expect(bm25(matchinfo1).toStringAsFixed(2), equals('-0.36'));

    final matchinfo2 =
        Matchinfo.encode(Uint32List.fromList([1, 1, 5, 17, 19, 2, 3, 2]));
    expect(bm25(matchinfo2).toStringAsFixed(2), equals('-0.45'));
  });

  group('integration', () {
    final sentences = [
      // rowid: 1
      'It is a truth universally acknowledged, that a single man in possession '
          'of a good fortune, must be in want of a wife.',
      // rowid: 2
      'However little known the feelings or views of such a man may be on his '
          'first entering a neighbourhood, this truth is so well fixed in the '
          'minds of the surrounding families, that he is considered the '
          'rightful property of some one or other of their daughters.',
      // rowid: 3
      '"My dear Mr. Bennet," said his lady to him one day, "have you heard '
          'that Netherfield Park is let at last?"',
      // rowid: 4
      'Mr. Bennet replied that he had not.',
      // rowid: 5
      '"But it is," returned she; "for Mrs. Long has just been here, and she '
          'told me all about it."',
      // rowid: 6
      'Mr. Bennet made no answer.',
      // rowid: 7
      '"Do you not want to know who has taken it?" cried his wife impatiently.',
      // rowid: 8
      '"You want to tell me, and I have no objection to hearing it."',
      // rowid: 9
      'This was invitation enough.',
    ].map((v) => [v.replaceAll('"', "'")]).toList();

    Future<void> runTest(IntegrationTest t) {
      return t.execute();
    }

    test('no documents', () {
      return runTest(IntegrationTest(
        columns: ['content'],
        documents: [],
        term: 'hello',
        expected: [],
      ));
    });

    test('single column and record', () {
      return runTest(IntegrationTest(
        columns: ['content'],
        documents: [
          ['hello'],
        ],
        term: 'hello',
        expected: [Result(1, -0.000001)],
      ));
    });

    test('no match', () {
      return runTest(IntegrationTest(
        columns: ['content'],
        documents: [
          ['hello'],
        ],
        term: 'john',
        expected: [],
      ));
    });

    test('multiple columns', () {
      return runTest(IntegrationTest(
        columns: ['title', 'body'],
        documents: [
          ['Hello', 'World'],
          ['Hello Hello', 'Say hello to Jane for me.'],
          ['Bye', 'Have a good trip.'],
        ],
        term: 'hello',
        expected: [
          Result(1, -0.000001),
          Result(2, -0.424083),
        ],
      ));
    });

    test('sentences', () async {
      await runTest(IntegrationTest(
        columns: ['sentence'],
        documents: sentences,
        term: 'silas',
        expected: [],
      ));

      await runTest(IntegrationTest(
        columns: ['sentence'],
        documents: sentences,
        term: 'invitation',
        expected: [
          Result(9, -2.524283),
        ],
      ));

      await runTest(IntegrationTest(
        columns: ['sentence'],
        documents: sentences,
        term: 'man',
        expected: [
          Result(1, -0.960002),
          Result(2, -0.638014),
        ],
      ));

      await runTest(IntegrationTest(
        columns: ['word', 'text'],
        documents: sentences.map((v) {
          final r = <String>[];
          r.add(v[0].split(' ')[0]);
          r.add(v[0]);
          return r;
        }).toList(),
        term: 'you',
        expected: [
          Result(3, -0.564685),
          Result(7, -0.667207),
          Result(8, -4.154174)
        ],
        weights: [2.0],
      ));
    });
  }, tags: ['integration']);
}

class Result implements Comparable<Result> {
  late int id;
  late double _rank;

  Result(this.id, this._rank);

  Result.fromRow(List<String> row, {List<double>? weights}) {
    if (row.length != 2) {
      throw new TestFailure('Result row should have 2 columns: $row');
    }
    id = int.parse(row[0]);
    _rank = bm25(hex.decode(row[1]) as Uint8List, weights: weights);
  }

  bool operator ==(dynamic other) {
    return other != null &&
        other is Result &&
        id == other.id &&
        rank == other.rank;
  }

  double get rank {
    final r = 1000000.0;
    return (_rank * r).round().toDouble() / r;
  }

  int compareTo(Result other) {
    final r = rank.compareTo(other.rank);
    return r != 0 ? r : id.compareTo(other.id);
  }

  String toString() {
    return 'Result(id: $id, rank: $rank)';
  }
}

class IntegrationTest {
  final List<String> columns;
  final List<List<String>> documents;
  final String term;
  final List<Result> expected;
  final List<double>? weights;

  IntegrationTest({
    required this.columns,
    required this.documents,
    required this.term,
    required this.expected,
    this.weights,
  });

  Future<void> execute() async {
    List<String> statements = [];

    statements.add(_createTable());

    for (var i = 0; i < documents.length; i++) {
      statements.add(_insert(i + 1, documents[i]));
    }

    statements.add(_select());

    final sql = statements.join(';\n') + ';\n';

    final stdout = <int>[];
    final stderr = <int>[];
    final completer = Completer<int>();
    final p = await Process.start('sqlite3', ['--list', '--noheader']);

    p.stdout.listen((List<int> event) {
      stdout.addAll(event);
    }, onDone: () async => completer.complete(await p.exitCode));

    p.stderr.listen((List<int> event) {
      stderr.addAll(event);
    });

    p.stdin.write(sql);
    await p.stdin.close();

    if (await completer.future != 0) {
      final error = await utf8.decoder.convert(stderr);
      throw new TestFailure('Failed to execute sqlite3: $error');
    }

    final results = (await utf8.decoder.convert(stdout))
        .trim()
        .split('\n')
        .where((v) => v.isNotEmpty)
        .map((v) => Result.fromRow(v.split('|'), weights: weights))
        .toList()
      ..sort();

    expected.sort();

    expect(results, equals(expected));
  }

  String _createTable() {
    return 'CREATE VIRTUAL TABLE bm25_test USING fts4(${columns.join(", ")})';
  }

  String _insert(int id, List<String> values) {
    var columnsSql = _strings([]
      ..add('rowid')
      ..addAll(columns));
    var valuesSql = _strings([]
      ..add('$id')
      ..addAll(values));

    return 'INSERT INTO bm25_test ($columnsSql) VALUES ($valuesSql)';
  }

  String _select() {
    return """
    SELECT rowid, hex(matchinfo(bm25_test, "$bm25FormatString"))
    FROM bm25_test
    WHERE bm25_test MATCH ${jsonEncode(term)}
    """;
  }

  String _strings(List<String> values) {
    var sql = jsonEncode(values);
    return sql.substring(1, sql.length - 1);
  }
}
