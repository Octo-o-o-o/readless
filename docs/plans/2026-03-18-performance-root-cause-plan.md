# Readless 性能根因排查与改造方案

日期：2026-03-18

## 结论

这次排查的结论不是“做几处小优化”就够了。

项目当前的包结构本身问题不大，`backend/` 与 `macos/` 的目录分层也基本清晰；真正有问题的是运行时数据流和同步边界：

1. 列表接口、详情接口、离线同步接口被混成了一个返回模型。
2. 客户端用多个 `@MainActor` 轮询器同时做状态同步、UI 更新和本地持久化，而且没有变化检测。
3. 后端把导入任务直接跑在 API 进程里，导入、搜索、正常读请求会互相争资源。

这三个问题是“根因级”的。它们会同时放大网络传输、JSON 解码、SQLite 写入、SwiftUI diff、主线程渲染、后端请求竞争和整体流畅度问题。

换句话说：当前卡顿不是单点 bug，而是几个边界设计叠加出来的系统性问题。

## 代码证据

### 1. 列表接口把 `full_text` 一起返回了

- `backend/app/schemas/content.py:18-35`
  - `ContentResponse` 同时承担列表和详情返回，并带有 `full_text`
- `backend/app/services/content_response.py:64-84`
  - `build_with_tags()` 无条件把 `content.full_text` 填进响应
- `backend/app/routers/content.py:139-186`
  - `GET /api/v1/content/` 直接返回 `list[ContentResponse]`
- `backend/app/models/content.py:52-56`
  - `full_text` 是正文全文，不是轻量字段
- `macos/Sources/App/ReadlessApp.swift:71-79`
  - 列表页真正消费的只是轻量 metadata
- `macos/Sources/App/Views/ContentListView.swift:13-63`
  - 列表渲染只用到标题、L0、来源和时间，不需要全文

这意味着客户端每次刷新内容列表，都可能把最多 50 篇正文整篇拉回本地。

### 2. 客户端每次刷新列表后都会把整批内容重新写入本地缓存

- `macos/Sources/App/Services/ContentManager.swift:152-160`
  - `fresh != contents` 时才更新 UI
  - 但无论是否变化，都会 `await cacheContents(fresh)`
- `macos/Sources/Storage/LocalDatabase.swift:202-213`
  - `saveContents()` 会循环保存所有内容记录

如果列表响应里还带着 `full_text`，那每次 refresh 都会触发：

后端查询全文 -> 网络传输全文 -> JSON 解码全文 -> SQLite 写入全文 -> FTS 触发器更新全文

### 3. 客户端轮询逻辑运行在主线程隔离域，而且每轮都更新 UI 和缓存

- `macos/Sources/App/Services/ImportTrackingCoordinator.swift:4-5`
  - `ImportTrackingCoordinator` 整体是 `@MainActor`
- `macos/Sources/App/Services/ImportTrackingCoordinator.swift:132-146`
  - 每轮轮询都会：
    - `fetchContent`
    - `onContentUpdate`
    - `persistContent`
    - 即使内容根本没变化
- `macos/Sources/App/Services/ContentManager.swift:262-280`
  - 列表页轮询回调总是 `upsertContent`，总是写缓存
- `macos/Sources/App/ViewModels/ReaderViewModel.swift:308-330`
  - 详情页还有一套独立轮询器，也会重复写缓存和更新 `content`
- `macos/Sources/App/Services/ContentManager.swift:207-212`
  - `upsertContent()` 只要命中同一个 id 就直接整体替换

这会导致正在处理中的内容每 2 秒至少触发一次：

- 网络请求
- 主线程状态变更
- SwiftUI 重算
- SQLite 写入

而且列表页和详情页可以同时干这件事。

### 4. Outline 的 identity 每次解码都变

- `backend/app/schemas/summary.py:6-10`
  - 后端 `OutlinePoint` 没有稳定 `id`
- `macos/Sources/Core/Models/Outline.swift:18-24`
  - 客户端解码时如果没有 `id` 就 `UUID().uuidString`

结果是同一篇内容只要重新拉一次，客户端就会把所有 outline point 视为“全新对象”，SwiftUI diff 失去稳定锚点，展开态和行级动画也更容易抖动。

### 5. 原文/富文本预览有明显主线程 CPU 工作

- `macos/Sources/App/Views/OriginalContentPanel.swift:11-31`
  - `detectContentFormat()` 会直接尝试 JSON 解析和多次正则匹配
- `macos/Sources/App/Views/OriginalContentPanel.swift:67-80`
  - `updateCachedText()` 会在主线程拼接全文、判断格式
- `macos/Sources/App/Views/OriginalContentPanel.swift:330-350`
  - Markdown 富文本构造在 `.task` 中直接做
- `macos/Sources/App/Views/OriginalContentPanel.swift:366-454`
  - JSON pretty-print + 颜色标注也在视图任务里直接做
- `macos/Sources/App/Views/OutlineView.swift:191-217`
  - L2 detail 的 attributed text 构造也在视图任务里直接做

这类逻辑在大文本上非常容易直接变成可见卡顿。

### 6. Command Bar 默认走重型云搜索，而且输入时就可能触发完整 AI 搜索链

- `macos/Sources/App/Services/CommandBarService.swift:55-62`
  - 默认 `searchMode = .cloud`
- `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift:135-142`
  - View 层有一层 150ms debounce
- `macos/Sources/App/Services/CommandBarService.swift:64-81`
  - Service 层又有一层 300ms debounce
- `macos/Sources/App/Services/CommandBarService.swift:161-201`
  - Cloud search 直接打后端 AI 搜索
- `backend/app/services/search_agent.py:35-52`
  - 搜索流程是：
    - AI parse intent
    - PostgreSQL FTS
    - AI rerank
    - AI answer
- `backend/app/services/search_agent.py:85-123`
  - FTS SQL 还是 `SELECT *`

这意味着用户在输入阶段就可能频繁触发高成本搜索链路，不仅慢，而且会把后端和客户端都拖重。

### 7. 后端导入任务直接跑在 API 进程里

- `backend/app/services/content_jobs.py:1`
  - 文件自己就写明是 `single-process background execution`
- `backend/app/services/content_jobs.py:38-66`
  - 用 `asyncio.create_task()` 在 Web 进程内起后台任务
- `backend/app/services/content_jobs.py:68-85`
  - 任务直接调用 `ProcessingPipeline`
- `backend/app/services/extractor.py:89-220`
  - URL 抽取、PDF 解析、OCR 都是重工作
- `backend/app/services/pipeline.py:184-218`
  - 抽取、总结、入库、FTS 更新串行执行
- `backend/app/services/pipeline.py:282-294`
  - 总结之后又额外发一次语言识别请求

这会造成两个问题：

1. 导入吞吐差，任务堆积时用户感觉“处理很卡”
2. 导入任务和普通读请求共享同一个 API 进程，容易把接口响应也拖慢

## 根因排序

### P0：必须优先解决

1. 列表接口返回全文，导致跨层数据放大
2. 客户端轮询没有变化检测，且轮询器本身在 `@MainActor`
3. 列表刷新和轮询刷新都会重复写本地缓存

这三点解决前，任何局部优化都很难带来“质的提升”。

### P1：第二阶段必须解决

4. Outline identity 不稳定，导致 SwiftUI diff 抖动
5. 原文预览/详情富文本处理跑在主线程
6. Command Bar 在输入阶段就走重型云搜索链路

### P2：吞吐与稳定性优化

7. 后端导入任务和 API 服务共进程
8. 导入链路多做了一次单独语言识别调用
9. 热路径日志过多，进一步放大 debug/release 中的 IO 抖动

## 是否需要修改架构

需要，但不是“推倒重写”。

### 不需要重写的部分

- `backend/services`、`routers`、`models` 这类目录组织没有本质问题
- macOS 侧 target/module 划分也不是主要性能瓶颈

### 必须修改的运行时架构边界

1. 列表数据和详情数据必须彻底分离
2. 轮询/状态同步必须单点集中，且不跑在 UI 主 actor 上
3. 本地缓存必须改成按变更增量写，而不是整批重写
4. 搜索必须拆成“输入期轻量检索”和“提交后重型答案生成”
5. 导入任务最终应该脱离 API 进程

## 完整改造方案

## 方案 A：先打掉最大的流量与写放大

### A1. 拆分 API DTO

新增三个明确模型：

- `ContentListItemResponse`
  - 只包含列表显示所需字段
  - 不包含 `full_text`
  - 不包含大块 `detail`
- `ContentDetailResponse`
  - 详情页使用
  - 包含 `full_text`
  - 允许包含完整 `l1_outline`
- `ContentStatusResponse`
  - 轮询/状态同步使用
  - 只包含 `id`, `status`, `updated_at`, `processing_error`, 必要时带 `l0_summary`

对应后端接口：

- `GET /api/v1/content/`
  - 返回 `list[ContentListItemResponse]`
- `GET /api/v1/content/{id}`
  - 返回 `ContentDetailResponse`
- `GET /api/v1/content/statuses?ids=...`
  - 返回 `list[ContentStatusResponse]`

### A2. 客户端缓存分层

把本地缓存拆成两层：

- 元数据缓存
  - 供列表、标签、基础搜索使用
- 全文缓存
  - 供原文面板、段落追踪、本地全文检索使用

需要新增本地字段：

- `hasFullText`
- `hasParagraphs`
- `lastHydratedAt`
- `contentRevision` 或直接用 `updatedAt`

### A3. 列表刷新改成增量写

目标：

- 列表 refresh 只写新增和变化项
- `updatedAt` 没变化就不写 SQLite
- 删除项单独清理

客户端改法：

- `ContentManager.loadContents()` 中不再无条件 `cacheContents(fresh)`
- 先把 `fresh` 转成 `id -> updatedAt`
- 与本地缓存对比后只写 dirty rows

### A4. 本地全文检索改成按需 hydration

当前问题是为了“本地搜索”把全文从列表接口里强行带回来了，这个方向是错的。

正确做法：

- 列表接口只同步元数据
- 用户点开内容时，详情接口拉取全文并缓存
- 后台空闲时再预取“最近访问 N 条”的全文
- 本地搜索默认先搜标题、L0、已 hydration 的全文
- 如果需要更强搜索，再增加后台 hydration 策略，而不是让列表接口背锅

## 方案 B：重做状态同步，不再让 UI 层各自轮询

### B1. 新建 `ContentSyncService`

职责：

- 统一管理所有 pending/processing 内容的同步
- 运行在独立 `actor`，不在 `@MainActor`
- 维护 `contentID -> lastSeen(status, updatedAt)` 状态表
- 只在状态变化时才通知 UI 和缓存层

UI 层：

- `ContentManager`
- `ReaderViewModel`

都不再直接持有轮询器，只订阅 `ContentSyncService` 推送的变更。

第一阶段落地时可以先用更低风险的等价实现：

- 保留 `ContentManager` 侧唯一轮询协调器
- `ReaderViewModel` 不再自建第二套轮询
- 通过共享更新通知复用同一份同步结果

这样可以先消掉重复轮询和重复落库，再视需要把它抽成独立 `ContentSyncService` 类型。

### B2. 同步粒度改为批量

替代现在的“每个内容一个请求，每 2 秒一次”：

- 一次请求查多个 `content_id`
- 或者直接做 SSE/WebSocket

最低成本版本：

- 新增 `GET /api/v1/content/statuses?ids=...`
- 每 2 秒一次批量状态请求

更优版本：

- SSE 推送处理状态
- 客户端只在状态真正变化时刷新对应内容

### B3. 轮询必须先做变化检测

变更判断键至少包括：

- `status`
- `updated_at`
- `processing_error`
- 对 ready 内容可加 `l0_summary`

如果没有变化：

- 不更新 `contents`
- 不更新 `ReaderViewModel.content`
- 不写本地数据库

### B4. UI 状态管理收口

现在：

- `ContentManager` 自己维护列表轮询
- `ReaderViewModel` 再维护详情轮询

改造后：

- `ContentManager` 只关心列表状态
- `ReaderViewModel` 只关心当前内容展示
- 同步来源只有一个

## 方案 C：修复 SwiftUI diff 和主线程渲染问题

### C1. 给 OutlinePoint 生成稳定 ID

推荐后端直接生成并持久化：

- `point_id = sha1(point + sorted(anchors))[:12]`
  或
- `point_id = f"{content_id}:{index}"`

如果暂时不改后端，客户端至少也要改成确定性 id，而不是 `UUID()`。

### C2. 富文本解析全部移出主线程

以下逻辑全部移到后台任务：

- 原文格式判断
- Markdown 解析
- JSON pretty-print + colorize
- detail citation attributed string 构造

原则：

- 首屏先显示 plain text
- 富文本结果异步替换
- 超过阈值的文本默认不做富文本预览，只提供“切换到富文本预览”按钮

建议阈值：

- `> 32 KB`：默认 plain text
- `> 128 KB`：禁止自动 JSON/Markdown 富解析

### C3. 大文本面板先做分页/懒渲染

`OriginalContentPanel` 不要在主线程一次性：

- 拼整篇全文
- 判断格式
- 建整块 `AttributedString`

可以改成：

- trace 模式继续按 paragraph 渲染
- full text 模式先分 chunk
- 富文本预览按 chunk 或只对可见部分处理

## 方案 D：把 Command Bar 变回“实时可交互”，而不是“每次输入都跑 AI 工作流”

### D1. 输入期只做轻量检索

输入阶段：

- 本地 FTS 或后端纯 FTS
- 不做 AI intent parse
- 不做 AI rerank
- 不做 AI answer synthesis

只有在用户明确提交时，才进入 AI answer。

### D2. 搜索链路拆成两段接口

后端拆分：

- `POST /api/v1/search/retrieve`
  - 返回候选内容
- `POST /api/v1/search/answer`
  - 基于用户明确选择/提交的问题生成答案

这样 Command Bar 输入时不会被 3 段 LLM 调用拖死。

### D3. 取消双重 debounce

当前 view 层 150ms，service 层 300ms，逻辑重复。

保留一层即可：

- UI 层只负责取消旧请求
- Service 层统一 debounce/cancellation

### D4. 搜索 SQL 不要 `SELECT *`

`backend/app/services/search_agent.py:85-123` 改成只取：

- `id`
- `title`
- `l0_summary`
- `l1_outline`
- `source_url`
- `updated_at`

不要把 `full_text` 整列读出来再做 rerank。

## 方案 E：把导入任务从 API 进程里拆出去

### E1. 短期方案：数据库任务表 + 独立 worker 进程

最小可落地版本：

- 新增 `content_jobs` 表
- API 只负责入队
- Worker 进程轮询 job 表执行
- 状态写回 `contents` / `content_jobs`

这样至少能做到：

- API 请求不和 OCR/PDF/抓取/总结抢同一事件循环职责
- 服务重启后任务可恢复
- 可以独立调 worker 并发，而不是卡死在 API 容器里

### E2. 长期方案：事件驱动同步

如果后续要做更丝滑：

- worker 更新 job 状态
- API 提供 SSE
- 客户端 `ContentSyncService` 订阅状态变更

### E3. 删掉额外语言识别调用

`backend/app/services/pipeline.py:282-294` 现在是：

- 先总结
- 再单独 `translator.detect_language()`

应改成一次 LLM 返回：

- `l0_summary`
- `l1_outline`
- `tags`
- `keywords`
- `language_code`

这样每次导入直接少一次模型请求。

## 具体实施顺序

### 第一阶段：必须先落地

1. 拆分列表/详情/状态 DTO
2. 客户端列表刷新改成增量写
3. 新建 `ContentSyncService`，替代双轮询器
4. 轮询增加变化检测，未变化不写 UI、不写缓存
5. Outline 使用稳定 ID

这一阶段完成后，性能和流畅度就应该有质变。

## 第一阶段实施结果

截至 2026-03-18，本轮已完成以下改造：

1. 已拆分后端列表 / 详情 / 状态 DTO
2. 已新增 `GET /api/v1/content/statuses?ids=...` 批量状态接口
3. `GET /api/v1/content/` 与 `GET /api/v1/tags/{id}/contents` 已不再返回 `full_text`
4. 客户端本地缓存改为合并写入
5. 列表同步时会保留已 hydration 的 `fullText` / `l1Outline`
6. 未变化记录会跳过 SQLite 写入
7. `ReaderViewModel` 已移除独立轮询，改为消费 `ContentManager` 的同步结果
8. 轮询已改成批量状态检查 + 变化检测后再拉详情

这意味着最关键的三个 P0 根因里，已经实际处理了两类放大源：

- 列表接口的正文传输放大
- 客户端重复轮询、重复写缓存

仍待继续落地的高优先项：

1. Outline 稳定 ID
2. 原文/富文本主线程解析
3. Command Bar 重型搜索链拆分
4. 导入任务脱离 API 进程

本轮验证结果：

- `pytest backend/tests/routers/test_content.py` 通过
- `pytest backend/tests/routers/test_tags.py` 通过
- `pytest backend/tests/test_pipeline.py -k ContentResponse` 通过
- `swift test --filter LocalDatabaseTests` 通过
- `swift test --filter APIClientTests` 通过

## 第二阶段实施结果

截至 2026-03-18，本轮继续完成了以下高价值改造：

1. 后端 outline point 已生成稳定 ID，新内容入库即持久化稳定 ID
2. 历史内容即使数据库里没有 `id`，详情接口返回时也会补稳定 ID
3. 客户端 `OutlinePoint` fallback 已从随机 `UUID()` 改成确定性 ID
4. `OriginalContentPanel` 的全文拼接、格式检测已移到后台任务
5. Markdown / JSON 预览和 L2 detail attributed text 构造已移到后台任务
6. 大文本预览已加入降级策略
7. `Command Bar` 输入阶段已切换到轻量 `retrieve` 接口
8. `Command Bar` 已从双 debounce 收口为单层 debounce
9. 后端搜索热路径已不再 `SELECT *`
10. 导入链路已把语言识别并入总结返回，省掉一次额外模型请求

这一轮后，P1 里最影响交互顺滑度的两项已经落地：

- SwiftUI diff 抖动
- 主线程富文本 CPU 峰值

同时又顺手解决了两个会直接影响整体响应成本的问题：

- 输入期重型云搜索
- 导入阶段额外语言识别请求

本轮新增验证结果：

- `pytest backend/tests/test_summarizer.py` 通过
- `pytest backend/tests/test_search.py` 通过
- `pytest backend/tests/test_pipeline.py -k "process_content"` 通过
- `swift test --filter ContentTests` 通过

## 第三阶段实施结果

截至 2026-03-18，本轮继续完成了吞吐和稳定性最关键的一步：

1. 已新增 `content_jobs` 数据表，导入任务正式从进程内 `asyncio.create_task()` 改为数据库队列
2. `POST /api/v1/content/` 现在只负责创建 `contents` 占位行并入队 job，不再在 API 进程内直接跑抽取/总结
3. 已新增独立 `app.worker` 进程，轮询 `content_jobs` 并执行 `ProcessingPipeline`
4. worker 启动时会回收上次异常退出留下的 `running` job，避免任务永久悬挂
5. `pending/processing` 内容的恢复逻辑已改为基于 `content_jobs`，而不是基于 API 进程内存任务表
6. 超时失败逻辑也已改成基于数据库 job 状态，重启后仍然成立
7. Docker Compose 与生产部署脚本已加入独立 `worker` 服务

这一步是根因级收益，不是一般性的“后台化”：

- API 请求线程现在只做入队和读写，不再与 OCR / PDF / 抓取 / 总结共享同一个进程热路径
- 导入高峰时，接口读请求和导入任务的 CPU / IO 争抢被物理拆开
- 任务恢复不再依赖单个 API 进程的内存状态，服务重启后吞吐不会直接掉到“全部丢失”

本轮新增验证结果：

- `pytest backend/tests/services/test_content_jobs.py` 通过
- `pytest backend/tests/routers/test_content.py` 通过
- `pytest backend/tests/test_pipeline.py` 通过
- `pytest backend/tests/test_search.py` 通过
- `ruff check backend/app backend/tests` 通过

### 第二阶段：明显改善交互手感

6. 原文/详情富文本解析移出主线程
7. Command Bar 输入期改为轻量检索
8. 去掉搜索双 debounce

### 第三阶段：改善吞吐和线上稳定性

9. 导入任务迁移到独立 worker
10. 总结接口合并语言识别
11. 对重型抓取/OCR/PDF 路径加指标与超时分层

其中 9 和 10 已完成，11 仍建议保留。

## 验证标准

### 用户可感知目标

- App 启动后内容列表应先秒开缓存，再无明显 UI 卡顿地完成远端刷新
- 正在处理内容时，列表和详情页不应每 2 秒肉眼抖动一次
- 打开“查看原文”不应出现明显冻结
- Command Bar 输入时结果应连续更新，而不是明显停顿

### 技术指标目标

1. `GET /api/v1/content/` 响应体大小下降 80% 以上
2. `loadContents()` 对本地数据库的写入量下降 80% 以上
3. 同时有 5 个 processing 内容时，客户端状态请求从 `O(n)` 降为 `O(1)` 批量请求
4. 未变化内容的轮询写入次数降为 0
5. 打开大文本原文面板时主线程卡顿从“可见”降到“几乎不可见”
6. Command Bar 输入阶段不再触发完整 AI 搜索链
7. 导入高峰下 API 读请求不再与导入任务共享同一进程的执行热点

### 建议增加的埋点

- 列表接口 payload bytes
- 客户端 `loadContents()` 耗时
- `cacheContents()` 实际写入条数、总字节数
- 轮询请求数 / 每分钟
- 未变化内容被写缓存的次数
- 原文面板富文本解析耗时
- Command Bar 从输入到首批结果耗时
- worker job 队列长度、claim 延迟、成功率、超时率

## 需要改动的关键文件

后端：

- `backend/app/schemas/content.py`
- `backend/app/models/content_job.py`
- `backend/app/services/content_response.py`
- `backend/app/routers/content.py`
- `backend/app/services/content_jobs.py`
- `backend/app/services/pipeline.py`
- `backend/app/worker.py`
- `backend/app/services/search_agent.py`
- `backend/alembic/versions/010_add_content_jobs.py`
- `backend/docker-compose.prod.yml`
- `backend/deploy.sh`

macOS：

- `macos/Sources/App/Services/ContentManager.swift`
- `macos/Sources/App/Services/ImportTrackingCoordinator.swift`
- `macos/Sources/App/ViewModels/ReaderViewModel.swift`
- `macos/Sources/Core/Models/Outline.swift`
- `macos/Sources/Storage/LocalDatabase.swift`
- `macos/Sources/App/Views/OriginalContentPanel.swift`
- `macos/Sources/App/Services/CommandBarService.swift`
- `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift`
- 新增 `macos/Sources/App/Services/ContentSyncService.swift`

## 这份方案是否已经抓住根因

是。

原因是这里优先处理的不是“某个函数慢”，而是三个会在整个链路里反复放大的结构问题：

1. 大字段在错误的接口层级传播
2. 无变化检测的重复同步
3. UI、缓存、后台处理职责耦合在同一条热路径里

只要这三点不改，继续做局部优化通常只能得到“稍微快一点”，很难得到“明显更流畅”。

## 文档复核结果

这份文档在写完后又做了一次逆向复核，结论如下：

1. 仅修 `OriginalContentPanel`、`Command Bar` 或某几个 SwiftUI view，并不能解释“经常卡顿”这个整体症状，因为这些问题主要发生在局部交互。
2. 真正能解释“启动刷新卡、处理中卡、列表偶发抖、数据库反复写”的，是 P0 三项一起存在：
   - 列表带全文
   - 无变化检测的轮询
   - 整批重写本地缓存
3. 即使只做 P0，不做 P1/P2，也已经足以带来一次明显的流畅度跃迁。
4. 但如果只做 P0，不处理 P1，那么“打开原文卡一下”和“Command Bar 输入偏重”仍然会保留，所以 P1 仍然保留在文档中，不下调优先级。

因此，这份方案最终保留了 P0/P1/P2 三层结构，没有再继续删减。

补充复核结论：

5. 现在把 worker 也真正落地后，后端链路上的三个主要热路径已经被拆开：
   - 列表/详情读路径
   - 状态同步路径
   - 导入处理路径
6. 这说明原方案里把“运行时边界”而不是“目录结构”当成架构问题，是正确判断。
7. 当前剩余最值得继续做的，不再是重新设计任务系统，而是给抓取 / OCR / PDF 路径补指标和分层超时，进一步降低长尾卡顿。

## 仍然刻意没有当作根因的问题

下面这些可以优化，但我不认为它们是当前“经常卡顿”的主因：

- 一般性的 SwiftUI 动画数量
- 单个 view 的排版细节
- 普通 SQL 索引微调
- 热键监听本身的基础开销
- 常规日志打印本身

它们最多是放大器，不是主因。
