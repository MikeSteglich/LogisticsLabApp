/// Help of the app: topics in assets/help/(language).json and their search - in the help window of the app and in
/// the help menu of macOS.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

class HelpTopic {
  final String id;
  final String title;
  final String keywords; // further words the search finds, e.g. synonyms
  final String body; // paragraphs, "- " lists, **bold**

  const HelpTopic(this.id, this.title, this.keywords, this.body);

  factory HelpTopic.fromJson(Map<String, dynamic> j) =>
      HelpTopic(j['id'] as String, j['title'] as String, j['keywords'] as String? ?? '', j['body'] as String);

  /// body without the marks of the text - for the search and the snippets
  String get plain => body.replaceAll('**', '').replaceAll(RegExp(r'^- ', multiLine: true), '');
}

/// a topic found by the search - snippet: the part of the text with the first hit
typedef HelpHit = ({HelpTopic topic, String snippet});

class HelpBook {
  final String language;
  final List<HelpTopic> topics;
  const HelpBook(this.language, this.topics);

  static final _books = <String, HelpBook>{};

  /// the topics of the language - English if there are none
  static Future<HelpBook> load(String language) async {
    if (_books[language] case final b?) return b;
    String text;
    try {
      text = await rootBundle.loadString('assets/help/$language.json');
    } catch (_) {
      text = await rootBundle.loadString('assets/help/en.json');
    }
    final topics = [for (final t in jsonDecode(text) as List) HelpTopic.fromJson(t as Map<String, dynamic>)];
    return _books[language] = HelpBook(language, topics);
  }

  HelpTopic? topic(String id) => topics.where((t) => t.id == id).firstOrNull;

  /// lower case without accents and umlauts - "Lösung" is found with "losung" and "loesung"
  static String fold(String s) {
    var r = s.toLowerCase();
    const map = {
      'ä': 'a',
      'ö': 'o',
      'ü': 'u',
      'ß': 'ss',
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
      'œ': 'oe',
      '’': "'",
    };
    for (final MapEntry(:key, :value) in map.entries) {
      r = r.replaceAll(key, value);
    }
    return r.replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
  }

  /// topics with all words of the query - the best first: words in the title count most, then the keywords
  List<HelpHit> search(String query) {
    final words = fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [for (final t in topics) (topic: t, snippet: '')];
    final scored = <(HelpTopic, int)>[];
    for (final t in topics) {
      final title = fold(t.title), keywords = fold(t.keywords), body = fold(t.plain);
      var score = 0;
      for (final w in words) {
        final s = (title.contains(w) ? 5 : 0) + (keywords.contains(w) ? 3 : 0) + (body.contains(w) ? 1 : 0);
        if (s == 0) {
          score = 0;
          break;
        }
        score += s;
      }
      if (score > 0) scored.add((t, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (t, _) in scored) (topic: t, snippet: _snippet(t.plain, words))];
  }

  /// the sentence with the first word of the query that occurs in the text - shortened
  static String _snippet(String text, List<String> words) {
    final folded = fold(text);
    for (final w in words) {
      final i = folded.indexOf(w);
      if (i < 0) continue;
      // the folded text can be shorter than the text (ae -> a): the position is near enough for a snippet
      final at = i.clamp(0, text.length - 1);
      var start = text.lastIndexOf(RegExp(r'[.\n]'), at);
      start = start < 0 ? 0 : start + 1;
      final end = text.indexOf(RegExp(r'[.\n]'), at);
      final s = text.substring(start, end < 0 ? text.length : end + 1).trim();
      return s.length > 140 ? '${s.substring(0, 137)}…' : s;
    }
    return '';
  }
}
