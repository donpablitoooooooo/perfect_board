import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_board/perfect_board.dart';
import 'package:perfect_board/src/l10n.dart';

class _Orders extends BoardRefSource {
  const _Orders();

  @override
  String get kind => 'order';
  @override
  String get label => 'Order';
  @override
  IconData get icon => Icons.receipt_long_outlined;
  @override
  String? get collection => 'Orders';
  @override
  Future<List<BoardRefHit>> load() async => const [];
}

void main() {
  tearDown(() => PerfectBoard.configure(
      currentUser: () => const BoardUser(uid: '', name: 'Admin')));

  test('testi: lingua scelta, segnaposto, ripiego in inglese', () {
    PerfectBoard.configure(
        currentUser: () => const BoardUser(uid: 'u', name: 'Ada'),
        locale: () => 'it');
    expect(bt('statusNew'), 'Nuove');
    expect(bt('statusChanged', {'status': 'Nuove'}), 'Stato: Nuove');

    PerfectBoard.configure(
        currentUser: () => const BoardUser(uid: 'u', name: 'Ada'),
        locale: () => 'fr');
    expect(bt('statusNew'), 'New', reason: 'lingua che manca → inglese');
    expect(bt('nonEsiste'), 'nonEsiste');
  });

  test('l\'utente si legge a ogni uso', () {
    var name = 'Ada';
    PerfectBoard.configure(
        currentUser: () => BoardUser(uid: 'u', name: name));
    expect(PerfectBoard.user.name, 'Ada');
    name = 'Grace';
    expect(PerfectBoard.user.name, 'Grace');
  });

  test('un collegamento di tipo sconosciuto resta, con l\'icona generica', () {
    final ref =
        TicketRef.fromMap({'kind': 'invoice', 'id': 'f1', 'label': 'F 12'});
    expect(ref, isNotNull);
    expect(ref!.icon, Icons.link);
    expect(ref.kindLabel, 'invoice');
    expect(ref.key, 'invoice:f1');
    expect(TicketRef.fromMap({'kind': '', 'id': 'x'}), isNull);
  });

  test('con la sorgente registrata prende nome, icona e collection', () {
    PerfectBoard.configure(
        currentUser: () => const BoardUser(uid: 'u', name: 'Ada'),
        refSources: const [_Orders()]);
    final ref = TicketRef.fromMap({'kind': 'order', 'id': 'o1'})!;
    expect(ref.kindLabel, 'Order');
    expect(ref.icon, Icons.receipt_long_outlined);
    expect(ref.source?.collection, 'Orders');
    expect(ref.label, 'o1', reason: 'senza etichetta salvata vale l\'id');
  });
}
