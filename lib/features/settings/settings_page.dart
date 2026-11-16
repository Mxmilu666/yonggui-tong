import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/version.dart';
import '../../data/favorite_widget.dart';
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
    final routeCount = ref.watch(favoriteRoutesProvider).length;
    const segmentStyle = ButtonStyle(visualDensity: VisualDensity.standard);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _SectionTitle('收藏'),
            ListTile(
              leading: const Icon(Icons.star_outline_rounded),
              title: const Text('收藏车站'),
              subtitle: Text('$favoriteCount 个 · 仅保存在本机'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/arrivals'),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('收藏路线'),
              subtitle: Text('$routeCount 条 · 显示在首页'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/'),
            ),
            if (ref.watch(widgetPinSupportedProvider).valueOrNull ?? false) ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('添加桌面小组件'),
              subtitle: const Text('在桌面显示收藏车站的下一班'),
              trailing: const Icon(Icons.add),
              onTap: () async {
                final requested = await FavoriteWidget.pin();
                if (!requested && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前桌面不支持直接添加，请在桌面长按空白处，从小组件列表添加「甬轨通」')));
                }
              },
            ),
            const _SectionTitle('外观'),
            const ListTile(leading: Icon(Icons.palette_outlined), title: Text('主题模式')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<ThemeMode>(
                style: segmentStyle,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: _saving ? null
                  : (value) => _save(() => ref.read(settingsProvider.notifier).setThemeMode(value.single)),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.color_lens_outlined),
              title: const Text('动态取色'),
              subtitle: const Text('在支持的设备上使用系统配色'),
              value: settings.dynamicColor,
              onChanged: _saving ? null : (value) => _save(() => ref.read(settingsProvider.notifier).setDynamicColor(value)),
            ),
            const _SectionTitle('数据与刷新'),
            const ListTile(
              leading: Icon(Icons.timer_outlined),
              title: Text('到站倒计时显示'),
              subtitle: Text('应用内显示分钟或分秒（如 02:15），不改变数据刷新频率'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<bool>(
                style: segmentStyle,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('分钟')),
                  ButtonSegment(value: true, label: Text('分秒')),
                ],
                selected: {settings.arrivalSeconds},
                onSelectionChanged: _saving ? null
                  : (value) => _save(() => ref.read(settingsProvider.notifier).setArrivalSeconds(value.single)),
              ),
            ),
            const ListTile(
              leading: Icon(Icons.update_rounded),
              title: Text('到站自动刷新'),
              subtitle: Text('退到后台时暂停，回到前台立即刷新'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<int>(
                style: segmentStyle,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 60, label: Text('每 60 秒')),
                  ButtonSegment(value: 120, label: Text('每 120 秒')),
                ],
                selected: {settings.refreshSeconds},
                onSelectionChanged: _saving ? null
                  : (value) => _save(() => ref.read(settingsProvider.notifier).setRefreshSeconds(value.single)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清除车站缓存'),
              subtitle: const Text('不影响收藏与设置'),
              enabled: !_saving,
              onTap: _clearCache,
            ),
            if (_saving) const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(semanticsLabel: '正在保存设置')),
            const _SectionTitle('关于'),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于甬轨通'),
              subtitle: const Text('版本 $appVersion'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
            ),
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
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleSmall
      ?.copyWith(color: Theme.of(context).colorScheme.primary))),
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
        Center(child: Image.asset('assets/brand.png', width: 72, height: 72, semanticLabel: '甬轨通图标')),
        const SizedBox(height: 16),
        Text('甬轨通', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('宁波地铁出行助手 · $appVersion', textAlign: TextAlign.center),
        const SizedBox(height: 32),
        Card.outlined(child: Column(children: [
          const ListTile(
            leading: Icon(Icons.dataset_outlined),
            title: Text('数据来源'),
            subtitle: Text('数据来自宁波地铁官方'),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('开源许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(context: context,
              applicationName: '甬轨通', applicationVersion: appVersion),
          ),
        ])),
      ]),
    )),
  );
}
