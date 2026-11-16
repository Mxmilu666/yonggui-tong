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

/// Entry-point search field; the actual query runs in [StationSearchSheet].
class StationSearchBar extends StatelessWidget {
  const StationSearchBar({super.key, required this.onTap, this.hintText = '搜索站名、拼音、编码或线路'});

  final VoidCallback onTap;
  final String hintText;

  @override
  Widget build(BuildContext context) => SearchBar(
    hintText: hintText,
    leading: const Icon(Icons.search),
    onTap: () {
      FocusManager.instance.primaryFocus?.unfocus();
      onTap();
    },
  );
}

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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
              controller: _controller,
              autoFocus: true,
              hintText: '站名、拼音、编码或线路',
              leading: IconButton(tooltip: '关闭搜索', onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back)),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
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
          const SizedBox(height: 8),
          if (catalog.isLoading) const LinearProgressIndicator(),
          Expanded(child: data == null
            ? catalog.hasError
              ? SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: ErrorState(message: '${catalog.error}', onRetry: () { ref.read(catalogProvider.notifier).refresh(); })))
              : const Center(child: CircularProgressIndicator(semanticsLabel: '正在载入车站目录'))
            : matches.isEmpty
              ? const SingleChildScrollView(child: EmptyState(title: '没有找到车站', message: '试试中文站名、全拼或四位站点编码。', icon: Icons.search_off))
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final station = matches[index];
                    return ListTile(
                      title: Text(station.name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [for (final line in station.lineIds) LineBadge(lineId: line, small: true)]),
                      ),
                      trailing: favorites.contains(station.id)
                        ? Icon(Icons.star_rounded, semanticLabel: '已收藏', color: Theme.of(context).colorScheme.primary)
                        : null,
                      onTap: () => Navigator.of(context).pop(station),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}
