# 缓存管理和搜索模式

## 功能概述

本次更新实现了智能缓存管理和可配置的搜索模式，优化了性能和用户体验。

## ✨ 新功能

### 1. 展开内容缓存优化

**问题**：之前每次展开/折叠大纲点时都会调用 API，造成不必要的网络请求。

**解决方案**：分离缓存和展开状态
- **缓存** (`cachedDetails`): 永久保存展开内容，切换 content 时才清空
- **展开状态** (`expandedIndices`): 仅记录哪些点当前是展开的

**效果**：
```
第一次展开 ¶1 → 调用 API ✅ → 存入缓存
折叠 ¶1 → 仅更新展开状态 ⚡
再次展开 ¶1 → 从缓存读取，无需 API ⚡⚡⚡
```

### 2. 缓存管理系统

**位置**：`macos/Sources/Storage/CacheManager.swift`

**功能**：
- ✅ **缓存大小限制**
  - 默认：4096 MB (4 GB)
  - 最小：50 MB
  - 最大：无限制
  - 预留空间：50 MB 缓冲

- ✅ **LRU 驱逐策略**
  - 当缓存超过限制时，自动删除最久未访问的内容
  - 基于 `last_accessed_at` 时间戳

- ✅ **缓存统计**
  - 当前使用量
  - 可用空间
  - 缓存项数量
  - 使用百分比

- ✅ **清理功能**
  - 清除所有缓存
  - 清除 30 天以上未访问的缓存

### 3. 数据库扩展 (v3 Migration)

新增表和列以支持完整的本地缓存：

```sql
-- 新增列
ALTER TABLE contents ADD COLUMN last_accessed_at DATETIME;  -- LRU
ALTER TABLE contents ADD COLUMN full_text TEXT;              -- 完整文本

-- 新增表：段落数据
CREATE TABLE paragraphs (
    id TEXT PRIMARY KEY,
    content_id TEXT NOT NULL,
    anchor_id TEXT NOT NULL,
    text TEXT NOT NULL,
    position INTEGER NOT NULL,
    FOREIGN KEY (content_id) REFERENCES contents(id) ON DELETE CASCADE
);

-- 新增表：展开详情缓存
CREATE TABLE expanded_details (
    content_id TEXT NOT NULL,
    point_index INTEGER NOT NULL,
    detail_text TEXT NOT NULL,
    cached_at DATETIME NOT NULL,
    PRIMARY KEY (content_id, point_index),
    FOREIGN KEY (content_id) REFERENCES contents(id) ON DELETE CASCADE
);

-- 新增 FTS5 虚拟表：全文搜索
CREATE VIRTUAL TABLE contents_fts USING fts5(
    title,
    full_text,
    l0_summary,
    content=contents,
    content_rowid=rowid
);
```

### 4. 搜索模式选择

**位置**：`macos/Sources/App/Views/Settings/CacheSettingsView.swift`

用户可以在设置中选择搜索模式，系统会**完全按照用户选择**执行，不降级。

#### 云端搜索 (Cloud Search)

**优点**：
- ✅ AI 语义理解（使用 OpenAI）
- ✅ 智能意图解析
- ✅ AI 结果排序
- ✅ 生成自然语言答案
- ✅ 搜索全部数据（不受本地缓存限制）

**缺点**：
- ❌ 需要网络连接
- ❌ 有网络延迟
- ❌ 消耗 API 额度

**实现**：
- 后端：PostgreSQL FTS (TSVECTOR + GIN index)
- AI Agent：`backend/app/services/search_agent.py`
- 流程：意图解析 → FTS 检索 → AI 排序 → 答案生成

#### 本地搜索 (Local Search)

**优点**：
- ✅ 完全离线可用
- ✅ 毫秒级响应速度
- ✅ 无 API 成本
- ✅ 隐私保护（数据不离开设备）

**缺点**：
- ❌ 需要本地缓存完整数据
- ❌ 搜索质量不如 AI（纯关键词匹配）
- ❌ 占用本地存储空间

**实现**：
- 数据库：SQLite FTS5 (BM25 ranking)
- 服务：`macos/Sources/Storage/LocalSearchService.swift`
- 流程：FTS5 查询 → BM25 排序 → 返回结果

### 5. 设置界面

**位置**：`macos/Sources/App/Views/Settings/CacheSettingsView.swift`

新增缓存和搜索设置页面：

**搜索设置**
- 搜索模式选择：云端 / 本地
- 模式说明和提示

**存储设置**
- 缓存大小滑块 (50 MB - 10 GB)
- 实时显示当前配置

**统计信息**
- 缓存使用进度条
- 已使用空间 / 可用空间
- 缓存项数量
- 使用百分比（超过 75% 显示橙色，超过 90% 显示红色）

**维护操作**
- 清除 30 天以上未访问的缓存
- 清除所有缓存（带确认对话框）

## 📁 文件结构

```
macos/Sources/
├── Core/Models/
│   └── SearchMode.swift          # 搜索模式枚举（云端/本地）
├── Storage/
│   ├── LocalDatabase.swift       # 数据库（新增 v3 migration）
│   ├── CacheManager.swift        # 缓存管理器
│   └── LocalSearchService.swift  # 本地 FTS5 搜索服务
├── App/
│   ├── ViewModels/
│   │   └── ReaderViewModel.swift # 修改：缓存/展开状态分离
│   ├── Services/
│   │   └── CommandBarService.swift # 修改：支持搜索模式切换
│   └── Views/Settings/
│       └── CacheSettingsView.swift # 新增：缓存和搜索设置 UI
```

## 🚀 使用方式

### 配置搜索模式

1. 打开设置界面
2. 在 "Search" 部分选择模式：
   - **Cloud Search**（默认）：使用 AI 搜索
   - **Local Search**：使用本地全文搜索

### 配置缓存大小

1. 打开设置界面
2. 在 "Storage" 部分调整滑块
3. 范围：50 MB - 10 GB
4. 默认：4096 MB (4 GB)

### 清理缓存

1. 打开设置界面
2. 在 "Maintenance" 部分：
   - **Clear Items Older Than 30 Days**：清理旧缓存
   - **Clear All Cache**：清空所有缓存（需确认）

## ⚙️ 配置存储

所有设置通过 `UserDefaults` 持久化：

```swift
// 搜索模式
UserDefaults.standard.string(forKey: "searchMode")  // "cloud" or "local"

// 缓存大小限制（字节）
UserDefaults.standard.object(forKey: "cacheSizeLimit") as? Int64
```

## 🔄 数据同步

**自动同步**（当使用本地搜索时）：
- 当缓存有足够空间（>50 MB）时
- 自动保存完整内容数据到本地
- 包括：title, full_text, l0_summary, paragraphs

**手动同步 API**：
```swift
let localSearch = LocalSearchService.shared
await localSearch.syncContent(content, fullText: "...", paragraphs: [...])
```

## 📊 性能对比

| 指标 | 云端搜索 | 本地搜索 |
|------|---------|---------|
| **响应时间** | ~500-2000ms | ~10-50ms |
| **离线可用** | ❌ | ✅ |
| **搜索质量** | ⭐⭐⭐⭐⭐ (AI) | ⭐⭐⭐ (关键词) |
| **存储占用** | 0 | ~100KB/item |
| **API 成本** | 有 | 无 |
| **隐私** | 中 | 高 |

## 🛠️ 开发者注意事项

### 展开缓存实现

```swift
// ❌ 错误实现（旧代码）
if expandedDetails[index] != nil {
    expandedDetails.removeValue(forKey: index)  // 删除缓存！
    return
}

// ✅ 正确实现（新代码）
if expandedIndices.contains(index) {
    expandedIndices.remove(index)  // 只改状态，保留缓存
    return
}

if cachedDetails[index] != nil {
    expandedIndices.insert(index)  // 从缓存读取
    return
}
```

### 添加新的可缓存数据

如果需要缓存其他类型的数据：

1. 在 `LocalDatabase` 中添加新表/列（新 migration）
2. 在 `CacheManager.evictIfNeeded()` 中添加清理逻辑
3. 更新缓存大小估算

### 实现本地搜索

```swift
let localSearch = LocalSearchService.shared
let result = try await localSearch.search(query: "keyword", limit: 20)

for item in result.results {
    print("\(item.title): \(item.snippet)")
}
```

## 🐛 已知问题

1. **缓存大小估算不精确**
   - 目前使用数据库文件大小
   - 实际占用可能包括 WAL 文件和临时文件

2. **FTS5 中文分词**
   - SQLite FTS5 对中文分词支持有限
   - 建议使用云端搜索获得更好的中文搜索体验

## 📝 TODO

- [ ] 实现自动缓存同步策略（后台定期同步）
- [ ] 优化 FTS5 中文分词（可能需要外部分词器）
- [ ] 添加缓存预热功能（首次启动时批量下载）
- [ ] 缓存压缩（gzip full_text）
- [ ] 缓存健康检查和修复工具

## 🔗 相关文档

- [CLAUDE.md](CLAUDE.md) - 项目总览
- [后端搜索实现](backend/app/services/search_agent.py)
- [数据库 Schema](macos/Sources/Storage/LocalDatabase.swift)
