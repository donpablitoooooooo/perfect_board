import 'package:go_router/go_router.dart';
import 'package:perfect_board/src/config.dart';
import 'package:perfect_board/src/pages/ticket_detail.dart';
import 'package:perfect_board/src/pages/ticket_new.dart';
import 'package:perfect_board/src/pages/tickets_page.dart';

/// Le rotte della board, da mettere fra quelle del `GoRouter` dell'app
/// (anche dentro una `ShellRoute`): la board, `new` e `detail/:id` sotto
/// [PerfectBoard.basePath].
List<RouteBase> perfectBoardRoutes() => [
      GoRoute(
        path: PerfectBoard.basePath,
        builder: (_, __) => const TicketsPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, __) => const TicketNewPage()),
          GoRoute(
            path: 'detail/:id',
            builder: (_, state) =>
                TicketDetailPage(ticketId: state.pathParameters['id']),
          ),
        ],
      ),
    ];
