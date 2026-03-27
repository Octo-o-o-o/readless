# Readless 架构优化方案与复核

日期：2026-03-22
仓库：`/Users/wangyixiao/WorkSpace/readless`

## 结论

当前项目的总体技术选型是合理的，不需要重写：

- 后端继续使用 FastAPI + async SQLAlchemy + PostgreSQL 是对的
- 内容导入已经从同步请求路径改成了数据库队列 + 独立 worker，这个方向是对的
- macOS 端继续使用 SwiftUI + SPM 模块 + GRDB 本地缓存也是合理的

但是，如果目标是把流畅度、用户体验和后续扩展做到更优，当前仍然有 4 个需要调整的架构边界：

1. macOS 端“声明的模块边界”和“真实代码边界”仍然不一致
2. 客户端会话与内容同步仍然依赖全局单例和 `NotificationCenter`
3. 后端内容任务队列会长期保留大体积原始 payload
4. 搜索层缺少语言感知的索引策略，对中英文混合场景扩展性不足

这不是推倒重来级别的问题，但已经足够构成“需要调整框架边界，而不是只修几个实现细节”。

## 代码证据

### 1. feature target 还是占位，真实功能仍集中在 `App`

- `macos/Sources/ReaderFeature/ReaderFeature.swift`
- `macos/Sources/LibraryFeature/LibraryFeature.swift`
- `macos/Sources/App/ReadlessApp.swift`
- `macos/Sources/App/Views/ReaderView.swift`
- `macos/Sources/App/Services/ContentManager.swift`

`Package.swift` 已经声明了 `ReaderFeature` 和 `LibraryFeature`，但当前两个 target 仍然只是占位文件，主要 UI、状态协调和交互逻辑仍然堆在 `App` 目录里。这样会让后续多人协作、AI 辅助修改和模块演进都变得更难。

### 2. 会话刷新和内容同步仍然是隐式全局协作

- `macos/Sources/Networking/APIClient.swift`
- `macos/Sources/App/Services/AuthService.swift`
- `macos/Sources/Networking/AuthRefreshCoordinator.swift`
- `macos/Sources/App/Services/ContentManager.swift`
- `macos/Sources/App/ViewModels/ReaderViewModel.swift`

当前客户端已经比之前清晰很多，但仍然存在：

- `APIClient.shared`
- `AuthService.shared`
- `ContentManager.shared`
- 通过 `NotificationCenter` 触发 token refresh
- 通过 `NotificationCenter` 广播内容更新

这套机制能工作，但边界不够显式。它会让会话恢复、401 重试、内容轮询、详情页刷新之间的因果关系继续藏在全局状态里。

### 3. 队列表会长期保存原始导入 body，图片/PDF 会把数据库做大

- `backend/app/models/content_job.py`
- `backend/app/services/content_jobs.py`
- `backend/app/schemas/content.py`

`content_jobs.body` 是必填 `Text` 字段，当前会直接保存原始导入 body。对于：

- `text`
- `url`
- base64 PDF
- base64 image

这意味着数据库队列不仅承担“调度信息”，还承担了“原始载荷存储”。而当前 job 成功后只会标记 `succeeded`，不会清空 `body`，也没有 job retention / purge 机制。随着导入量增长，数据库、备份、迁移和运维成本都会被放大。

### 4. 搜索索引策略没有按语言抽象，后续扩展会受限

- `backend/app/services/pipeline.py`
- `backend/app/services/search_agent.py`
- `macos/Sources/Storage/LocalSearchService.swift`

现在服务端和本地搜索都已经有独立入口，但索引策略仍偏“单一 tokenizer 假设”：

- PostgreSQL 侧使用 `to_tsvector('simple', ...)`
- 本地搜索侧把查询按空格切词

这对英文还算可用，但对于中文和中英混合内容，并没有真正的语言感知搜索层。项目既然明确支持中英双语内容，搜索层最终需要按语言做索引策略抽象，否则后续搜索体验和知识库扩展都会受限。

## 推荐调整方案

## P0. 让 macOS 模块边界变成真实边界

### 目标

把“阅读器功能”和“内容库功能”从 `App` 目录中真正抽出来，让 `App` 只负责：

- 启动
- 依赖注入
- 窗口与场景装配

### 调整

1. 把以下内容迁入 `ReaderFeature`
   - `ReaderView`
   - `ReaderViewModel`
   - `OutlineView`
   - `OriginalContentPanel`
   - `SourceTracePanel`

2. 把以下内容迁入 `LibraryFeature`
   - `ContentListView`
   - 侧边栏 section 逻辑
   - tag filter 的 library 侧展示

3. 把 `ReadlessApp.swift` 缩成应用装配层，不再直接承载主要业务 UI

### 预期收益

- 降低大文件修改冲突
- 提高功能边界清晰度
- 后续接入 iPad / iOS 或新入口时，更容易复用 feature 层

## P0. 用显式的 AppContext / SessionStore 替代全局通知式协作

### 目标

把当前的全局单例 + `NotificationCenter` 协作，收敛成显式依赖注入。

### 调整

1. 新增 `AppContext`
   - 持有 `SessionStore`
   - 持有 `ContentSyncService`
   - 持有 `APIClient`
   - 持有 `ContentRepository`

2. 把 token refresh 改成显式会话接口
   - `APIClient` 不再通过通知请求刷新 token
   - 改成依赖 `SessionStore`/`SessionActor` 提供 `validAccessToken()`

3. 把内容更新广播改成 typed sync channel
   - `ReaderViewModel` 不再监听全局 `NotificationCenter`
   - 统一通过 `ContentSyncService` 订阅内容状态变化

4. 把 `shared` 单例逐步变成注入默认值，而不是硬编码访问点

### 预期收益

- 降低并发和状态错位风险
- 减少 `@unchecked Sendable` 的使用压力
- 提高测试可替换性

## P0. 收敛内容任务队列的数据职责

### 目标

让 `content_jobs` 只承担“调度”职责，而不是长期保存大体积原始载荷。

### 调整

1. 对 `url` / `text`
   - 仅保留最小可恢复输入

2. 对 `pdf` / `image`
   - 不把大体积 base64 永久保存在 job 表
   - 改成临时文件或对象存储 staging key

3. 在 job 成功或失败后
   - 清空 `body`
   - 或写入 `body_digest` / `staging_key`

4. 增加 retention 机制
   - 定期删除成功 job
   - 定期清理旧失败 job

### 预期收益

- 避免数据库被上传体积拖大
- 降低备份和迁移成本
- 让队列模型更接近真正的 job queue

## P1. 把搜索升级为“语言感知索引层”

### 目标

保留现有搜索入口，但让底层索引策略可按语言选择，而不是所有内容统一走一套分词假设。

### 调整

1. 服务端新增 search indexing strategy
   - 英文内容：继续使用 PostgreSQL FTS
   - 中文内容：增加 trigram / 专门 tokenizer / 外部检索方案
   - 混合内容：允许 dual-index

2. 本地搜索同步策略对齐服务端
   - 本地 metadata search
   - 本地 full-text search
   - 中文查询不再依赖空格切词

3. 将 `source_language` 纳入索引与检索策略选择

### 预期收益

- 搜索体验更符合项目的双语定位
- 为后续 RSS、邮件、知识库聚合提供更稳的检索底层

## P1. 后端配置与应用服务继续收口

### 目标

当前后端已经明显改善，但还可以再把“可维护性边界”收紧一层。

### 调整

1. 把 `settings = Settings()` 从 import-time 全局对象，收敛成缓存 getter
2. 继续压缩 `backend/app/routers/content.py`
3. 把搜索、内容查询、状态恢复等逻辑尽量留在 service 层

### 预期收益

- 降低测试和脚本场景下的 import 副作用
- 减少 router 层的策略性逻辑
- 为后续多 worker / 多环境配置做准备

## 不建议做的事

以下方案不是当前阶段的最优选择：

1. 不建议整体重写成 TCA / Redux 风格客户端
   - 成本太高
   - 当前问题主要不是状态库缺失，而是边界尚未完全收口

2. 不建议现在就引入 Kafka / Redis Queue / Celery
   - 当前单 worker + PostgreSQL queue 对现阶段已够用
   - 真正急迫的问题是 job payload 生命周期，而不是先换中间件

3. 不建议马上把内容处理改成 WebSocket/SSE 驱动
   - 当前轮询链路已经被显著收敛
   - 相比之下，客户端会话边界和 job 表职责更值得优先处理

## 实施顺序

### Phase 1

- 引入 `AppContext`
- 替换 auth refresh 的通知式协作
- 替换内容更新通知为 typed sync service

### Phase 2

- 真正迁移 `ReaderFeature` / `LibraryFeature`
- 缩小 `ReadlessApp.swift`
- 缩小 `ReaderView.swift`

### Phase 3

- 收敛 `content_jobs` 的原始 payload 存储
- 加入 retention / purge
- 完成数据迁移

### Phase 4

- 建立语言感知搜索索引层
- 对齐服务端与本地搜索策略

## 方案复核

我复核后的判断是：这是一份“当前仓库状态下的最佳调整方案”，原因如下。

1. 它保留了已经做对的部分
   - 不推翻 FastAPI / PostgreSQL / SwiftUI / GRDB
   - 不否定已经完成的异步导入和仓储层收敛

2. 它优先修的是“边界问题”而不是“风格问题”
   - 先修 feature 边界
   - 再修 session / sync 边界
   - 再修 queue 数据职责
   - 最后补搜索扩展性

3. 它兼顾了用户体验、性能和后续扩展
   - UX：减少状态同步隐式耦合和大文件抖动
   - 性能：减少数据库负担与全局状态扩散
   - 扩展：为双语搜索和更多内容源留出空间

4. 它的实施风险可控
   - 每一步都能渐进式落地
   - 不需要停机重构
   - 不需要大规模替换已有基础设施

## 本次验证结果

- `backend`: `pytest -q` 通过，`276 passed`
- `backend`: `ruff check .` 未通过，当前剩余 1 个 import 排序问题，位于 `backend/create_tables.py`
- `macos`: `swift test` 通过，`93 tests passed`

这进一步说明：当前项目不是“已经坏到要重写”，而是“基础方向正确，但还需要把关键边界做实”。
