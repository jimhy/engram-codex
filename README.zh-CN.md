# engram-codex

> [Engram](https://github.com/jimhy/engram) 仿人脑分层长期记忆系统的 **Codex 适配器**。会话开始注入相关记忆、会话结束自动复盘巩固、并提供一个 skill 让 agent 按需主动检索。单 Rust 二进制、零依赖、**与 Claude Code 版共用记忆库**。

[English](./README.md) | **中文**

---

## 安装

```bash
codex plugin marketplace add jimhy/engram-codex
codex plugin add engram@engram-codex
```

开 `codex`,首次提示时信任 engram 的 hook。卸载:`codex plugin remove engram@engram-codex`。

## 你会得到什么

| codex 机制 | 作用 |
|---|---|
| `SessionStart` hook | 经 `engram hot-index` → `additionalContext` 把**热索引**(相关记忆)注入上下文;并**补跑**上次会话未完成的巩固 |
| `Stop` hook | 起一个无头 `codex exec` 复盘者,只巩固**自上次水位线以来的增量**(写入新记忆、升降级、标记取代、合并) |
| engram **skill** | recall-first:被问"以前处理过 X 吗 / 这项目是什么 / 还剩什么待办"时,agent 先查记忆再翻代码 |

记忆库与 **Claude Code 版共用**(`~/.engram/general.redb` + 各项目 `<项目>/.engram/engram.redb`),两边记忆互通。

## 工作原理

引擎与 [engram](https://github.com/jimhy/engram) 同一套——分层、ACT-R 式活跃度、会遗忘(遗忘=降级不删)。完整模型见主项目。

| 层级 | 角色 |
|---|---|
| **L1** | "潜意识"——核心身份 / 全局偏好(几乎不忘) |
| **L2** | 重要、跨项目 |
| **L3** | 普通的通用笔记 |
| **L4** | 项目级,存于 `<项目>/.engram/engram.redb`,按 `.engram/` 锚点定位 |

## 结构

```
.agents/plugins/marketplace.json   codex marketplace 清单(source: ./plugin)
plugin/                            the codex plugin
  .codex-plugin/plugin.json        manifest
  hooks/hooks.json                 SessionStart/Stop,${PLUGIN_ROOT} 自定位
  scripts/                         codex-{session-start,stop-review,launch-reviewer}.{ps1,sh}
                                   + reviewer-prompt.md
  skills/engram/SKILL.md           engram agent 接口 + 判定 rubric
  bin/                             四平台引擎二进制
```

## 平台

- **Windows**:`.ps1`(已实测)
- **macOS / Linux**:`.sh`(`hooks.json` 用 `command` / `commandWindows` 分流)

## 与 Claude Code 适配器的差异

- **用 `Stop` 而非 `SessionEnd`**:codex 没有 `SessionEnd`;`Stop` 每回合触发,所以增量 ≥ `ENGRAM_REVIEW_MIN_LINES`(默认 40)才起复盘——不够则留 pending 给下次 `SessionStart` 的 catch-up 兜底。
- **`Stop` 的 stdout 必须是合法 JSON**:hook 固定回 `{}`。
- **复盘用 `codex exec`**(而非 `claude -p`),`ENGRAM_REVIEWER=1` 守卫递归。
- 注入 / 复盘 hook 只在**交互式 `codex` TUI** 触发——`codex exec`(非交互)不触发会话生命周期 hook。

## 配置

- `ENGRAM_REVIEW_MIN_LINES` —— 触发复盘所需的 transcript 增量行数(默认 `40`)。
- `ENGRAM_REVIEWER_CODEX` —— 复盘者启动的 codex 可执行文件(默认 `codex`)。
- `ENGRAM_REVIEWER_MODEL` —— 无头复盘者的模型覆盖。

## 许可证

MIT
