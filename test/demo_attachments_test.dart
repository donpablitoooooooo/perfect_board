import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_board/perfect_board.dart';
import 'package:perfect_board/src/local_attachments.dart';
import 'package:perfect_board/src/widgets/ticket_attachments.dart';

void main() {
  tearDown(() {
    LocalAttachments.clear();
    PerfectBoard.configure(
        currentUser: () => const BoardUser(uid: '', name: 'Admin'));
  });

  test('account demo: il file resta in memoria, senza toccare Firebase',
      () async {
    PerfectBoard.configure(
      currentUser: () => const BoardUser(uid: 'd', name: 'Demo'),
      demo: () => true,
    );
    // Se provasse Storage o Firestore fallirebbe: Firebase qui non c'è.
    await uploadTicketAttachment(
      ticketId: 't1',
      file: PlatformFile(
          name: 'shot.png', size: 3, bytes: Uint8List.fromList([1, 2, 3])),
      commentId: 'c1',
    );

    final local = LocalAttachments.of('t1');
    expect(local, hasLength(1));
    expect(local.single.name, 'shot.png');
    expect(local.single.contentType, 'image/png');
    expect(local.single.commentId, 'c1');
    expect(local.single.uploadedByName, 'Demo');
    expect(local.single.isLocal, isTrue);
    expect(LocalAttachments.of('altra'), isEmpty);

    LocalAttachments.remove('t1', local.single.id);
    expect(LocalAttachments.of('t1'), isEmpty);
  });

  testWidgets('la miniatura di un file in memoria viene dai byte',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TicketAttachmentTile(
        attachment: TicketAttachment(
          id: 'local-0',
          name: 'shot.png',
          url: '',
          contentType: 'image/png',
          size: 3,
          uploadedByName: 'Demo',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        onOpen: () {},
      ),
    ));
    expect(find.byType(Image), findsOneWidget);
  });

  test('di default non è un account demo', () {
    expect(PerfectBoard.isDemo, isFalse);
  });
}
