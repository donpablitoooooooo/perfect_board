/// Una board kanban per segnalazioni di lavoro, su Firebase.
library;

export 'src/config.dart';
export 'src/models/ticket.dart';
export 'src/pages/ticket_detail.dart' show TicketDetailPage;
export 'src/pages/ticket_new.dart' show TicketNewPage;
export 'src/pages/tickets_page.dart' show TicketsPage;
export 'src/routes.dart';
export 'src/theme.dart' show BoardTheme, BoardColors, BoardColorsContext;
export 'src/widgets/ticket_screenshot.dart'
    show TicketScreenshot, TicketScreenshotHost, TicketScreenshotTarget;
