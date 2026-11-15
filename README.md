# 甬轨通

宁波地铁综合出行助手。纯 Flutter 客户端，无登录、支付或后端，不使用官方 Logo。

## 运行

Flutter stable（开发环境 3.50.0 / Dart 3.14），Android / iOS / Web 工程。

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Android 需安装 Android SDK 与 JDK 17+；iOS 需 Xcode 与相应模拟器运行时。无需 API Key。

## 架构

- Material 3、甬城蓝种子主题、Riverpod Notifier / AsyncNotifier。
- go_router 路由；UI → provider → repository → Dio，不从 Widget 发请求。
- SharedPreferences 持久化目录缓存、收藏与设置；不保存个人身份信息。
- API 缓存先读后更新；目录有效期 24 小时；到站仅驻留内存。
- 到站请求按站点去重并限制至少间隔 60 秒；应用后台暂停轮询，回前台刷新（仍遵守最小间隔）。失败保留旧数据。
- Flutter 3.50 使用已拆分的 `material_ui` Material 3 包，动态取色依赖使用兼容的 2.x 版本。

## 示意线网

`assets/data/network.json` 包含九条线路、179 个经真实 Dict 解析的站点 ID，坐标为人工示意布局，不是经纬度；站序来自真实 StationList 的 Rank。运行时站名、拼音、编码和线路隶属以 API 目录为准，不把静态几何当作运营信息。

线网支持拖动、缩放、线路筛选、站点点击与复位；放大后显示站名。大屏显示 NavigationRail，地图和站点列表并列，站点详情信息和到站看板双栏。所有时刻仍通过真实 API 获取。


## 数据接口

唯一网络数据源：`https://metroinfo.ditiego.net`，仅调用以下三个 GET：

| 接口 | 用途 |
| --- | --- |
| `/Api/Stations/StationList` | 官方站名、拼音、编码和站序 |
| `/Api/Stations/Dict` | 二次 JSON 解码，将编码解析为整数 StationId |
| `/Api/Stations/ScheduleTime/{StationId}` | 每条线路的两个方向到站数据 |

换乘站按 Dict 合并；`0110` / `0242` 对应同一个站，不能直接拿编码请求到站。

以 `IntimeStr` 为权威时刻，按 UTC+8 与当前时间计算倒计时；`IntimeDura <= 0` 视为无车，绝不展示哨兵为到站。未公开的 StationStatus / IsShow 不作为运营状态枚举。方向 Flag 的终点对应关系未公开，因此展示“方向 1 / 2”，不猜测方向。

网络超时 10 秒，失败最多重试 2 次，指数退避；错误和空数据有明确反馈。

详细接口记录：[`docs/ningbo-metro-arrival-api.md`](docs/ningbo-metro-arrival-api.md)。

## 限制与免责声明

这是独立开发的非官方客户端；接口未公开承诺稳定性，数据可能滞后、停运或不可用。到站数据仅供参考，以车站现场信息为准。没有可靠数据来源的票价、首末班、出入口、设施与附近站点均不展示。动态取色依赖系统支持；不支持时使用品牌配色。未采集定位，不包含埋点或在线字体。
