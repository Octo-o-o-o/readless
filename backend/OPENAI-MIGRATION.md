# OpenAI SDK 迁移说明

## 概述

Readless后端已从 **Anthropic SDK** 迁移到 **OpenAI SDK**。

---

## 🔄 主要变化

### 1. 环境变量更新

#### ❌ 旧配置（Anthropic）
```bash
ANTHROPIC_API_KEY=sk-ant-api03-xxxxx
```

#### ✅ 新配置（OpenAI）
```bash
OPENAI_API_KEY=sk-xxxxx

# 可选配置
OPENAI_API_BASE=https://api.openai.com/v1
OPENAI_MODEL=gpt-4-turbo-preview
```

### 2. API密钥获取

**OpenAI API Key获取**：
1. 访问 https://platform.openai.com/api-keys
2. 登录账号
3. 点击 "Create new secret key"
4. 输入名称，复制密钥

### 3. 模型选择

推荐模型配置：

| 场景 | 推荐模型 | 原因 |
|------|---------|------|
| **生产环境** | `gpt-4o` | 性能优秀，成本适中 |
| **开发测试** | `gpt-3.5-turbo` | 快速响应，成本低 |
| **高质量** | `gpt-4-turbo-preview` | 最高质量输出 |

---

## 💰 成本对比

### Anthropic Claude (旧)
- Claude Sonnet 4.5:
  - 输入: $3/百万tokens
  - 输出: $15/百万tokens

### OpenAI (新)

| 模型 | 输入价格 | 输出价格 | 适用场景 |
|------|---------|---------|---------|
| GPT-4o | $5/M tokens | $15/M tokens | 平衡性能和成本 ✅ |
| GPT-4 Turbo | $10/M tokens | $30/M tokens | 高质量输出 |
| GPT-3.5 Turbo | $0.5/M tokens | $1.5/M tokens | 开发测试 |

**示例**：处理一篇5000字文章（约1000 tokens）
- GPT-4o: 约 $0.005-0.015
- GPT-3.5 Turbo: 约 $0.001-0.002

---

## 🔧 配置步骤

### 步骤1: 获取OpenAI API Key

```bash
# 访问 https://platform.openai.com/api-keys
# 创建新密钥并复制
```

### 步骤2: 更新 .env 配置

```bash
cd /Users/wangyixiao/WorkSpace/readless/backend

# 编辑.env文件
nano .env
```

添加/修改以下配置：
```bash
# 删除或注释掉旧的Anthropic配置
# ANTHROPIC_API_KEY=sk-ant-api03-xxxxx

# 添加OpenAI配置
OPENAI_API_KEY=sk-你的OpenAI密钥

# 可选：指定默认模型
OPENAI_MODEL=gpt-4o

# 可选：如使用代理或Azure OpenAI
# OPENAI_API_BASE=https://your-proxy.com/v1
```

### 步骤3: 验证配置

重新部署后测试：
```bash
curl -X POST https://readless.cc/api/v1/content/ \
  -H 'Content-Type: application/json' \
  -d '{
    "source_type": "text",
    "body": "测试OpenAI API集成。\n\n这是第一段内容。\n\n这是第二段内容。"
  }'
```

应返回包含 `l0_summary` 和 `l1_outline` 的JSON响应。

---

## 🌐 支持的OpenAI兼容服务

除了官方OpenAI API，还支持以下兼容服务：

### 1. Azure OpenAI
```bash
OPENAI_API_KEY=你的Azure密钥
OPENAI_API_BASE=https://your-resource.openai.azure.com/
OPENAI_MODEL=gpt-4
```

### 2. 自托管或代理服务
```bash
OPENAI_API_KEY=你的密钥
OPENAI_API_BASE=https://your-proxy-service.com/v1
```

### 3. 其他兼容服务
任何符合OpenAI API规范的服务都可以使用，只需配置 `OPENAI_API_BASE`。

---

## 📝 代码变化说明

### Python依赖更新

#### 旧依赖 (pyproject.toml)
```toml
dependencies = [
    "anthropic>=0.43.0",
    # ...
]
```

#### 新依赖
```toml
dependencies = [
    "openai>=1.10.0",
    # ...
]
```

### 代码调用示例

#### 旧代码（Anthropic）
```python
import anthropic

client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

message = client.messages.create(
    model="claude-sonnet-4-5-20250514",
    max_tokens=2000,
    messages=[{
        "role": "user",
        "content": prompt
    }]
)

response = message.content[0].text
```

#### 新代码（OpenAI）
```python
from openai import OpenAI

client = OpenAI(api_key=settings.openai_api_key)

response = client.chat.completions.create(
    model=settings.openai_model or "gpt-4o",
    max_tokens=2000,
    messages=[{
        "role": "user",
        "content": prompt
    }]
)

result = response.choices[0].message.content
```

---

## ⚠️ 迁移注意事项

### 1. Prompt格式差异

**Claude特性**（不再可用）：
- XML格式的prompt结构
- 特定的思考链提示

**建议**：
- 使用标准的对话格式
- 简化prompt结构
- 通过system message设置角色

### 2. 响应格式

- Claude和GPT的响应风格略有不同
- 可能需要微调prompt以获得期望的输出格式
- 建议使用JSON mode确保结构化输出

### 3. Token计数

- OpenAI和Anthropic的token计数方式不同
- 中文内容：GPT通常使用更多tokens
- 建议监控实际使用情况调整max_tokens

### 4. 速率限制

OpenAI默认速率限制：
- 免费试用：3 RPM (requests per minute)
- Tier 1: 3,500 RPM
- Tier 2+: 根据付费等级递增

建议实施请求队列和重试机制。

---

## 🔍 功能对比

| 功能 | Anthropic Claude | OpenAI GPT |
|------|-----------------|-----------|
| 上下文窗口 | 200k tokens | 128k tokens (GPT-4 Turbo) |
| 函数调用 | ✅ Tool use | ✅ Function calling |
| JSON模式 | 部分支持 | ✅ 完整支持 |
| 视觉理解 | Claude 3支持 | ✅ GPT-4V/4o支持 |
| 流式输出 | ✅ | ✅ |
| 批处理API | ❌ | ✅ |

---

## 💡 优化建议

### 1. 成本优化

```python
# 根据任务复杂度选择模型
def get_model_for_task(task_type):
    if task_type == "simple_summary":
        return "gpt-3.5-turbo"  # 低成本
    elif task_type == "complex_analysis":
        return "gpt-4o"  # 平衡
    else:
        return "gpt-4-turbo-preview"  # 高质量
```

### 2. 响应缓存

```python
# 对相同内容的请求使用缓存
import hashlib

def get_cache_key(content):
    return hashlib.md5(content.encode()).hexdigest()

# 检查缓存，避免重复调用API
```

### 3. 批处理

对于非实时任务，使用OpenAI Batch API降低成本50%。

---

## ❓ 常见问题

### Q1: 为什么迁移到OpenAI？

**A**:
- 更好的生态支持和工具集成
- 更灵活的模型选择（GPT-4o、GPT-3.5等）
- 支持更多兼容服务（Azure、自托管等）
- 批处理API等企业功能

### Q2: 需要重新训练或调整吗？

**A**:
- 不需要重新训练
- 可能需要微调prompt以优化输出质量
- 建议测试关键功能确保输出符合预期

### Q3: 可以同时支持两种SDK吗？

**A**:
- 技术上可行，但会增加维护复杂度
- 建议专注于OpenAI生态
- 如有需要，可以通过环境变量切换

### Q4: API费用如何计费？

**A**:
- OpenAI按使用量计费，每月出账单
- 可在 https://platform.openai.com/usage 查看使用情况
- 建议设置使用限额避免超支

---

## 📚 参考资源

- [OpenAI API文档](https://platform.openai.com/docs/api-reference)
- [OpenAI定价](https://openai.com/pricing)
- [OpenAI Python SDK](https://github.com/openai/openai-python)
- [GPT最佳实践](https://platform.openai.com/docs/guides/prompt-engineering)

---

迁移完成后，Readless将获得更好的灵活性和成本优势！🚀
