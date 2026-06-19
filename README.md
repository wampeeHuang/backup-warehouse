# Backup Warehouse

**文件保险箱，不是数据库。**

把备份管理变成"扔进 inbox，走人"——人类零认知负担的备份仓库。灵感来自 Andrej Karpathy 的知识管理 inbox 机制。

---

## 任何 AI 读完本文档应该能：

1. 理解这套备份哲学（为什么这么设计）
2. 知道人类怎么用（inbox 一个入口）
3. 知道 AI 怎么操作（save / find / check 三个命令）
4. 重现部署这套仓库

---

## 哲学

### 人类只需要一个文件夹

```
人把文件扔进 inbox/ → AI 消化入库 → 人类回来看 receipt
```

人类不记命令、不打标签、不关心存储结构。inbox 是唯一需要知道的地方。

### 内容寻址去重

文件按 SHA256 哈希存储。两个文件内容相同 → 同一份存储 → 不同的 index 记录指向同一位置。

下次备份 80% 的文件没变 → 80% 被去重 → 只存 20% 新内容。

### 验完才入库，不验不删源

```
inbox 文件 → 算 SHA256 → 复制到 store/ → 重算 store 副本 → 
→ SHA256 一致 ✅ → 写 index + 删 inbox 副本
→ SHA256 不一致 🚨 → 报错 + 保留 inbox 副本（不丢数据）
```

没有中间状态。文件要么在 inbox（未入库）要么在 store（已入库），切换点就是验证通过那一刻。

---

## 目录结构

```
backup-warehouse/
├── README.md            ← 你正在读的
├── WAREHOUSE.md         ← 仓库宪法
├── save.ps1             ← 消化 inbox（核心脚本）
├── find.ps1             ← 搜索索引
├── check.ps1            ← 完整性校验
├── index.jsonl          ← 唯一索引（一行一文件）
├── inbox/               ← 人类唯一界面
├── store/               ← 内容寻址存储
│   └── sha256/          ← SHA256 前2位分桶
├── _config/
│   └── warehouseignore  ← 过滤规则
├── _runtime/            ← 运行时临时文件
└── docs/
    └── diagram.svg      ← 流程图
```

---

## 三个脚本

### save.ps1 — 消化 inbox

```powershell
.\save.ps1
```

对 inbox 中每个文件：
1. 命中 `_config/warehouseignore` → 跳过
2. 计算 SHA256
3. hash 已存在于 `store/` → 去重，只写 `index.jsonl` 新行，删 inbox 副本
4. hash 不存在 → 复制到 `store/sha256/{前2位}/{hash}`
5. 重算 store 副本 SHA256 做比对
6. 一致 → 写 `index.jsonl` 新行，删 inbox 副本
7. 不一致 → 报错，保留 inbox 副本

输出示例：
```
扫描 127 个 | 新存 23 个 | 去重 104 个 | 跳过 15 个 | 异常 0 个
```

### find.ps1 — 搜索

```powershell
.\find.ps1 claude-session
.\find.ps1 jsonl
.\find.ps1 evopearl
```

grep `index.jsonl` 所有字段，输出匹配行。

### check.ps1 — 验完整性

```powershell
.\check.ps1
```

1. 统计 `index.jsonl` 唯一 hash 数 vs `store/` 实际文件数
2. 随机抽 10 个文件重算 SHA256 与文件名比对
3. 一致 → 通过
4. 不一致 → 仓库根目录生成 `ATTENTION.md`

---

## index.jsonl 格式

```jsonl
{"hash":"sha256:ab3f123...","path":"C:/Users/.../file.jsonl","size":1234,"mtime":"2026-06-15T10:30:00","inbox_at":"2026-06-19T14:22:00","ext":".jsonl"}
```

新记录追加在末尾，最新的在最下面。`tail` 即看最新，`grep` 搜全部。

---

## 自动化

| 触发方式 | 做什么 |
|----------|--------|
| 人对 AI 说"存一下" | AI 跑 `save.ps1` |
| 定时任务 | 跑 `save.ps1`（兜底消化 inbox） |
| 定时任务 | 跑 `check.ps1`（验完整性） |

---

## 人类操作速记

| 想做什么 | 怎么做 |
|----------|--------|
| 备份东西 | 扔进 `inbox/` |
| 通知 AI 消化 | "存一下" / "消化 inbox" |
| 找文件 | `find.ps1 关键词` |
| 取回文件 | 根据 find 结果，从 `store/sha256/` 复制 |
| 检查健康 | `check.ps1` |

---

## 部署到你的机器

### 1. 克隆仓库
```bash
git clone <repo-url> F:\warehouse
```

### 2. 注册定时任务（可选）
两个 Task Scheduler 任务：
- `Warehouse Save` — 兜底消化 inbox（频率按需）
- `Warehouse Check` — 验完整性（频率按需）

### 3. 告诉家人 / 未来的自己
"想备份的东西扔进 `F:\warehouse\inbox\` 就行。"

---

## 设计原则

- **不是数据库**：没有事务、WAL、锁、回滚
- **不是物流仓库**：没有批次追踪、波次管理
- **三个动作**：存（save）、查（find）、验（check）
- **零依赖**：纯 PowerShell，Windows 内置
- **内容自验证**：文件名即 SHA256，损坏自检
