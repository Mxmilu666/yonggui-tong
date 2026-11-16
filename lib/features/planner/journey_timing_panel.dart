import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/arrival.dart';
import '../../core/models/route_plan.dart';
import '../../core/models/station.dart';
import '../../core/utils/direction_resolver.dart';
import '../../core/utils/journey_timing.dart';
import '../../core/utils/time_utils.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

String _about(DateTime at) => '约 ${TimeUtils.formatBeijing(at, pattern: 'HH:mm')}';
String _slot(Slot slot) => slot.projected ? _about(slot.at) : TimeUtils.formatBeijing(slot.at);

/// "Leave now": next departure at the origin, whether each transfer needs a hurry,
/// and the estimated arrival. Polls only the origin and transfer stations.
class JourneyTimingPanel extends ConsumerWidget {
  const JourneyTimingPanel({super.key, required this.plan, required this.catalog});

  final RoutePlan plan;
  final StationCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now().toUtc();
    final stations = {plan.originId, for (final segment in plan.segments.take(plan.segments.length - 1)) segment.stationIds.last};
    final snapshots = <int, ArrivalSnapshot?>{
      for (final id in stations) id: ref.watch(arrivalsProvider(id)).snapshot,
    };
    final timing = journeyTiming(plan: plan, snapshots: snapshots, catalog: catalog, now: now);
    if (timing == null) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    String name(int id) => catalog.stationById(id)!.name;
    String direction(int line, int? flag) => flag == null ? '$line号线'
      : '$line号线 ${DirectionResolver.label(lineId: line, flag: flag, catalog: catalog)}';

    final origin = name(plan.originId);
    final rows = <Widget>[
      switch (timing.status) {
        BoardStatus.pending => _Row(icon: Icons.trip_origin, title: '正在获取$origin的发车时刻…'),
        BoardStatus.noService => _Row(icon: Icons.bedtime_outlined,
          title: '$origin当前时段暂无${direction(timing.lineId, timing.flag)}班次'),
        BoardStatus.boarded => _Row(icon: Icons.trip_origin,
          title: '$origin ${TimeUtils.formatBeijing(timing.board!)} 开',
          subtitle: '${direction(timing.lineId, timing.flag)} · 下一班'),
      },
      for (final transfer in timing.transfers) _TransferVerdict(
        transfer: transfer,
        station: name(transfer.stationId),
        onward: direction(transfer.toLine, transfer.toFlag),
      ),
      if (timing.arriveAt case final arrival?)
        _Row(icon: Icons.place_outlined, title: '${_about(arrival)} 到达${name(plan.destinationId)}'),
    ];
    return Semantics(
      container: true,
      label: '现在出发的时刻推算',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          row,
        ],
        const SizedBox(height: 8),
        Text('始发班次取自车站时刻表；乘车按每站约 2 分钟估算并对齐换乘站到站时刻，接口未公布的后续班次按当前发车间隔推算，不含步行与延误。',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: muted)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
        if (subtitle != null) Text(subtitle!, style: text.bodySmall?.copyWith(color: muted, fontFeatures: _tabular)),
      ])),
    ]);
  }
}

class _TransferVerdict extends StatelessWidget {
  const _TransferVerdict({required this.transfer, required this.station, required this.onward});
  final TransferTiming transfer;
  final String station;
  final String onward;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final arrive = '${_about(transfer.arriveAt)} 到$station';
    final hurry = transfer.status == TransferStatus.connected ? transfer.hurry : null;
    final (background, foreground) = switch (hurry) {
      Hurry.relaxed => (colors.primaryContainer, colors.onPrimaryContainer),
      Hurry.hurry => (colors.tertiaryContainer, colors.onTertiaryContainer),
      Hurry.risky => (colors.errorContainer, colors.onErrorContainer),
      null => (colors.surfaceContainerHigh, colors.onSurfaceVariant),
    };
    final minutes = transfer.gap?.inMinutes ?? 0;
    final slack = minutes < 1 ? '不足 1 分钟' : '约 $minutes 分钟';
    final (IconData icon, String? verdict, String headline, String detail) = switch (transfer.status) {
      TransferStatus.pending => (Icons.transfer_within_a_station, null, arrive, '正在获取$station的换乘班次…'),
      TransferStatus.noService => (Icons.transfer_within_a_station, null, arrive, '$station当前时段暂无$onward班次'),
      TransferStatus.beyondSchedule => (Icons.schedule, null, arrive,
        '$station时刻表只公布到 ${TimeUtils.formatBeijing(transfer.lastKnown!)}，暂时无法判断，临近时自动更新'),
      TransferStatus.connected => switch (hurry!) {
        Hurry.relaxed => (Icons.check_circle_outline, '不用赶', '$station换乘可等$slack', ''),
        Hurry.hurry => (Icons.directions_run, '需要赶', '$station换乘只有$slack', ''),
        Hurry.risky => (Icons.warning_amber_rounded, '可能赶不上', '$station换乘只有$slack', ''),
      },
    };
    final schedule = transfer.depart == null ? detail
      : '$arrive，$onward ${_slot(transfer.depart!)} 开'
        '${hurry == Hurry.risky && transfer.nextDepart != null ? '；错过则下一班 ${_slot(transfer.nextDepart!)}' : ''}';
    return Semantics(
      label: [?verdict, headline, schedule].join('，'),
      child: ExcludeSemantics(child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 22, color: foreground)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (verdict != null) Text(verdict, style: text.titleMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
            Text(headline, style: text.bodyMedium?.copyWith(
              color: verdict != null ? foreground : colors.onSurface, fontFeatures: _tabular)),
            const SizedBox(height: 2),
            Text(schedule, style: text.bodySmall?.copyWith(color: foreground, fontFeatures: _tabular)),
          ])),
        ]),
      )),
    );
  }
}
