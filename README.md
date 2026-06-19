# Backup Warehouse

**文件保险箱，不是数据库。**

人扔进 inbox，AI 按日期归档入库。store/ 和普通文件夹一样可以翻，去重靠硬链接不占空间，完整性靠 SHA256 校验。

灵感来自 Andrej Karpathy 的知识管理 inbox 机制。

---

## 任何 AI 读完本文档应该能：

1. 理解这套备份哲学（为什么这么设计）
2. 知道人类怎么用（inbox 扔，store 翻）
3. 知道 AI 怎么操作（save / find / check 三个命令）
4. 重现部署这套仓库

---

## 哲学

### 人只需要两个文件夹

```
inbox/  ← 扔东西进来
store/  ← 按日期翻备份

人不用记命令、不打标签、不关心去重怎么实现的。
inbox 是入口，store 是出口。
```

### 按 mtime 日期归档

文件自带修改时间（mtime），这是最自然的线索——"大概是上个月改的那个文件"比记住文件名靠谱。

每次消化时，取文件的 mtime 放进对应的日期文件夹：`store/YYYY-MM-DD/原始路径/`

不管什么时候消化，文件都归档到它真正"活着"的日期。一周消化一次完全没问题。

### 去重靠硬链接

同一内容只存一份实体，其他出现位置用 Windows 硬链接指向。不占额外磁盘空间。删一个不影响另一个。

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
├── README.md              ← 你正在读的
├── WAREHOUSE.md           ← 仓库宪法
├── save.ps1               ← 消化 inbox（核心脚本）
├── find.ps1               ← 搜索索引
├── check.ps1              ← 完整性校验
├── index.jsonl            ← 唯一索引（一行一文件）
├── inbox/                 ← 人类唯一入口
├── store/                 ← 按日期归档，人可翻阅
│   ├── 2026-06-15/        ← mtime 日期
│   │   └── ...            ← 原始目录结构保留
│   └── ...
├── _config/
│   └── warehouseignore    ← 过滤规则
├── _runtime/              ← 运行时临时文件
└── docs/
    └── diagram.svg        ← 流程图
```

---

## 三个脚本

### save.ps1 — 消化 inbox

```powershell
.\save.ps1
```

对 inbox 中每个文件：
1. 命中 `_config/warehouseignore` → 跳过
2. 取文件 mtime，确定归档日期 `store/YYYY-MM-DD/`
3. 计算 SHA256
4. 已有同 hash 文件 → 创建硬链接（去重），写 index，删 inbox 源
5. 没有 → 复制到 `store/YYYY-MM-DD/原相对路径/`
6. 重算 store 副本 SHA256 比对
7. 一致 → 写 index，删 inbox 源
8. 不一致 → 报错，保留 inbox 源

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

输出格式：`mtime | store/YYYY-MM-DD/path | size | hash`

### check.ps1 — 验完整性

```powershell
.\check.ps1
```

1. 统计 index 唯一 hash 数 vs store/ 实际文件数
2. 随机抽 10 个文件重算 SHA256 与 index 记录比对
3. 一致 → 通过
4. 不一致 → 仓库根目录生成 `ATTENTION.md`

---

## index.jsonl 格式

```jsonl
{"hash":"sha256:ab3f123...","path":"claude-sessions/backups/2026-06-15/session.jsonl","size":1234,"mtime":"2026-06-15T10:30:00","inbox_at":"2026-06-19T14:22:00","ext":".jsonl"}
```

- `path` 相对于 `store/YYYY-MM-DD/`
- `mtime` 决定文件在哪个日期文件夹下
- `inbox_at` 是消化入库的时间
- 新记录追加在末尾，`tail` 即看最新

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
| 翻看备份 | 打开 `store/`，按日期文件夹翻 |
| 找文件 | `find.ps1 关键词` |
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
"想备份的东西扔进 `F:\warehouse\inbox\`，想找的去 `F:\warehouse\store\` 翻。"

---

## 设计原则

- **不是数据库**：没有事务、WAL、锁、回滚
- **人可翻阅**：store/ 就是普通文件夹，按日期排
- **去重不占空间**：硬链接，同一内容只存一份
- **三个脚本**：存（save）、找（find）、验（check）
- **零依赖**：纯 PowerShell，Windows 内置
- **SHA256 验完整性**：不靠文件名辨识，靠内容校验
