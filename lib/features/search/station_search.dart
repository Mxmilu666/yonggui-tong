import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/station.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/line_badge.dart';
import '../../data/providers.dart';

Future<Station?> showStationSearch(BuildContext context, WidgetRef ref) => showModalBottomSheet<Station>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (_) => const StationSearchSheet(),
);

class StationSearchSheet extends ConsumerStatefulWidget {
  const StationSearchSheet({super.key});

  @override
  ConsumerState<StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends ConsumerState<StationSearchSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final favorites = ref.watch(favoritesProvider);
    final data = catalog.valueOrNull;
    final matches = data?.search(_query) ?? <Station>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
            child: Row(children: [
              Expanded(child: Text('找一个车站', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(tooltip: '关闭搜索', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
              controller: _controller,
              hintText: '站名、拼音、编码或线路',
              leading: const Icon(Icons.search),
              trailing: [if (_query.isNotEmpty) IconButton(tooltip: '清空搜索', onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              }, icon: const Icon(Icons.close))],
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.length == 1) Navigator.of(context).pop(matches.single);
              },
            ),
          ),
          const SizedBox(height: 12),
          if (catalog.isLoading) const LinearProgressIndicator(),
          Expanded(child: data == null
            ? catalog.hasError
              ? SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: ErrorState(message: '${catalog.error}', onRetry: () { ref.read(catalogProvider.notifier).refresh(); })))
              : const Center(child: CircularProgressIndicator(semanticsLabel: '正在载入车站目录'))
            : matches.isEmpty
              ? const SingleChildScrollView(child: EmptyState(title: '没有找到车站', message: '试试中文站名、全拼或四位站点编码。', icon: Icons.search_off))
              : ListView.separated(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final station = matches[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(station.name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [for (final line in station.lineIds) LineBadge(lineId: line, small: true)]),
                      ),
                      trailing: Icon(favorites.contains(station.id) ? Icons.star_rounded : Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(station),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}
