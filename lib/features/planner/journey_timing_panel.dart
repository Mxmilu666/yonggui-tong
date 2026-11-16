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

/// "Leave now" timeline: next departure at the origin, catchability of every
/// transfer, and the estimated arrival. Polls only the origin and transfer stations.
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
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    String name(int id) => catalog.stationById(id)!.name;
    String direction(int line, int? flag) => flag == null ? '$line号线'
      : '$line号线 ${DirectionResolver.label(lineId: line, flag: flag, catalog: catalog)}';
    String clock(DateTime at) => TimeUtils.formatBeijing(at);
    String about(DateTime at) => '约 ${TimeUtils.formatBeijing(at, pattern: 'HH:mm')}';

    final origin = name(plan.originId);
    final rows = <Widget>[
      switch (timing.status) {
        BoardStatus.pending => _Row(icon: Icons.trip_origin, title: '正在获取$origin的发车时刻…'),
        BoardStatus.noService => _Row(icon: Icons.bedtime_outlined,
          title: '$origin当前时段暂无${direction(timing.lineId, timing.flag)}班次'),
        BoardStatus.boarded => _Row(icon: Icons.trip_origin,
          title: '$origin ${clock(timing.board!.at)} 开',
          subtitle: '${direction(timing.lineId, timing.flag)} · 下一班'),
      },
      for (final transfer in timing.transfers) _TransferRow(
        transfer: transfer,
        station: name(transfer.stationId),
        onward: direction(transfer.toLine, transfer.toFlag),
        arrive: about(transfer.arriveAt),
        clock: clock,
      ),
      if (timing.arriveAt case final arrival?)
        _Row(icon: Icons.place_outlined, title: '${about(arrival)} 到达${name(plan.destinationId)}'),
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
        Text('发车与接续班次取自车站时刻表；乘车按每站约 2 分钟估算，不含步行与延误。',
          style: text.labelSmall?.copyWith(color: muted)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.foreground});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = foreground ?? Theme.of(context).colorScheme.onSurface;
    final muted = foreground ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: muted)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: text.bodyMedium?.copyWith(color: color, fontFeatures: _tabular)),
        if (subtitle != null) Text(subtitle!, style: text.bodySmall?.copyWith(color: muted, fontFeatures: _tabular)),
      ])),
    ]);
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.transfer, required this.station, required this.onward,
    required this.arrive, required this.clock});
  final TransferTiming transfer;
  final String station;
  final String onward;
  final String arrive;
  final String Function(DateTime) clock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final arrival = '$arrive 到$station';
    final row = switch (transfer.status) {
      TransferStatus.pending => _Row(icon: Icons.transfer_within_a_station,
        title: arrival, subtitle: '正在获取$station的换乘班次…'),
      TransferStatus.noService => _Row(icon: Icons.transfer_within_a_station,
        title: arrival, subtitle: '$station当前时段暂无$onward班次'),
      TransferStatus.beyondSchedule => _Row(icon: Icons.schedule,
        title: arrival,
        subtitle: '$station时刻表目前只到 ${clock(transfer.lastKnown!)}，临近时自动更新能否赶上'),
      TransferStatus.connected => _Row(
        icon: transfer.tight ? Icons.directions_run : Icons.transfer_within_a_station,
        foreground: transfer.tight ? colors.onTertiaryContainer : null,
        title: transfer.tight ? '换乘紧张：仅 ${_minutes(transfer.gap!)}' : '来得及：候车约 ${_minutes(transfer.gap!)}',
        subtitle: '$arrival，换乘 $onward ${clock(transfer.depart!.at)} 开'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: transfer.tight ? colors.tertiaryContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: row,
    );
  }

  static String _minutes(Duration gap) => gap.inMinutes < 1 ? '不足 1 分钟' : '${gap.inMinutes} 分钟';
}
