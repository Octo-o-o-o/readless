# Strict Architecture Audit Prompt

## Prompt

```text
你是一个极其严苛、偏保守的 Staff+ 架构审查员。请对当前仓库做一次“以发现问题为优先”的全栈健康审查，不要基于 README、AGENTS、CLAUDE 或计划文档直接相信项目现状，必须以真实代码、真实依赖、真实测试结果和真实命令输出为准。

仓库根目录：/Users/wangyixiao/WorkSpace/readless
审查输出文件：/Users/wangyixiao/WorkSpace/readless/docs/strict-architecture-audit-report-2026-03-11.md

目标：
1. 从最严苛的角度，排查项目在架构合理性、模块边界、依赖方向、并发模型、性能、成本、可恢复性、安全性、稳定性、可扩展性、可测试性、可观测性、文档一致性、AI 可读性、AI 可编辑性，以及你认为值得纳入的其他维度上的真实问题。
2. 把问题保存在一个 Markdown 文件里。
3. 对问题结果再做一次 review，去重、降噪、质疑自己，筛掉低价值或证据不足的项。
4. 只对“真实回报高”的部分生成解决方案，避免产出大而空的重构建议。

执行要求：
- 先建立“真实架构视图”，不要只看说明文档。
- 必须覆盖 backend 和 macOS 两部分。
- 必须优先阅读这些入口或等价关键文件：
  - backend/pyproject.toml
  - backend/app/main.py
  - backend/app/config.py
  - backend/app/database.py
  - backend/app/routers/*.py
  - backend/app/services/*.py
  - backend/app/models/*.py
  - backend/tests/*
  - macos/Package.swift
  - macos/Sources/App/ReadlessApp.swift
  - macos/Sources/App/Services/*
  - macos/Sources/App/ViewModels/*
  - macos/Sources/App/Views/*
  - macos/Sources/Networking/*
  - macos/Sources/Storage/*
  - macos/Sources/AIServices/*
  - macos/Sources/ReaderFeature/*
  - macos/Sources/LibraryFeature/*
- 必须运行必要的验证命令，不允许纯静态想象。至少包含：
  - 后端测试
  - 后端静态检查
  - macOS 端测试
  - 适量的结构命令（如 rg、wc、nl、sed）
- 如果默认命令跑不通，要记录“为什么跑不通”，并在不污染仓库的前提下用最小必要条件继续验证。

评估维度：
- 架构与边界：模块职责是否清晰，是否存在壳模块、伪分层、依赖倒挂、共享可变状态。
- 性能与成本：同步链路是否过长，是否存在多次远程 AI 往返、低效查询、重复工作、冷路径被放在热路径。
- 安全与隐私：令牌、密钥、身份验证、授权、订阅校验、后台管理、敏感数据落盘、日志暴露。
- 稳定性与恢复：异常传播、重试、超时、取消、幂等、事务边界、退出/登出、服务漂移、订阅状态漂移。
- 数据与一致性：数据库模型、迁移、缓存与服务端真相、测试数据库与生产数据库差异。
- 测试与可验证性：测试是否能真实覆盖关键行为，是否存在“结构测试很多、行为测试很少”的假阳性。
- 文档与开发体验：README/文档/脚本是否与真实代码一致，开发默认路径是否可用。
- AI 可读性与 AI 可编辑性：文件/类型是否过大、边界是否可推断、命名是否稳定、是否存在会误导 AI 的壳模块、过时文档或隐藏状态。

证据标准：
- 只写“有证据的问题”，每条问题都必须给出文件和行号。
- 如果是通过命令发现的，要给出命令摘要和结论。
- 如果是推断，必须明确标注“这是推断”，并解释为什么推断合理。
- 不要写泛泛的“建议优化”。

输出结构：
1. Scope
   - 审查范围
   - 读取的关键文件
   - 运行的关键命令及结果摘要
2. Prompt Self-Check
   - 说明这份 prompt 是否覆盖了 backend、macOS、命令验证、问题落盘、结果复核、ROI 方案筛选
3. Findings
   - 按严重度排序
   - 每条包括：标题、严重度、影响面、证据、为什么重要、建议方向、ROI 判断
4. Review of Findings
   - 去重
   - 降噪
   - 哪些是“必须做”、哪些是“应该做”、哪些是“观察项”
5. High-ROI Solutions
   - 只保留高回报项
   - 每项给出目标、改动边界、实施步骤、预期收益、风险
6. Validation Notes
   - 审查过程中有哪些限制、哪些结论已经被验证、哪些仍需后续验证

额外约束：
- 不修改业务代码。
- 不回避尖锐结论，但不要为了显得严格而夸大问题。
- 不把“未来可能想做的重构”伪装成“当前必须修复的问题”。
- 如果某一处设计是权衡而不是缺陷，要明确写出来。

在真正开始写报告前，先做一次 prompt 自检：
- 是否覆盖 backend 与 macOS 两部分？
- 是否要求跑命令而不是只读代码？
- 是否要求把问题写入一个 md 文件？
- 是否要求对结果做二次 review？
- 是否要求只为高 ROI 项生成方案？
- 是否要求给出文件与行号证据？

如果以上任一项没有覆盖，先修正 prompt 再执行。
```

## Self-Check

- Covers backend and macOS: yes
- Requires command-based validation: yes
- Requires saving issues to one Markdown file: yes
- Requires a second-pass review of findings: yes
- Requires ROI-based solution selection: yes
- Requires evidence with file and line references: yes
