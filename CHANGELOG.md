## 0.2.0

- **Demo accounts**: `PerfectBoard.configure(demo: ...)` and the `demo`
  custom claim (`set_admin.js --demo`). A demo account uses the board but
  its files (attachments and screenshots) stay in memory, in the browser,
  and it cannot delete cards. The rules enforce both.
- The example has a *Try the demo* button when `DEMO_EMAIL` and
  `DEMO_PASSWORD` are defined, and accepts `demo` / `demo` as a shortcut.

## 0.1.0

First release.

- Kanban board (New → Needs info → In progress → Ready for testing →
  Approved, plus Discarded) with drag and drop and time in column.
- Card detail: in-place title and description, labels, due date, checklist,
  links to your app's documents (`BoardRefSource`), attachments with
  preview, comments with attachments.
- Screenshots of the app itself with a movable frame and freehand drawing,
  from a card, from *New card* and from a comment.
- Markdown export (storage paths, never download links with tokens).
- Standard Material 3 components; colors from the app theme, `BoardTheme`
  for the rest.
- Italian and English texts.
- Cloud Functions (counters, cleanup), security rules with tests, CLI
  (`functions/board.js`), `set_admin.js`, Claude Code command.
