import 'package:intl/intl.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/l10n_strings.dart';

/// Il testo [key] nella lingua di [PerfectBoard.locale], con i segnaposto
/// `{nome}` sostituiti da [args]. Lingua che manca → inglese; chiave che
/// manca → la chiave stessa, che in pagina si nota subito.
String bt(String key, [Map<String, String>? args]) {
  final strings = boardStrings[PerfectBoard.locale] ?? boardStrings['en']!;
  var text = strings[key] ?? boardStrings['en']![key] ?? key;
  args?.forEach((name, value) => text = text.replaceAll('{$name}', value));
  return text;
}

/// Formati delle date sulla board: giorno/mese/anno, come nell'app d'origine.
final dateFormat = DateFormat('dd/MM/yyyy');
final dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
