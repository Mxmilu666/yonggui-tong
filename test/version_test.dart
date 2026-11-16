import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonggui_tong/app/version.dart';

void main() {
  test('关于页显示的版本与 pubspec 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec)![1];
    expect(appVersion, version);
  });
}
