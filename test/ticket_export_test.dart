import 'package:perfect_board/src/models/ticket.dart';
import 'package:perfect_board/src/widgets/ticket_export.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://firebasestorage.googleapis.com/v0/b/example-project'
    '.firebasestorage.app/o/uploads%2Ftickets%2FAbCdEfGhIjKlMnOpQrSt%2F'
    '1790000000000_Screenshot.png'
    '?alt=media&token=00000000-0000-0000-0000-000000000000';

void main() {
  test('il percorso si ricava dal link degli allegati vecchi', () {
    expect(
      TicketAttachment.pathFromUrl(_url),
      'uploads/tickets/AbCdEfGhIjKlMnOpQrSt/'
      '1790000000000_Screenshot.png',
    );
    expect(TicketAttachment.pathFromUrl(''), '');
  });

  test('nell\'export finisce il percorso, mai il link con il token', () {
    final attachment = TicketAttachment.fromFirestore('a1', {
      'name': 'Screenshot.png',
      'url': _url,
      'contentType': 'image/png',
      'size': 36291,
    });
    final markdown = buildTicketMarkdown(
      ticket: const Ticket(
        id: 'AbCdEfGhIjKlMnOpQrSt',
        title: 'test',
        body: 'b',
        status: TicketStatus.inCarico,
        createdByName: 'ada',
        createdByEmail: '',
        createdByRole: 'admin',
      ),
      comments: const [],
      attachments: [attachment],
    );
    expect(markdown, isNot(contains('token=')));
    expect(markdown, isNot(contains('https://')));
    expect(markdown, contains('`uploads/tickets/AbCdEfGhIjKlMnOpQrSt/'));
    expect(markdown, contains('board.js files AbCdEf'));
  });
}
