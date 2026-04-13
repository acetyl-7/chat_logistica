import 'dart:io';

void main() {
  final file = File('lib/screens/dashboard_screen.dart');
  String content = file.readAsStringSync();
  content = content.replaceAll(r'\n', '\n');
  file.writeAsStringSync(content);
}
