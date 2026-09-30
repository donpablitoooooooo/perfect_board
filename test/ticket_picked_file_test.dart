import 'dart:typed_data';

import 'package:perfect_board/src/widgets/ticket_fields.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG 1×1: basta a far scegliere la miniatura.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _wrap(PlatformFile file) => MaterialApp(
    home: Scaffold(
        body: TicketPickedFileChip(file: file, onRemove: () {})));

void main() {
  testWidgets('un\'immagine in attesa ha già la miniatura', (tester) async {
    await tester.pumpWidget(_wrap(PlatformFile(
        name: 'screenshot_1.png', size: _png.length, bytes: _png)));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('screenshot_1.png'), findsOneWidget);
  });

  testWidgets('un file che non è un\'immagine ha l\'icona', (tester) async {
    await tester.pumpWidget(_wrap(PlatformFile(
        name: 'log.txt', size: 3, bytes: Uint8List.fromList([1, 2, 3]))));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });
}
