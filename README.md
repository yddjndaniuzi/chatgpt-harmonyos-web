# ChatGPT Web for HarmonyOS

基于 **ArkUI + ArkWeb** 的非官方鸿蒙 ChatGPT 网页套壳客户端实验，当前版本 **0.2.18**。

原生侧栏、顶栏和输入区承载常用操作，登录与会话内容由 ChatGPT 官网提供。它是网页混合客户端，依赖官网页面结构和账号能力，并非完整原生实现，也不是 OpenAI 官方应用。

## 功能

- 原生会话侧栏、最近会话列表与本地标题搜索，适配小尺寸外屏滚动。
- 聊天／工作切换、模型选择和思考等级入口；选项读取当前账号可用的网页控件，不内置模型清单。
- Dot 入口使用官网实际导航；Dot 页面不显示思考等级。
- 历史会话与 Dot 切换时显示加载提示，待内容及控件稳定后淡出。
- 原生输入区对接网页的发送、停止及附件操作；支持系统文件选择和下载保存。
- 登录弹窗、Cookie 持久化、返回操作、网络错误提示与连接诊断。

## 构建

使用 DevEco Studio 打开项目并安装对应 HarmonyOS SDK。当前工程配置：Stage 模型、兼容 API 20、目标 API 26，构建模型版本 6.1.0。

仓库使用示例包名 `com.example.chatgptweb`。安装到设备前，请在 `AppScope/app.json5` 改成自己的包名，并在本机完成签名配置；证书和授权文件不要提交。

macOS 可直接执行：

```sh
zsh build.sh
```

DevEco Studio 不在默认位置时，可通过 `DEVECO_APP` 指定应用路径。其他平台使用 DevEco Studio 内的构建入口。

未签名产物：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

仓库不提供个人签名的安装包、证书或设备授权材料。

## 回归测试

测试使用 Node.js 18 或更新版本，在模拟 DOM 和 ArkWeb 控制器中执行实际桥接代码，不需要账号、手机或登录凭据。

```sh
npm ci --ignore-scripts
npm test
```

覆盖认证隔离、异步历史列表、导航竞态、模型与思考等级区分、加载就绪判断、旧回调失效和加载超时出口。通过这些测试不代表所有线上网页交互均已通过真机验收。

## 主要源码

| 文件 | 作用 |
| --- | --- |
| `entry/src/main/ets/pages/Index.ets` | 原生布局、导航状态、过渡效果、文件处理与错误提示 |
| `entry/src/main/ets/pages/WebBridge.ets` | 公开 DOM 中的历史、输入区与 Dot 导航适配 |
| `entry/src/main/ets/pages/ControlsBridge.ets` | 模式、模型与思考等级控件适配 |
| `tests/auth-lifecycle.cjs` | 桥接与生命周期回归检查 |

## 当前验证与限制

0.2.18 源版本已在 Pura X 验证历史会话、Dot 及往返切换的加载提示自动退出；小外屏侧栏滚动已验证。发布目录使用示例包名，需要自行签名安装。

官网改版可能影响控件识别。模型名称、选项和思考等级显示仍有兼容性边界，选择后的持久状态、文件上传下载、发送和停止需要按实际账号继续验证。未实现麦克风、摄像头、系统推送和后台保活。系统浏览器与应用不会自动共享登录态。

适配器不读取 Cookie 值、令牌或调用私有接口；登录状态由 ArkWeb 管理。发布时的脱敏范围见 [PRIVACY.md](PRIVACY.md)。名称和图标说明见 [NOTICE.md](NOTICE.md)。
