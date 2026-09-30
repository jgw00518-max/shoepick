import 'package:flutter/material.dart';

import 'locale_dictionary.dart';

/// 목업의 한국어 문구와 영어 사전을 화면 전체에서 공유합니다.
class LocaleScope extends InheritedWidget {
  const LocaleScope({super.key, required this.language, required super.child});

  final String language;

  static String languageOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.language ??
      '한국어';

  @override
  bool updateShouldNotify(LocaleScope oldWidget) =>
      language != oldWidget.language;
}

final _translationKeys = englishDictionary.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));

String translateMockupText(String value, String language) {
  if (language != 'English') return value;
  final exact = englishDictionary[value];
  if (exact != null) return exact;
  var result = value;
  for (final key in _translationKeys) {
    if (key.length < 2 || !result.contains(key)) continue;
    result = result.replaceAll(key, englishDictionary[key]!);
  }
  return result;
}

/// Text와 같은 기본 매개변수로 문구를 렌더링하며 언어 변경 시 다시 그립니다.
class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) => Text(
    translateMockupText(data, LocaleScope.languageOf(context)),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
  );
}
