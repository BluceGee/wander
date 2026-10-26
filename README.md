# XNL 工具箱

一款 Android 多功能工具箱 APP（Flutter），集成备忘录、记账、小游戏等日常功能，数据全部保存在本机。

## 功能

| 模块 | 说明 |
| --- | --- |
| 🤖 AI 助手 | 内置 agent 框架：自然语言记账、查账单、管理备忘录（需配置 LLM 接口） |
| 🏠 首页 | 功能入口 + 本月收支、备忘录数量速览 |
| 📝 备忘录 | 新建 / 编辑 / 删除 / 置顶，长按删除 |
| 💰 记账 | 支出 / 收入录入，分类统计，按月查看流水，左滑删除 |
| 🎮 小游戏 | 井字棋（AI 对手，极小化极大算法）、猜数字 |
| ⚙️ 设置 | 浅色 / 深色 / 跟随系统，LLM 接口配置，清空数据 |

## 开发环境

- Flutter 3.47.8（stable）
- Dart 3.13.7
- minSdk 24，目标 Android（小米 / Redmi 等机型均可安装）

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

## AI 助手（内置 agent 框架）

框架是**供应商无关**的：`LlmClient` 接口 + 可插拔适配层。当前内置
`OpenAiCompatClient`，接任何 OpenAI 兼容端点（MiMo 平台等）；模型需要支持
function calling（`tools` / `tool_calls`）。

```
lib/core/agent/           框架核心（与业务解耦）
├── llm_types.dart        ChatMessage / ToolSpec / ToolCall / ToolResult
├── llm_client.dart       LlmClient 接口 + LlmConfig
├── openai_compat_client.dart  OpenAI 兼容适配层（MiMo 等）
├── agent_tool.dart       AgentTool + ToolRegistry（执行失败转 is_error 回传）
└── agent_service.dart    agent 循环：模型 → 工具 → 回传 → 最终回复
lib/features/assistant/   应用层
├── app_tools.dart        内置工具（备忘录 CRUD、记账、查账/月报）
├── assistant_store.dart  会话状态 + 系统提示词
└── assistant_page.dart   对话界面（工具调用可视化、写操作二次确认）
```

要点：

- **工具循环**：模型发起 `tool_calls` → 本地执行 → 结果以 `tool` 消息回传 → 继续，
  直到模型给出最终文本；`maxRounds` 防失控。
- **写操作确认**：`ToolSpec.requiresConfirmation` 的工具（记一笔、建/删备忘录）
  弹窗经用户确认才执行，拒绝会以 `is_error` 告知模型。
- **口语日期**：记账工具接受「今天 / 昨天 / 3号 / 上周三 / 10月1日」等说法，
  在本机归一为具体日期并回显，识别不了会报错请用户澄清，不瞎猜。
- **密钥安全**：API Key 存 Android Keystore 加密存储（`flutter_secure_storage`），
  不落明文 `SharedPreferences`、不进 APK、不参与系统备份（`allowBackup=false`）；
  旧版明文键首次启动自动迁移并清除。正式对外分发应改为后端代理转发。
- **扩展**：新增工具往 `buildAppTools` 里加 `AgentTool`；换供应商只需新增一个
  `LlmClient` 实现（例如将来接自建 ZeroClaw 网关）。

配置入口：`设置 → AI 助手 → LLM 接口配置`（API 地址 / 模型名 / API Key）。

## 项目结构

```
lib/
├── main.dart                 # 入口
├── app.dart                  # MaterialApp / 主题
├── core/
│   ├── agent/                # AI agent 框架（LLM 适配层 + 工具循环）
│   ├── models/               # Memo、ExpenseRecord 数据模型
│   ├── storage/              # 全局状态 + JSON 持久化；KeyVault（API Key 加密存储）
│   ├── theme/                # Material 3 主题
│   └── utils/                # 日期/金额格式化、口语日期归一
└── features/
    ├── home/                 # 首页
    ├── assistant/            # AI 助手（对话 UI + 内置工具）
    ├── memo/                 # 备忘录
    ├── expense/              # 记账
    ├── games/                # 游戏大厅、井字棋、猜数字
    └── settings/             # 设置、LLM 接口配置
```

## 技术说明

- 状态管理：`ChangeNotifier` + `ListenableBuilder`（无第三方状态库）
- 本地存储：`shared_preferences` + JSON，纯本机、不联网
- 密钥存储：`flutter_secure_storage`（Android Keystore 加密）
- UI：Material 3，支持深色模式

## 后续路线（调研结论，未纳入当前版本）

- **本地规则意图路由**：「记一笔午饭 25」这类高频短指令走纯 Dart 规则直接执行
  （零成本、离线、确定性），长尾复杂问题再走 LLM——本 APP 工具面窄而固定，收益明显
- **端侧小模型**：`LlmClient` 接口后可挂本地实现（如 llamadart + Qwen3-0.6B/1.7B），
  完全离线零成本；需按机型 RAM 选型，注意发热降频与 4GB 机 OOM
- **薄代理分发**：正式对外分发时上后端代理（持 key、限流、日预算熔断），
  客户端只带 app token——APK 内永远无秘密
- **撤销栈 / 软删除**：写操作先快照可回滚，删除 30 天可恢复
