import 'package:perfect_board/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Pezzi di interfaccia condivisi dalla Bacheca.
///
/// Comparivano identici in cinque file: qui stanno una volta sola, così un
/// ritocco allo stile non lascia indietro un pezzo.

/// Toast di conferma, in alto e nel colore primario del tema.
void ticketToast(BuildContext context, String message) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.TOP,
    timeInSecForIosWeb: 3,
    backgroundColor: Theme.of(context).primaryColor,
    textColor: Colors.white,
    fontSize: 14.0,
  );
}

/// Chip colorata, in due taglie.
///
/// [dense] è la versione da card: più stretta, senza angoli tondi, per stare
/// in fila con le altre senza rubare spazio al titolo.
class TicketChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;
  final IconData? icon;

  const TicketChip({
    super.key,
    required this.label,
    required this.color,
    this.dense = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 1)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: dense ? null : BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stato vuoto discreto, in linea con `TableSection`.
class TicketEmpty extends StatelessWidget {
  final String text;

  const TicketEmpty(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(color: subtitleColor, fontSize: 13),
      ),
    );
  }
}
