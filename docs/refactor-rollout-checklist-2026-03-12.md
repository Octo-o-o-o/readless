# Readless Refactor Rollout Checklist (2026-03-12)

## 目标

为本次 1-7 步重构提供可执行的上线与回滚方案，重点覆盖：

- 后端新增迁移 `009_add_content_processing_metadata`
- 内容链路/认证链路/订阅链路/标签链路重构
- macOS 客户端 `ContentManager/ReaderViewModel/APIClient` 拆分重构

约束：

- 当前按单实例部署假设执行（不涉及多实例队列一致性）。
- 优先“可回滚、可观测、可分批”，避免一次性全量切换。

## 阶段 0：上线前闸门（必须全部通过）

### 代码与测试闸门

- [ ] 后端：`cd backend && pytest -q` 通过
- [ ] 后端：`cd backend && ruff check .` 无阻断错误
- [ ] macOS：`cd macos && swift build` 通过
- [ ] macOS：`cd macos && swift test` 通过

### 迁移与版本闸门

- [ ] `cd backend && alembic heads` 显示 `009 (head)`
- [ ] 确认生产环境 `DATABASE_URL` 指向正确实例
- [ ] 确认 `deploy.sh` 会执行迁移（或手动执行 `alembic upgrade head`）

### 运维闸门

- [ ] 执行一次数据库备份（上线前）
- [ ] 准备回滚包（上一版后端 tar 包）与回滚命令
- [ ] 明确值班窗口（建议至少 60 分钟观察）

## 阶段 1：后端发布（先后端，后客户端）

### 1.1 发布步骤

1. 上传并解压后端包到服务器（按现有流程）。
2. 在服务器执行部署：
   - `cd /root/backend`
   - `bash deploy.sh`
3. 确认迁移已到 `009`：
   - `docker compose -f docker-compose.prod.yml exec -T api alembic current`
4. 健康检查：
   - `curl https://readless.cc/health`
   - `curl https://readless.cc/docs`

### 1.2 后端验收（烟雾测试）

- [ ] 内容导入：`POST /api/v1/content/` 正常返回 `pending/processing`
- [ ] 内容查询：`GET /api/v1/content/` 返回结构正常
- [ ] 认证链路：`/api/v1/auth/login`、`/api/v1/auth/refresh` 正常
- [ ] 订阅链路：`/api/v1/subscription/status` 正常
- [ ] 标签链路：`/api/v1/tags` 相关接口正常
- [ ] 无持续异常日志：
  - `docker compose -f docker-compose.prod.yml logs --tail=200 api`

### 1.3 观察窗口（建议 30-60 分钟）

- [ ] `5xx` 未显著升高
- [ ] `401` 刷新失败未异常升高
- [ ] 内容处理失败率未异常升高
- [ ] 无迁移相关错误（字段不存在、类型不匹配等）

## 阶段 2：macOS 客户端分批发布

### 2.1 分批策略

1. 内部/灰度用户先行（10%-20%）。
2. 观察 24 小时后再扩大比例。
3. 全量前保持后端版本不变，避免双变量。

### 2.2 客户端验收

- [ ] 导入文本/URL 后轮询与状态更新正常
- [ ] Reader 打开内容时轮询/段落加载正常
- [ ] 401 自动刷新后请求可自动重试
- [ ] 登录/登出/恢复会话正常
- [ ] 标签筛选与更新正常

## 回滚方案

### 回滚触发条件（任一满足即回滚）

- 连续出现关键路径 5xx（内容导入、登录、刷新、订阅、标签）
- 认证刷新普遍失败导致用户无法继续使用
- 数据一致性异常（内容状态持续卡死、订阅状态错误更新）

### 后端回滚（优先）

1. 回滚到上一版后端代码并重启容器。
2. 本次 `009` 为**加字段的向后兼容迁移**，通常不需要立刻回滚数据库结构。
3. 若必须降级结构：
   - `cd backend && alembic downgrade 008`
   - 仅在确认旧代码不兼容新字段且已评估风险时执行。

### 客户端回滚

1. 停止扩大发布。
2. 回退到上一稳定客户端版本。
3. 后端保持当前版本通常可兼容旧客户端（已按接口兼容设计）。

## 发布后 24 小时复盘检查

- [ ] 内容处理成功率与平均处理时延
- [ ] 认证刷新成功率与 401 比例
- [ ] 订阅 webhook 处理成功率
- [ ] 标签接口错误率
- [ ] 用户侧关键投诉（登录失败、导入卡住、阅读页异常）

## 备注

- 本清单针对当前单实例部署模式；后续如引入多实例，需要补充任务分发与幂等策略清单。
- 若本次发布窗口紧张，建议先完成“后端发布 + 观察”，客户端顺延到下一个窗口。
