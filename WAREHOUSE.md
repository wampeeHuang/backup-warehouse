# 备份仓库宪法

## 定位

`F:\warehouse\` 是本机所有备份的统一入口。一个文件保险箱，不是数据库。

核心理念来自 Karpathy inbox 模式：**人类只往 inbox 扔东西，AI 按 mtime 日期归档入库。** store/ 人可直接翻阅，和普通文件夹一样。

## 人类页面

| 想做什么 | 怎么做 |
|----------|--------|
| 备份东西 | 扔进 `F:\warehouse\inbox\` |
| 通知 AI 消化 | "存一下 inbox" |
| 翻看备份 | 直接打开 `F:\warehouse\store\`，按日期找 |
| 找文件 | `find.ps1 关键词` |
| 检查仓库健康 | `check.ps1` |

你只需要认识 `inbox\`（放东西）和 `store\`（找东西）两个文件夹。

## AI 页面

### save.ps1 — 消化 inbox

```
对 inbox 中每个文件：
  1. 过滤（warehouseignore + 元数据文件）
  2. 取 mtime 确定归档日期 → store/YYYY-MM-DD/
  3. 计算 SHA256
  4. 已有同 hash 文件 → 硬链接（去重，不占空间）
  5. 没有 → 复制到 store/YYYY-MM-DD/原相对路径/
  6. 重算 store 副本 SHA256 比对
  7. 一致 → 写 index.jsonl + 删 inbox 源
  8. 不一致 → 报错，保留 inbox 源
```

**验完才入库，不验不删源。**

### find.ps1 — 搜索

grep `index.jsonl` 全部字段。输出 mtime | store路径 | 大小 | hash。

### check.ps1 — 验完整性

```
1. 统计 index 唯一 hash 数 vs store/ 实际文件数
2. 随机抽 N 个文件重算 SHA256 与 index 记录比对
3. 异常 → 仓库根目录生成 ATTENTION.md
```

## 存储规则

- 文件按 **mtime 日期** 归档：`store/YYYY-MM-DD/原始相对路径/`
- **去重靠硬链接**：同一 hash 只存一份实体，其他出现位置用 Windows 硬链接
- `index.jsonl` 是唯一索引，一行一个文件记录，新记录追加在末尾
- 删一个硬链接不影响其他指向同一实体的入口

## index.jsonl 格式

```jsonl
{"hash":"sha256:ab3f123...","path":"claude-sessions/backups/2026-06-15/session.jsonl","size":1234,"mtime":"2026-06-15T10:30:00","inbox_at":"2026-06-19T14:22:00","ext":".jsonl"}
```

- `path` 相对于 `store/YYYY-MM-DD/`
- `mtime` 决定文件在哪个日期文件夹下
- `inbox_at` 是消化入库的时间

## 过滤规则

`_config/warehouseignore` 定义，每行一个模式。命中则不入库。

## 红线

- 不验不删：store 副本 SHA256 验证通过前，绝不删除 inbox 源文件
- 不手动编辑 `index.jsonl`
- 不直接在 `store/` 下修改文件（改了 check 会报错）
- 不在仓库目录内存放非备份来源的文件
