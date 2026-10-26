# XNL 工具箱

一款 Android 多功能工具箱 APP（Flutter），集成备忘录、记账、小游戏等日常功能，数据全部保存在本机。

## 功能

| 模块 | 说明 |
| --- | --- |
| 🏠 首页 | 功能入口 + 本月收支、备忘录数量速览 |
| 📝 备忘录 | 新建 / 编辑 / 删除 / 置顶，长按删除 |
| 💰 记账 | 支出 / 收入录入，分类统计，按月查看流水，左滑删除 |
| 🎮 小游戏 | 井字棋（AI 对手，极小化极大算法）、猜数字 |
| ⚙️ 设置 | 浅色 / 深色 / 跟随系统，清空数据 |

## 开发环境

- Flutter 3.47.8（stable）
- Dart 3.13.7
- minSdk 21，目标 Android（小米 / Redmi 等机型均可安装）

## 快速开始

```bash
flutter pub get      # 安装依赖
flutter test         # 运行测试
flutter run          # 连接手机 / 模拟器直接运行
```

## 打包 APK（安装到小米手机）

```bash
# 发布版 APK（带混淆，体积更小）
flutter build apk --release

# 产物位置
# build/app/outputs/flutter-apk/app-release.apk
```

安装到手机：

1. **USB 调试**：手机「设置 → 我的设备 → 全部参数」连点 MIUI 版本开启开发者选项，再进入「设置 → 更多设置 → 开发者选项」打开 **USB 调试**，用数据线连接电脑后允许调试授权；
2. `flutter run` 直接安装运行，或把 `app-release.apk` 发送到手机点击安装；
3. 若提示「禁止安装」，在安装弹窗里点「允许本次安装」，或到「设置 → 更多设置 → 开发者选项」关闭 **MIUI 优化**（部分机型需要）。

## 项目结构

```
lib/
├── main.dart                 # 入口
├── app.dart                  # MaterialApp / 主题
├── core/
│   ├── models/               # Memo、ExpenseRecord 数据模型
│   ├── storage/app_store.dart# 全局状态 + SharedPreferences JSON 持久化
│   ├── theme/                # Material 3 主题
│   └── utils/format.dart     # 日期 / 金额格式化
└── features/
    ├── home/                 # 首页
    ├── memo/                 # 备忘录
    ├── expense/              # 记账
    ├── games/                # 游戏大厅、井字棋、猜数字
    └── settings/             # 设置
```

## 技术说明

- 状态管理：`ChangeNotifier` + `ListenableBuilder`（无第三方状态库）
- 本地存储：`shared_preferences` + JSON，纯本机、不联网
- UI：Material 3，支持深色模式
