import 'package:perfect_board/src/models/ticket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mezzogiorno di [d] giorni fa: i giorni si contano sul calendario, quindi
/// l'ora in cui gira il test non conta.
DateTime _daysAgo(int d) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - d, 12);
}

DateTime _inDays(int d) => DateTime.now().add(Duration(days: d));

Ticket _ticket(
  TicketStatus status, {
  DateTime? created,
  DateTime? changed,
  DateTime? taken,
  DateTime? due,
}) =>
    Ticket(
      id: 'abcdef123',
      title: 't',
      body: 'b',
      status: status,
      createdByName: '',
      createdByEmail: '',
      createdByRole: 'admin',
      createdAt: created,
      statusChangedAt: changed,
      takenAt: taken,
      dueAt: due,
    );

void main() {
  group('da quando è nella colonna', () {
    test('conta da statusChangedAt quando c\'è', () {
      final t = _ticket(TicketStatus.inCarico,
          created: _daysAgo(30), changed: _daysAgo(3));
      expect(t.daysInStatus, 3);
    });

    test('le schede vecchie ripiegano sulla presa in carico', () {
      final t = _ticket(TicketStatus.inCarico,
          created: _daysAgo(30), taken: _daysAgo(5));
      expect(t.daysInStatus, 5);
    });

    test('conta i giorni di calendario, non le 24 ore', () {
      // Spostata ieri alle 10:50, guardata stamattina alle 9: è "da ieri".
      final t = _ticket(TicketStatus.inCarico,
          changed: DateTime(2026, 9, 28, 10, 50));
      expect(t.daysInStatusAt(DateTime(2026, 9, 29, 9)), 1);
      expect(t.daysInStatusAt(DateTime(2026, 9, 28, 23, 59)), 0);
      // A cavallo del cambio dell'ora legale (25 ottobre 2026).
      expect(t.daysInStatusAt(DateTime(2026, 10, 28, 0, 30)), 30);
    });

    test('e altrimenti sull\'apertura', () {
      final t = _ticket(TicketStatus.nuova, created: _daysAgo(4));
      expect(t.daysInStatus, 4);
    });
  });

  group('colore del tempo', () {
    test('normale sotto la settimana', () {
      expect(
          _ticket(TicketStatus.inCarico, changed: _daysAgo(6)).statusAgeColor,
          isNull);
    });

    test('arancio da una settimana, rosso da due', () {
      expect(
          _ticket(TicketStatus.daChiarire, changed: _daysAgo(7)).statusAgeColor,
          Colors.orange);
      expect(_ticket(TicketStatus.pronta, changed: _daysAgo(14)).statusAgeColor,
          Colors.redAccent);
    });

    test('in Nuove e Approvata non si accende mai', () {
      expect(_ticket(TicketStatus.nuova, changed: _daysAgo(40)).statusAgeColor,
          isNull);
      expect(_ticket(TicketStatus.fatto, changed: _daysAgo(40)).statusAgeColor,
          isNull);
    });
  });

  group('colore della scadenza', () {
    test('rossa se passata, arancio a due giorni, normale più in là', () {
      expect(_ticket(TicketStatus.inCarico, due: _daysAgo(1)).dueColor,
          Colors.redAccent);
      expect(_ticket(TicketStatus.inCarico, due: _inDays(2)).dueColor,
          Colors.orange);
      expect(_ticket(TicketStatus.inCarico, due: _inDays(5)).dueColor, isNull);
    });

    test('su una scheda approvata la scadenza non preoccupa', () {
      expect(_ticket(TicketStatus.fatto, due: _daysAgo(3)).dueColor, isNull);
    });
  });
}
