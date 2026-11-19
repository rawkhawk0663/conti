import 'dart:io';

import 'package:flutter/material.dart';

/// Ein Punkt in einem Kontextmenü.
class MenuAction<T> {
  const MenuAction(this.value, this.icon, this.label, {this.danger = false});
  final T value;
  final IconData icon;
  final String label;

  /// Rot (z. B. „Löschen“).
  final bool danger;
}

/// Menü an der Stelle [at] (Rechtsklick, Surface) oder als Blatt von unten
/// (Handy). Gibt den gewählten Wert zurück, null = nichts gewählt.
Future<T?> showContextMenu<T>(BuildContext context, {Offset? at, required List<MenuAction<T>> actions}) {
  final danger = Theme.of(context).colorScheme.error;
  if (at != null) {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(at);
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        for (final a in actions)
          PopupMenuItem<T>(
            value: a.value,
            height: 44,
            child: Row(
              children: [
                Icon(a.icon, size: 20, color: a.danger ? danger : null),
                const SizedBox(width: 12),
                Text(a.label, style: a.danger ? TextStyle(color: danger) : null),
              ],
            ),
          ),
      ],
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.danger ? danger : null),
              title: Text(a.label, style: a.danger ? TextStyle(color: danger) : null),
              onTap: () => Navigator.pop(context, a.value),
            ),
        ],
      ),
    ),
  );
}

/// Macht [child] empfänglich für das Kontextmenü: Rechtsklick (Maus, an der
/// Stelle des Zeigers) und langes Drücken (Finger, Stift). Auf dem Computer
/// erscheint das Menü auch beim langen Drücken an der Stelle, auf dem Handy
/// als Blatt von unten.
class ContextMenuArea extends StatelessWidget {
  const ContextMenuArea({super.key, required this.onMenu, required this.child});

  /// [at] ist die Stelle für das Menü, oder null für das Blatt von unten.
  final void Function(Offset? at) onMenu;
  final Widget child;

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(_desktop ? d.globalPosition : null),
      child: child,
    );
  }
}

/// Kurzer Hinweis mit „Rückgängig“ (verschwindet nach 6 Sekunden).
void showUndo(BuildContext context, String text, VoidCallback onUndo, {String undoLabel = 'Rückgängig'}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      persist: false,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    ),
  );
}
