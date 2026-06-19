# 备份仓库宪法

## 定位

`F:\warehouse\` 是本机所有备份的统一入口。一个文件保险箱，不是数据库。

核心理念来自 Karpathy inbox 模式：**人类只往 inbox 扔东西，AI 负责消化入库。** 人类不需要知道仓库内部怎么组织。

## 人类页面

| 想做什么 | 怎么做 |
|----------|--------|
| 备份东西 | 扔进 `F:\warehouse\inbox\` |
| 通知 AI 消化 | "存一下" |
| 找文件 | `find.ps1 关键词` |
| 取回文件 | 从 `store/sha256/xx/hash` 复制到需要的地方 |
| 检查仓库健康 | `check.ps1` |

你只需要认识 `inbox\` 一个文件夹。剩下的 AI 管。

## AI 页面

### save.ps1 — 消化 inbox

对 inbox 中每个文件：过滤 → SHA256 → 去重 → 存 store → 验 → 写 index → 删 inbox 副本。

**验完才入库，不验不删源。**

```
inbox 文件 → SHA256 → copy to store/ → 重算 store 副本 SHA256 →
→ 一致：index 写一行 + 删 inbox 副本
→ 不一致：报错 + 保留 inbox 副本
```

### find.ps1 — 搜索

grep `index.jsonl` 全部字段。输出 hash | 路径 | 大小 | 时间。

### check.ps1 — 验完整性

统计 index 唯一 hash 数 vs store/ 实际文件数，随机抽 10 个重算 SHA256。
异常时在仓库根目录生成 `ATTENTION.md`。

## 存储规则

- 文件按 SHA256 存储：`store/sha256/{前2位}/{完整hash}`
- 同样内容只存一份，不同来源指向同一内容
- `index.jsonl` 是唯一索引，一行一文件，新记录追加在末尾

## index.jsonl 格式

```jsonl
{"hash":"sha256:...","path":"/原始/路径","size":1234,"mtime":"2026-06-15T10:30:00","inbox_at":"2026-06-19T14:22:00","ext":".jsonl"}
```

## 过滤规则

`_config/warehouseignore` 定义，每行一个 glob 模式。命中则不入库。

## 红线

- 不验不删：store 副本 SHA256 验证通过前，绝不删除 inbox 源文件
- 不直接动 `store/` 下的文件（内容寻址不可变）
- 不手动编辑 `index.jsonl`
- 不在仓库目录内存放非备份来源的文件
