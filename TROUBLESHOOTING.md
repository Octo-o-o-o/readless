# Command Bar 问题修复指南

## 🚀 部署到服务器（推荐用于稳定测试）

如果你不想每次都在本地启动后端，可以将后端部署到远程服务器。

### 快速部署步骤

1. **选择部署方式**（详见 [DEPLOYMENT.md](DEPLOYMENT.md)）：
   - Railway.app（最简单，推荐新手）
   - Docker Compose on VPS（生产环境推荐）
   - Render / Fly.io（免费选项）

2. **部署后端**（以 Docker Compose 为例）：

```bash
# 在服务器上
git clone https://github.com/你的用户名/readless.git
cd readless/backend

# 启动服务（包含 PostgreSQL + API + Caddy HTTPS）
sudo docker compose up -d --build

# 运行数据库迁移
sudo docker compose exec api alembic upgrade head

# 验证
curl https://你的域名/health
```

3. **配置 macOS 客户端连接到服务器**：

```bash
# 方法 1: 使用配置脚本（推荐）
cd macos
./configure-backend.sh https://api.readless.cc

# 方法 2: 手动设置
defaults write com.readless.app apiBaseURL "https://api.readless.cc"

# 验证配置
defaults read com.readless.app apiBaseURL
```

4. **重启 macOS App**：
   - 完全退出 App（⌘Q）
   - 重新运行 `swift run` 或在 Xcode 中运行
   - 查看日志应显示：`[Readless] Using configured API base URL: https://api.readless.cc`

5. **测试导入功能**：
   - ⌘K 打开 Command Bar
   - 粘贴长文本
   - 按 Enter 导入
   - 应该成功（不再报错 `error 0`）

### 恢复本地开发

```bash
# 删除服务器配置，恢复使用 localhost
defaults delete com.readless.app apiBaseURL

# 重启 App，会自动使用 http://localhost:8000
```

---

## 你遇到的4个问题及解决方案

### ✅ 问题1: ⌘K 后窗口没有激活到前台

**症状**: 按 ⌘K 后 Command Bar 打开，但需要手动切换到 App

**原因**: 没有在打开 Command Bar 时激活应用窗口

**✅ 已修复**:
- 修改了 `ReadlessApp.swift`
- 添加 `NSApp.activate(ignoringOtherApps: true)`
- 现在按 ⌘K 会自动激活窗口到前台

---

### ✅ 问题2: UI 显示太复杂

**症状**: 粘贴内容后显示完整的内容预览

**期望**: 只显示简单的操作提示 "Enter For Import / Command + Enter For Retrieve"

**✅ 已修复**:
- 修改了 `CommandBarService.swift`
- 简化为2个清晰的选项：
  ```
  📥 Import this content
     Enter — Generate summary and outline

  🔍 Search for similar content
     ⌘↩ — Search local library
  ```

---

### ⚠️ 问题3: 按 Enter 后导入失败

**症状**:
```
Import failed: The operation couldn't be completed.
(Networking.APIError error 0.)
```

**原因**: **后端 API 服务没有运行**

**✅ 解决方案**:

#### 方法1: 启动后端服务（推荐）

```bash
# 在终端运行
cd /Users/wangyixiao/WorkSpace/readless
./start-backend.sh
```

或者手动启动：

```bash
cd backend
source venv/bin/activate  # 如果没有venv，先 python3 -m venv venv
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

#### 方法2: 检查后端配置

1. **确保 .env 文件存在**:
   ```bash
   cd backend
   ls -la .env  # 应该存在
   ```

2. **如果没有 .env，创建一个**:
   ```bash
   cp .env.example .env  # 如果有example文件
   ```

3. **编辑 .env 添加必要配置**:
   ```env
   OPENAI_API_KEY=your_key_here
   DATABASE_URL=postgresql://...
   # 其他必需配置
   ```

#### 验证后端运行

打开浏览器访问：http://localhost:8000/docs

如果看到 FastAPI 文档页面，说明后端正常运行。

---

### ⚠️ 问题4: 权限和快捷键问题

**症状**:
- 每次运行都提示权限
- 已在系统设置添加 App，但仍然提示
- Option+Shift+R/D 快捷键不生效

**原因**:
- 开发阶段每次构建，App 路径/签名可能变化
- macOS 辅助功能权限基于 App bundle ID 和签名
- 开发构建不稳定，每次可能被识别为"新 App"

**✅ 解决方案**:

#### 解决方法1: 使用 Xcode 构建并固定路径（推荐）

1. **在 Xcode 中打开项目**:
   ```bash
   cd macos
   open Package.swift  # Xcode会自动打开
   ```

2. **设置固定的构建路径**:
   - Xcode → Preferences → Locations
   - Advanced → 选择 "Unique"

3. **添加构建产物到辅助功能权限**:
   - 系统设置 → 隐私与安全性 → 辅助功能
   - 点击 `+`
   - 添加路径: `/Users/wangyixiao/Library/Developer/Xcode/DerivedData/App-xxx/Build/Products/Debug/App.app`

#### 解决方法2: 临时方案 - 添加整个构建目录

**⚠️ 安全警告**: 这会给予整个构建目录辅助功能权限

1. **系统设置 → 隐私与安全性 → 辅助功能**
2. **点击 `+`，添加这些路径**:
   - `/Users/wangyixiao/Library/Developer/Xcode/DerivedData`
   - 或者添加 Xcode 本身

#### 解决方法3: 创建发布版本

```bash
cd macos
swift build -c release
```

发布版本的路径更稳定：
```
macos/.build/release/App
```

#### 验证快捷键

**测试快捷键是否生效**:

1. **⌘K** - 打开 Command Bar
2. **⌥⇧R** - 静默导入剪贴板
3. **⌥⇧D** - 导入剪贴板并显示
4. **⌥⇧V** - 召唤面板
5. **⌥⇧S** - 搜索

如果不生效，检查：
- [ ] 辅助功能权限已授予
- [ ] HotkeyService 正确初始化（查看控制台日志）
- [ ] 没有其他 App 占用相同快捷键

---

## 完整测试流程

### 1. 启动后端

```bash
# 终端1: 启动后端
cd /Users/wangyixiao/WorkSpace/readless
./start-backend.sh

# 等待看到:
# ✅ Starting FastAPI server on http://localhost:8000
```

### 2. 运行 macOS App

```bash
# 终端2: 运行App
cd macos
swift run
```

或在 Xcode 中按 ⌘R

### 3. 测试导入功能

1. **复制一段长文本**（>100字符）
2. **按 ⌘K** 打开 Command Bar（应自动激活到前台）
3. **粘贴内容** ⌘V
4. **看到2个选项**:
   - Import this content (Enter)
   - Search for similar content (⌘↩)
5. **按 Enter** 导入
6. **等待处理**（应该不会报错）
7. **查看左侧列表**，新内容应出现

---

## 开发建议

### 方案A: 完整开发环境（推荐）

```bash
# 窗口1: 后端
cd /Users/wangyixiao/WorkSpace/readless/backend
source venv/bin/activate
uvicorn app.main:app --reload

# 窗口2: 前端
cd /Users/wangyixiao/WorkSpace/readless/macos
swift run

# 或在Xcode中运行
```

### 方案B: Docker 后端（可选）

```bash
cd /Users/wangyixiao/WorkSpace/readless/backend
docker-compose up -d
```

---

## 错误排查清单

### 导入失败时检查

- [ ] 后端是否运行？`curl http://localhost:8000/health`
- [ ] .env 文件是否配置？`cat backend/.env`
- [ ] OpenAI API key 是否有效？
- [ ] 数据库是否运行？（PostgreSQL）

### 快捷键不生效检查

- [ ] 辅助功能权限已授予
- [ ] App 路径在权限列表中
- [ ] 查看控制台日志：`[Readless] Hotkey ⌥⇧R: registered`
- [ ] 重启 App 试试

### 窗口不激活检查

- [ ] 是否在 Xcode 调试模式？（可能有延迟）
- [ ] 尝试 `NSApp.activate(ignoringOtherApps: true)`（已修复）

---

## 日志查看

### 查看实时日志

```bash
# 在运行App的终端查看输出
# 应该看到：
[Readless] Hotkey ⌘K detected
[Readless] Command Bar hotkey (⌘K): registered
```

### 查看系统日志

```bash
log stream --predicate 'process == "App"' --level debug
```

---

## 快速参考

### 后端命令

```bash
# 启动
./start-backend.sh

# 手动启动
cd backend && uvicorn app.main:app --reload

# 检查健康
curl http://localhost:8000/health

# 查看API文档
open http://localhost:8000/docs
```

### 前端命令

```bash
# Swift构建
cd macos && swift build

# 运行
swift run

# 发布版本
swift build -c release
```

---

## 常见问题FAQ

**Q: 每次都要启动后端很麻烦？**

A: 可以设置后端自动启动：
1. 创建 LaunchAgent（macOS 自启动）
2. 或使用 Docker `docker-compose up -d`

**Q: 能不能不依赖后端？**

A: 目前导入功能需要后端进行内容提取和摘要生成。未来可以考虑：
- 本地 LLM 支持（Ollama）
- 离线模式（仅保存原文）

**Q: 辅助功能权限太烦人？**

A: 这是 macOS 安全要求。解决方案：
1. 使用发布版本（路径固定）
2. 或等待正式打包签名的版本

---

**更新日期**: 2026-03-01
**相关文档**:
- `COMMAND_BAR_USAGE.md` - 使用指南
- `COMMAND_BAR_TESTING.md` - 测试指南
- `docs/plans/2026-03-01-command-bar-ui-complete-design.md` - 设计文档
