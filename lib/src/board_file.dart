import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Un file da allegare, già in memoria: nome e contenuto.
///
/// È il tipo della board, non quello di `file_picker`: le schermate nascono
/// qui dentro (non da un selettore), i file in attesa restano in memoria
/// finché la scheda o il commento partono, e così `file_picker` si usa in un
/// punto solo, [pickBoardFiles].
class BoardFile {
  final String name;
  final Uint8List bytes;

  const BoardFile({required this.name, required this.bytes});

  int get size => bytes.length;

  /// Estensione senza il punto, `null` se il nome non ne ha.
  String? get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1);
  }
}

/// Quello che l'utente ha scelto: i file da tenere e i nomi di quelli
/// scartati perché più grandi di [maxBytes].
typedef BoardPick = ({List<BoardFile> files, List<String> tooBig});

/// Apre il selettore dei file e legge quelli scelti. I file oltre
/// [maxBytes] non si leggono nemmeno: si scartano e si nominano, così chi
/// chiama può dirlo.
Future<BoardPick> pickBoardFiles({required int maxBytes}) async {
  final picked = await FilePicker.pickFiles();
  final files = <BoardFile>[];
  final tooBig = <String>[];
  for (final file in picked) {
    final length = file.lengthSync() ?? await file.length();
    if (length != null && length > maxBytes) {
      tooBig.add(file.name);
      continue;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      tooBig.add(file.name);
      continue;
    }
    files.add(BoardFile(name: file.name, bytes: bytes));
  }
  return (files: files, tooBig: tooBig);
}
