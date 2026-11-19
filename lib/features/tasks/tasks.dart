import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/deadlines.dart';
import '../../core/model/crm.dart';
import '../../core/model/synced.dart';
import '../../widgets/visuals.dart';

/// Aufgabe anlegen ([task] == null) oder ändern. [clientId]: vorgewählter Kunde.
Future<void> editTask(BuildContext context, {Task? task, String? clientId}) async {
  final s = ContiScope.read(context);
  final t = task?.copy() ?? Task(id: newId(), title: '', clientId: clientId);
  final title = TextEditingController(text: t.title);
  final notes = TextEditingController(text: t.notes);
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(task == null ? tr('Neue Aufgabe', 'New task') : tr('Aufgabe', 'Task')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: task == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: tr('Was ist zu tun?', 'What needs doing?')),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: t.due ?? Day.today(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(Day.today().year + 5, 12, 31),
                          );
                          if (d != null) setState(() => t.due = d);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(labelText: tr('Frist', 'Deadline'), suffixIcon: const Icon(Icons.event)),
                          child: Text(t.due == null ? tr('Ohne Frist', 'No deadline') : Day.short(t.due!)),
                        ),
                      ),
                    ),
                    if (t.due != null)
                      IconButton(
                        tooltip: tr('Frist entfernen', 'Remove deadline'),
                        onPressed: () => setState(() => t.due = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: s.clients.any((c) => c.id == t.clientId) ? t.clientId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Kunde', 'Client')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Allgemein', 'General'))),
                    for (final c in s.clients) DropdownMenuItem(value: c.id, child: Text(c.displayName, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => t.clientId = v),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(labelText: tr('Notiz', 'Note')),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (task != null)
            TextButton(
              onPressed: () async {
                await s.deleteTask(task);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: Text(tr('Löschen', 'Delete')),
            ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                setState(() => error = tr('Bitte beschreiben, was zu tun ist.', 'Please describe what needs doing.'));
                return;
              }
              t
                ..title = title.text.trim()
                ..notes = notes.text.trim();
              Navigator.pop(context, true);
            },
            child: Text(tr('Sichern', 'Save')),
          ),
        ],
      ),
    ),
  );
  if (ok == true) await s.saveTask(t);
}

/// Erledigt / wieder offen.
Future<void> toggleTask(ContiState s, Task t) async {
  final x = t.copy()
    ..done = !t.done
    ..doneAt = t.done ? null : DateTime.now().toUtc();
  await s.saveTask(x);
}

/// Eine Zeile mit Häkchen, Titel, Kunde und Ampel.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.showClient = true});
  final Task task;
  final bool showClient;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final u = Urgency.of(task, s.business.deadlineRules);
    final who = showClient ? s.client(task.clientId)?.displayName : null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => editTask(context, task: task),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Checkbox(value: task.done, onChanged: (_) => toggleTask(s, task)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                      color: task.done ? c.muted : null,
                    ),
                  ),
                  Text(
                    [?who, if (task.due != null) Day.short(task.due!)].join(' · ').isEmpty
                        ? tr('Allgemein', 'General')
                        : [?who, if (task.due != null) Day.short(task.due!)].join(' · '),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!task.done && task.due != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (u.color ?? c.track).withValues(alpha: u.color == null ? 1 : 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: u.color == null ? null : Border.all(color: u.color!.withValues(alpha: 0.7)),
                ),
                child: Text(
                  u.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: u.color ?? c.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Alle Aufgaben (offen oder erledigt).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final list = _done
        ? (s.tasks.where((t) => t.done).toList()..sort((a, b) => (b.doneAt ?? b.updatedAt).compareTo(a.doneAt ?? a.updatedAt)))
        : s.openTasks;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Aufgaben', 'Tasks'))),
      floatingActionButton: GradientFab(label: tr('Aufgabe', 'Task'), icon: Icons.add, onPressed: () => editTask(context)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Offen', 'Open'))),
                  ButtonSegment(value: true, label: Text(tr('Erledigt', 'Done'))),
                ],
                selected: {_done},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _done = v.first),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                EmptyState(
                  icon: Icons.task_alt,
                  title: _done ? tr('Noch nichts erledigt', 'Nothing done yet') : tr('Keine offenen Aufgaben', 'No open tasks'),
                  text: tr(
                    'Aufgaben mit Frist bekommen eine Farbe, je näher die Frist rückt. Conti erinnert dich auch mit einer Mitteilung.',
                    'Tasks with a deadline change colour as it gets closer. Conti also reminds you with a notification.',
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [for (final t in list) TaskTile(task: t)]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
