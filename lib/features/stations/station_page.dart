import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../arrivals/arrivals_page.dart';

class StationPage extends ConsumerWidget {
  const StationPage({super.key, required this.stationId});
  final int stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(catalogProvider).valueOrNull?.stationById(stationId);
    return Scaffold(
      appBar: AppBar(title: const Text('站点详情')),
      body: station == null
          ? const Center(child: Text('请先加载站点目录，或返回重新选择站点'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(station.name, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(station.pinyin),
                    const SizedBox(height: 8),
                    Text('站点编码 ${station.codes.join(' / ')}'),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final id in station.lineIds)
                        ActionChip(label: Text('$id号线'), onPressed: () => context.push('/lines/$id')),
                    ]),
                    const SizedBox(height: 24),
                    ArrivalBoard(stationId: stationId),
                  ]),
                )),
              ],
            ),
    );
  }
}
