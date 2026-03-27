# .env 配置指南

## ✅ 配置检查清单

### 1️⃣ 数据库配置

#### DATABASE_URL
```bash
DATABASE_URL=postgresql+asyncpg://readless:readless@db:5432/readless
```

**❗ 重要说明**：
- ✅ **端口使用5432是正确的**（不需要改成5433）
- 原因：这是**容器内部**的连接地址
- `db` 是docker-compose中定义的服务名
- Docker容器之间通过内部网络通信，使用内部端口5432
- 只有从**宿主机**访问时才需要用5433端口

**端口说明**：
```
容器内部（API → DB）: db:5432     ✅ 正确
宿主机访问DB:        127.0.0.1:5433  ✅ 避免冲突
```

#### POSTGRES_PASSWORD
```bash
POSTGRES_PASSWORD=你的强密码
```

⚠️ **必须修改**：
- 不要使用默认密码
- 建议至少16位，包含大小写字母、数字、特殊字符
- 示例：`P@ssw0rd_2026_Readless!`

---

### 2️⃣ AI服务配置

#### OPENAI_API_KEY
```bash
OPENAI_API_KEY=sk-xxxxx
```

**获取步骤**：
1. 访问 https://platform.openai.com/api-keys
2. 登录/注册OpenAI账号
3. 点击 "Create new secret key"
4. 输入密钥名称（如：readless-backend）
5. 复制密钥（只显示一次，请立即保存）

**用途**：
- L0摘要生成
- L1 outline生成
- L2详细展开
- L3追问回答
- 搜索Agent

**推荐模型**：
- GPT-4 Turbo: 性能优秀，成本适中
- GPT-4o: 最新多模态模型
- GPT-3.5 Turbo: 快速且经济

**价格**（参考，2024年）：
- GPT-4 Turbo: $10/百万输入token, $30/百万输出token
- GPT-4o: $5/百万输入token, $15/百万输出token
- GPT-3.5 Turbo: $0.5/百万输入token, $1.5/百万输出token
- 一篇5000字文章约1000 tokens，GPT-4o成本约$0.005-0.015

#### 可选配置

**OPENAI_API_BASE** (可选)
```bash
OPENAI_API_BASE=https://api.openai.com/v1
```
如使用Azure OpenAI、OpenAI兼容服务或代理，修改此项。

**OPENAI_MODEL** (可选)
```bash
OPENAI_MODEL=gpt-4-turbo-preview
```
默认模型配置，可选值：
- `gpt-4-turbo-preview`
- `gpt-4o`
- `gpt-3.5-turbo`

---

### 3️⃣ 认证服务

#### CLERK_SECRET_KEY
```bash
CLERK_SECRET_KEY=sk_live_xxxxx
```

**获取步骤**：
1. 访问 https://clerk.com/
2. 创建应用
3. 进入 API Keys
4. 复制 "Secret Key"

**用途**：
- 用户认证
- Session管理
- 用户信息获取

**注意**：
- 开发环境用 `sk_test_xxx`
- 生产环境用 `sk_live_xxx`

---

### 4️⃣ 对象存储（Cloudflare R2）

#### R2配置
```bash
R2_ENDPOINT=https://账户ID.r2.cloudflarestorage.com
R2_ACCESS_KEY=xxxxx
R2_SECRET_KEY=xxxxx
R2_BUCKET=readless
```

**获取步骤**：

1. **获取Account ID**
   - 登录 https://dash.cloudflare.com/
   - 右上角账户 → Account ID

2. **创建R2 Bucket**
   - 进入 R2 → Create bucket
   - 名称：`readless`
   - 区域：Automatic

3. **创建API Token**
   - R2 → Manage R2 API Tokens
   - 点击 "Create API token"
   - 权限：Admin Read & Write
   - 复制 Access Key ID 和 Secret Access Key

**Endpoint格式**：
```
https://[你的账户ID].r2.cloudflarestorage.com
```

**用途**：
- 存储播客音频文件
- 存储用户上传的PDF/图片
- 存储处理后的内容

**成本**：
- 免费额度：10GB存储 + 每月10万次请求
- 超出后：$0.015/GB/月

---

### 5️⃣ 语音合成

#### ELEVENLABS_API_KEY
```bash
ELEVENLABS_API_KEY=xxxxx
```

**获取步骤**：
1. 访问 https://elevenlabs.io/
2. 注册账号
3. 进入 Profile → API Keys
4. 创建新密钥

**用途**：
- 生成AI播客对话
- Text to Dialogue功能

**价格**（参考）：
- 免费：10,000字符/月
- Starter: $5/月，30,000字符
- Creator: $22/月，100,000字符

---

### 6️⃣ 其他配置

#### DOMAIN
```bash
DOMAIN=readless.cc
```
✅ 已正确配置，无需修改

#### CORS_ORIGINS
```bash
# 生产环境（推荐）
CORS_ORIGINS=["https://readless.cc"]

# 开发环境
CORS_ORIGINS=["https://readless.cc","http://localhost:3000"]

# 允许所有（不推荐生产环境）
CORS_ORIGINS=["*"]
```

**说明**：
- 控制哪些域名可以访问API
- 生产环境应限制为具体域名
- 开发时可以加上本地地址

---

## 📋 配置步骤

### 方式1：复制模板文件（推荐）

```bash
cd /Users/wangyixiao/WorkSpace/readless/backend

# 复制模板
cp .env.example .env

# 编辑配置
nano .env

# 或使用VSCode编辑
code .env
```

### 方式2：直接创建

```bash
cat > backend/.env << 'EOF'
DATABASE_URL=postgresql+asyncpg://readless:readless@db:5432/readless
POSTGRES_PASSWORD=你的强密码

OPENAI_API_KEY=sk-你的OpenAI密钥
CLERK_SECRET_KEY=sk_live_你的密钥

R2_ENDPOINT=https://你的账户ID.r2.cloudflarestorage.com
R2_ACCESS_KEY=你的AccessKey
R2_SECRET_KEY=你的SecretKey
R2_BUCKET=readless

ELEVENLABS_API_KEY=你的密钥

DOMAIN=readless.cc
CORS_ORIGINS=["https://readless.cc"]
EOF
```

---

## ✅ 配置验证

### 检查配置文件
```bash
# 查看配置（不会显示密钥值）
cat backend/.env | grep -E '^[A-Z]' | cut -d= -f1

# 应该显示：
# DATABASE_URL
# POSTGRES_PASSWORD
# ANTHROPIC_API_KEY
# CLERK_SECRET_KEY
# R2_ENDPOINT
# R2_ACCESS_KEY
# R2_SECRET_KEY
# R2_BUCKET
# ELEVENLABS_API_KEY
# DOMAIN
# CORS_ORIGINS
```

### 检查必填项
```bash
# 检查是否有占位符未替换
cat backend/.env | grep -E 'xxxxx|changeme|你的'

# 如果有输出，说明还有未配置的项
```

---

## 🔒 安全建议

1. **不要提交到Git**
   - `.env` 文件已在 `.gitignore` 中
   - 确认：`git status` 不应显示 `.env`

2. **定期轮换密钥**
   - API密钥建议每3-6个月更换
   - 数据库密码定期更新

3. **最小权限原则**
   - R2 API Token只给必要的读写权限
   - 管理后台和邮件服务只保留最小必要权限

4. **监控使用量**
   - 定期检查OpenAI兼容接口、ElevenLabs使用量
   - 设置成本告警

---

## ❓ 常见问题

### Q1: DATABASE_URL中的端口要改成5433吗？

**A**: ❌ **不需要**！

- 容器内部通信用 `db:5432`（正确）
- 只有从宿主机连接时才用 `127.0.0.1:5433`
- 例如使用 `psql` 或数据库工具时：
  ```bash
  # 从宿主机连接
  psql -h 127.0.0.1 -p 5433 -U readless -d readless
  ```

### Q2: 当前JWT认证可以替换成其他认证服务吗？

**A**: 可以，可选方案：
- Auth0
- Supabase Auth
- NextAuth.js
- 自建JWT认证

需要修改 `backend/app/routers/content.py` 中的认证中间件。

### Q3: 可以不配置ElevenLabs吗？

**A**: 可以，如果不需要播客功能：
- 留空或注释掉该行
- 播客生成接口会返回错误
- 其他功能不受影响

### Q4: R2可以用AWS S3替代吗？

**A**: 可以，修改 `backend/app/services/storage.py`：
```python
# 使用S3
self.s3 = boto3.client(
    "s3",
    endpoint_url="https://s3.amazonaws.com",  # 或其他S3兼容服务
    aws_access_key_id=settings.s3_access_key,
    aws_secret_access_key=settings.s3_secret_key,
)
```

---

## 📊 最小配置（仅核心功能）

如果只想测试核心的摘要功能，最少需要：

```bash
DATABASE_URL=postgresql+asyncpg://readless:readless@db:5432/readless
POSTGRES_PASSWORD=你的密码
OPENAI_API_KEY=sk-你的OpenAI密钥
DOMAIN=readless.cc
CORS_ORIGINS=["*"]
```

其他服务可以暂时留空，后续需要时再配置。

---

配置完成后，可以开始部署后端服务了！🚀
