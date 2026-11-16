# 甬轨通

宁波地铁综合出行助手。纯 Flutter 客户端，无登录、支付或后端，不使用官方 Logo。

应用图标是自绘的“甬”字轨道图形：顶部是串在黄色线路上的站点环，“用”画成两条钢轨加枕木。源文件为 `assets/brand.svg`；Android 自适应图标是对应的矢量 `ic_yonggui_foreground.xml`，其余 PNG（Android 旧版、iOS、Web、关于页的 `assets/brand.png`）用 `tool/render_icons.sh`（macOS，需 Chrome）重新生成。

## 运行

Flutter stable（开发环境 3.50.0 / Dart 3.14），Android / iOS / Web 工程。

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

真实 API 的 Android 集成场景（需要网络，包含一次 60 秒实际轮询）：

```sh
flutter test integration_test/core_flow_test.dart -d emulator-5554
```

普通 `flutter test` 完全离线，使用从三个接口保存的真实裁剪响应，不会请求服务。生产运行不使用 fixture。

Android 需安装 Android SDK 与 JDK 17+；iOS 需 Xcode 与相应模拟器运行时。无需 API Key。

## 架构

- Material 3、甬城蓝种子主题、Riverpod Notifier / AsyncNotifier。
- go_router 路由；UI → provider → repository → Dio，不从 Widget 发请求。
- SharedPreferences 持久化目录缓存、收藏与设置；不保存个人身份信息。
- API 缓存先读后更新；目录有效期 24 小时；到站仅驻留内存。
- 到站请求按站点去重并限制至少间隔 60 秒；应用后台暂停轮询，回前台刷新（仍遵守最小间隔）。失败保留旧数据。
- Flutter 3.50 使用已拆分的 `material_ui` Material 3 包，动态取色依赖使用兼容的 2.x 版本。
- 中文字体随 App 打包（Noto Sans SC，SIL OFL 1.1），运行时不下载在线字体。许可位于 `assets/fonts/OFL.txt`，App「关于 → 开源许可」可查看。

## 示意线网

`assets/data/network.json` 包含九条线路、179 个经真实 Dict 解析的站点 ID，坐标为人工示意布局，不是经纬度；站序来自真实 StationList 的 Rank。运行时站名、拼音、编码和线路隶属以 API 目录为准，不把静态几何当作运营信息。

线网支持拖动、缩放、线路筛选、站点点击与复位；放大后显示站名。大屏显示 NavigationRail，地图和站点列表并列，站点详情信息和到站看板双栏。所有时刻仍通过真实 API 获取。

## 行程估算

`RoutePlanner` 使用 `(StationId, LineId)` 状态建图、`collection.HeapPriorityQueue` 执行 Dijkstra。相邻站边权 2 分钟，换乘 4 分钟；起点选择线路不收费，同站行程 0 分钟。同权重优先更少换乘，返回分段站序、换乘站、乘坐站数及预计分钟。

所有结果明确标注“估算，不含候车/延误”。路线选择不参与实时到站运算，不提供票价，不保证线路实际可乘；接口目录中标有暂不开通的站仍按原名显示。静态线网缺少或目录已移除的节点不创建虚构捷径。拓扑更新需要同步维护 asset。

行程结果可收藏，收藏路线显示在首页，点击回到对应起终点的估算页。收藏卡片和估算页的“现在出发”直接回答换乘要不要赶：取起点在行进方向（按站序与已核对的方向终点确定 Flag）的下一班 `OutTimeStr` 出发，乘车按每站约 2 分钟估算，并对齐到换乘站同向来车中最接近的一班（相差 3 分钟内）；再取去线同向、在到站之后的第一班发车。间隔 ≥5 分钟显示“不用赶”，2–5 分钟“需要赶”，不足 2 分钟“可能赶不上”并给出错过后的下一班。接口每个方向只公布接下来约两班，更晚的班次按这两班的间隔推算，推算时刻前加“约”；只有一班可参照时不推算，显示暂时无法判断。乘车时长是估算，不含步行与延误。

## 测试与截图

测试覆盖 Dict 二次解析、鼓楼换乘合并、3/12 号线 Rank 顺序、北京时间和跨午夜倒计时、-60 哨兵、失败重试/去重/限流、缓存和持久化、线网拓扑、地图交互、Dijkstra、现在出发的换乘推算（方向选取、超出已公布班次不外推）、收藏路线跳转、320dp 搜索和深色行程估算、大字号免责声明。Android 集成场景使用真实网络验证搜索、方向块、收藏、60 秒轮询、地图与设置。

关键页面截图在 [`screenshots/`](screenshots/)；截图中的空班次为当时真实 API 状态，不是演示数据。iOS 工程已配置，但本次运行验收以 Android 为准。
- 开发验收：`flutter analyze` 零问题；`flutter test` 33 个测试通过；Android 真实 API 集成场景通过（含实际等待一次 60 秒轮询）；`flutter run -d emulator-5554` 已启动。
- 目视检查：Android 首页/到站/线网、Web 320dp 深色线网和行程、大屏 NavigationRail + 双栏。
- 本机已安装 Flutter stable 到 `~/.local/share/flutter/stable`，`~/.local/bin/flutter` / `dart` 可直接使用；工程不依赖此绝对路径。
- Android release 配置使用开发签名，便于本地运行；尚未配置应用商店分发签名。iOS 未进行模拟器或真机验收。



## 数据接口

唯一网络数据源：`https://metroinfo.ditiego.net`，仅调用以下三个 GET：

| 接口 | 用途 |
| --- | --- |
| `/Api/Stations/StationList` | 官方站名、拼音、编码和站序 |
| `/Api/Stations/Dict` | 二次 JSON 解码，将编码解析为整数 StationId |
| `/Api/Stations/ScheduleTime/{StationId}` | 每条线路的两个方向到站数据 |

换乘站按 Dict 合并；`0110` / `0242` 对应同一个站，不能直接拿编码请求到站。

以 `IntimeStr` 为权威时刻，按 UTC+8 与当前时间计算倒计时；`IntimeDura <= 0` 视为无车，绝不展示哨兵为到站。未公开的 StationStatus / IsShow 不作为运营状态枚举。

方向显示“往 ××”。`DirectionResolver` 内置已核对的 `LineId + Flag → 终点编码` 关系，编码仍经 Dict 找到当前目录中的官方站名，不把编码当到站 ID。核对来源为官方服务号使用的站点资料（2026-11-16）：[鼓楼](https://metroinfo.ditiego.net/Api/Stations/16)、[鄞州区政府](https://metroinfo.ditiego.net/Api/Stations/88)、[小洋江](https://metroinfo.ditiego.net/Api/Stations/134)、[市中医院](https://metroinfo.ditiego.net/Api/Stations/170)，对应字段 `StationTimes.LineId / Flag / EndStationName`。这些仅在开发时核对，生产 App 不增加接口请求；裁剪依据位于 `test/fixtures/directions.json`。线路方向为本地参考资料，不推断短线车实际终到；缺少映射或目录不一致时提示“终点待确认”。

网络超时 10 秒，失败最多重试 2 次，指数退避；错误和空数据有明确反馈。

详细接口记录：[`docs/ningbo-metro-arrival-api.md`](docs/ningbo-metro-arrival-api.md)。

## 限制与免责声明

这是独立开发的非官方客户端；接口未公开承诺稳定性，数据可能滞后、停运或不可用。到站数据仅供参考，以车站现场信息为准。没有可靠数据来源的票价、首末班、出入口、设施与附近站点均不展示。动态取色依赖系统支持；不支持时使用品牌配色。未采集定位，不包含埋点或在线字体。
