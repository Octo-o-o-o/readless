# Command Bar UI Integration Plan

## 当前状态

✅ **已完成（Task 8-10）**：
- AIServiceConfig - AI配置系统
- UnifiedAIProvider - AI provider抽象
- InputModels - 数据模型
- InputParser - 输入解析器
- AICoordinator - 状态管理（存根）

❌ **缺失部分**：
- CommandBarView - UI界面
- CommandBarService - 业务逻辑
- HotkeyService集成 - 快捷键绑定
- App集成 - 主窗口显示

## 需要实现的组件

### 1. CommandBarView（UI层）

**文件**: `macos/Sources/App/Views/CommandBarView.swift`

**功能**：
- 浮动输入框（类似Spotlight）
- 实时搜索结果显示
- 键盘导航（↑↓选择，Enter执行，Esc关闭）
- Liquid Glass材质

**依赖**：
- LiquidGlassKit（材质）
- AICoordinator（状态）

### 2. CommandBarService（业务逻辑层）

**文件**: `macos/Sources/AIServices/CommandBar/CommandBarService.swift`

**功能**：
- 接收用户输入
- 调用InputParser解析
- 调用AI分析意图
- 执行对应操作（创建内容/搜索/生成播客）
- 更新AICoordinator状态

**流程**：
```
用户输入 → InputParser.parse()
         → IntentAnalyzer.analyze()（未实现）
         → ActionExecutor.execute()（未实现）
         → 返回结果
```

### 3. 快捷键集成

**修改文件**: `macos/Sources/App/Services/HotkeyService.swift`

**新增快捷键**：
```swift
extension KeyboardShortcuts.Name {
    static let commandBar = Self("commandBar", default: .init(.k, modifiers: [.command]))
}
```

**集成到AppDelegate**：
```swift
onCommandBar: {
    // 显示/隐藏Command Bar
    AICoordinator.shared.isCommandBarVisible.toggle()
}
```

### 4. 主窗口集成

**修改文件**: `macos/Sources/App/ReadlessApp.swift` 或主窗口

**添加**：
```swift
.overlay {
    if aiCoordinator.isCommandBarVisible {
        CommandBarView()
            .environment(aiCoordinator)
    }
}
```

## 实现步骤

### Step 1: 创建CommandBarView（UI）

**优先级**: 高
**工作量**: 2-3小时

1. 创建浮动窗口
2. 输入框 + 结果列表
3. 键盘导航
4. Liquid Glass样式

### Step 2: 快捷键绑定

**优先级**: 高
**工作量**: 30分钟

1. 添加快捷键定义
2. 在HotkeyService注册
3. 连接到AICoordinator

### Step 3: CommandBarService

**优先级**: 中
**工作量**: 4-6小时

1. 集成InputParser
2. 实现基础命令（创建内容、搜索）
3. 连接到ContentManager

### Step 4: 完整集成测试

**优先级**: 中
**工作量**: 1-2小时

1. 端到端测试
2. 性能优化
3. 错误处理

## 最小可用版本（MVP）

**目标**: 1天内实现基础可用版本

**范围**：
1. ✅ 基础CommandBarView（输入框 + 简单列表）
2. ✅ ⌘K快捷键
3. ✅ 基础命令支持：
   - 导入文本/URL
   - 搜索现有内容
4. ✅ 集成到主窗口

**后续增强**：
- AI意图分析
- 多模态支持（图片/PDF）
- 上下文建议
- 高级命令

## 技术细节

### CommandBarView设计

```swift
struct CommandBarView: View {
    @Environment(AICoordinator.self) var coordinator
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            // 输入框
            TextField("Type a command...", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding()

            // 结果列表
            if !coordinator.commandResults.isEmpty {
                ScrollView {
                    ForEach(coordinator.commandResults) { result in
                        CommandResultRow(result: result)
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}
```

### 快捷键处理

```swift
// HotkeyService.swift
case 40:  // K — Command Bar
    if mods == [.command] {
        print("[Readless] Hotkey ⌘K detected")
        onCommandBar()
        return true
    }
```

## 下一步行动

选择以下之一：

1. **Option A: 快速实现MVP**（推荐）
   - 1天完成基础可用版本
   - 先实现UI和快捷键
   - 后续迭代增强功能

2. **Option B: 完整实现所有功能**
   - 3-5天完成完整版本
   - 包含AI意图分析
   - 多模态支持

3. **Option C: 分阶段实现**
   - Phase 1: UI + 快捷键（今天）
   - Phase 2: 基础命令（明天）
   - Phase 3: AI增强（本周）

## 推荐路径

**建议选择 Option A (MVP)**：

1. **今天下午**: CommandBarView + ⌘K快捷键
2. **今天晚上**: 基础命令（导入文本、搜索）
3. **明天**: 优化和测试

这样你今晚就能看到可用的Command Bar！
