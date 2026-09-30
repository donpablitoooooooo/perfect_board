## 0.2.1

- Accepts the latest `go_router` (18), `cached_network_image` (4) and
  `file_saver` (0.6) while still working with the previous majors.
- `cached_network_image` needs at least 3.4.1 (3.2.0 no longer builds with
  current Flutter).
- Shorter package description.

## 0.2.0

- **Demo mode**: `PerfectBoard.configure(demo: ...)`. Each demo user (in
  the example: an anonymous sign-in) gets a private board: its cards carry
  `sandbox` = its uid and it sees only those. Its files (attachments and
  screenshots) stay in memory, in the browser, thumbnails and previews
  included. The rules enforce both.
- Optional `demoCleanup` Cloud Function (off by default, see
  `functions/index.js`): every night removes demo boards older than a day
  and stale anonymous users.
- The example has a *Try the demo* button that starts
  a private board with a few sample cards.

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
