import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_board/src/board_file.dart';

BoardFile _file(String name) =>
    BoardFile(name: name, bytes: Uint8List.fromList([1, 2, 3]));

void main() {
  test('estensione senza il punto', () {
    expect(_file('shot.png').extension, 'png');
    expect(_file('archivio.tar.gz').extension, 'gz');
  });

  test('niente estensione', () {
    expect(_file('README').extension, isNull);
    expect(_file('.gitignore').extension, isNull);
    expect(_file('strano.').extension, isNull);
  });

  test('la dimensione è quella dei byte', () {
    expect(_file('x.bin').size, 3);
  });
}
