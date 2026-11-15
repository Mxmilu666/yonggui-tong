import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() action, {String? success}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted && success != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('清除车站缓存？'),
      content: const Text('将清除本地车站目录，下次读取时重新联网获取。收藏和偏好设置会保留。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('清除')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    await _save(() async {
      await ref.read(metroRepositoryProvider).clearCatalogCache();
      ref.invalidate(catalogProvider);
    }, success: '车站目录缓存已清除');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final favoriteCount = ref.watch(favoritesProvider).length;
    return Scaffold(
      appBar: AppBar(title: const Text('我的与设置')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.bookmarks_outlined, size: 32, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(height: 16),
                Text('把常用站留在手边', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                const SizedBox(height: 8),
                Text('已收藏 $favoriteCount 个车站 · 仅保存在本机', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(onPressed: () => context.go('/arrivals'), icon: const Icon(Icons.star_outline_rounded), label: const Text('查看收藏车站')),
              ]),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('外观'),
            Card(margin: EdgeInsets.zero, child: Column(children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题模式'),
                subtitle: Text(switch (settings.themeMode) { ThemeMode.system => '跟随系统', ThemeMode.light => '浅色', ThemeMode.dark => '深色' }),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_saving,
                onTap: () async {
                  final mode = await showModalBottomSheet<ThemeMode>(context: context, showDragHandle: true, useSafeArea: true, builder: (context) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final option in ThemeMode.values) ListTile(
                        title: Text(switch (option) { ThemeMode.system => '跟随系统', ThemeMode.light => '浅色', ThemeMode.dark => '深色' }),
                        trailing: option == settings.themeMode ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.of(context).pop(option),
                      ),
                    ]),
                  ));
                  if (mode != null && mounted) await _save(() => ref.read(settingsProvider.notifier).setThemeMode(mode));
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                secondary: const Icon(Icons.color_lens_outlined),
                title: const Text('动态取色'),
                subtitle: const Text('在支持的设备上使用系统配色'),
                value: settings.dynamicColor,
                onChanged: _saving ? null : (value) => _save(() => ref.read(settingsProvider.notifier).setDynamicColor(value)),
              ),
            ])),
            const SizedBox(height: 24),
            const _SectionTitle('数据与刷新'),
            Card(margin: EdgeInsets.zero, child: Column(children: [
              ListTile(
                leading: const Icon(Icons.update_rounded),
                title: const Text('到站自动刷新'),
                subtitle: Text('每 ${settings.refreshSeconds} 秒 · 退到后台时暂停'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_saving,
                onTap: () async {
                  final seconds = await showModalBottomSheet<int>(context: context, showDragHandle: true, useSafeArea: true, builder: (context) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final interval in [60, 120]) ListTile(
                        title: Text('每 $interval 秒'),
                        trailing: settings.refreshSeconds == interval ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.of(context).pop(interval),
                      ),
                    ]),
                  ));
                  if (seconds != null && mounted) await _save(() => ref.read(settingsProvider.notifier).setRefreshSeconds(seconds));
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清除车站缓存'),
                subtitle: const Text('不影响收藏与设置'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_saving,
                onTap: _clearCache,
              ),
            ])),
            if (_saving) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(semanticsLabel: '正在保存设置')),
            const SizedBox(height: 24),
            const _SectionTitle('关于'),
            Card(margin: EdgeInsets.zero, child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于甬轨通'),
              subtitle: const Text('版本 1.0.0 · 数据来源与免责声明'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
            )),
          ],
        ),
      )),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于甬轨通')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.route_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('甬轨通', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('宁波地铁出行助手 · 1.0.0', textAlign: TextAlign.center),
        const SizedBox(height: 32),
        const _AboutSection(title: '独立出行工具', body: '甬轨通是非官方应用，与宁波轨道交通运营方无隶属或合作关系。应用标识为独立设计的抽象轨道图形，不是官方标识。'),
        const _AboutSection(title: '真实数据来源', body: '车站目录、站点 ID 与到站时刻来自宁波地铁官方 Android App 后端的未公开接口。接口主机：https://metroinfo.ditiego.net。无需账号，不提供支付服务。'),
        const _AboutSection(title: '时刻与方向说明', body: '到站时刻按运行图提供，统一为北京时间（UTC+8），不保证反映实时延误。倒计时由接口到站时刻计算；无效与占位班次不会作为列车展示。方向 1/2 是接口编号，暂不推断终点名称。暂无有效班次不能据此判断线路已停运。'),
        const _AboutSection(title: '线网与行程估算', body: '线网图为示意图，不按地理比例绘制。行程时长为相邻站 2 分钟、换乘 4 分钟的本地估算，不含候车、步行及延误，不是实际列车运行时长。本应用不提供未经接口证实的票价、出入口、设施或首末班信息。'),
        const _AboutSection(title: '使用提示', body: '未公开接口可能变化或暂时不可用。到站与估算信息仅供参考，请以车站公告、现场显示及运营方发布为准。收藏与偏好设置仅保存在本机；清除目录缓存不会移除收藏。'),
        const _AboutSection(title: '接口文档', body: '仓库文档路径：\ndocs/ningbo-metro-arrival-api.md\n\n来源说明：com.nbmetro.smartmetro v5.3.14；接口文档实测日期 2026-11-16。'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => showLicensePage(context: context,
            applicationName: '甬轨通', applicationVersion: '1.0.0'),
          icon: const Icon(Icons.description_outlined), label: const Text('开源许可')),
      ]),
    )),
  );
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SelectableText(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7)),
    ]),
  );
}
