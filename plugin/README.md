# Engram × Codex Plugin

让 [Codex](https://developers.openai.com/codex) 用上 engram 分层长期记忆：**会话开始注入记忆热索引、会话结束自动复盘巩固**，并提供一个 engram skill 让 agent 在该检索时**主动回溯记忆**。

标准 **codex plugin**，走 codex marketplace 分发，与 Claude 适配器（`../../plugin/`）一比一对称。引擎、SKILL、reviewer-prompt 都打包在内，**零外部依赖**。

## 安装

发布后（GitHub 仓库带 `.agents/plugins/marketplace.json`）：
```bash
codex plugin marketplace add jimhy/engram
codex plugin add engram@engram          # 或在 codex 的 Plugin Directory 里 install
```

本地开发（指向含 `.agents/plugins/marketplace.json` 的仓库根）：
```bash
codex plugin marketplace add F:\ClaudeWorkspaces\engram
codex plugin add engram@engram
```

装到 `~/.codex/plugins/cache/engram/engram/<version>/`；codex 自动加载 `hooks/hooks.json` 并向 hook 注入 `PLUGIN_ROOT` 环境变量。卸载：`codex plugin remove engram@engram`。

## 四个对接点 → codex 机制

| engram 对接点 | codex 机制 |
|---|---|
| 会话开始**注入热索引** | `SessionStart` hook → `engram hot-index --emit json` → `hookSpecificOutput.additionalContext` |
| 会话结束**复盘巩固** | `Stop` hook → `review-prepare` 算增量 → `codex exec` 无头复盘落库 |
| **主动检索**（agent） | `skills/engram/SKILL.md`：recall-first，被问"以前处理过 X 吗/项目是什么/还剩什么"时先查记忆 |
| **项目定位** | `engram resolve`（`.engram/` 锚点，从 cwd 向上找） |

## 结构

```
adapters/codex/                 (plugin root = $PLUGIN_ROOT)
  .codex-plugin/plugin.json     manifest（name/version/skills/hooks/interface）
  hooks/hooks.json              SessionStart/Stop，command 用 ${PLUGIN_ROOT}，commandWindows 分流
  scripts/
    codex-session-start.ps1     注入热索引（cwd 锚定，不读 stdin）+ catchup
    codex-stop-review.ps1       review-prepare + 阈值去重 + 起复盘 + 回 {}
    codex-launch-reviewer.ps1   codex exec 无头复盘（detached）
    reviewer-prompt.md          复盘 prompt 模板（+ codex rollout 格式注脚）
  skills/engram/SKILL.md        engram agent 接口 + 判定 rubric
  bin/                          四平台引擎二进制
```

## 与 Claude 适配器的关键差异

1. **Stop 而非 SessionEnd**：codex 没有 SessionEnd，`Stop` 每回合触发 → 增量行数 ≥ 阈值（`ENGRAM_REVIEW_MIN_LINES`，默认 40）才起复盘，否则留 pending 给下次 `SessionStart` 的 `catchup-scan` 兜底。
2. **Stop 的 stdout 必须是合法 JSON**：脚本干完活固定回 `{}`。
3. **复盘用 `codex exec`** 而非 `claude -p`，prompt 走 stdin，`ENGRAM_REVIEWER=1` 守卫递归。
4. **注入/复盘 hook 只在交互式 `codex` TUI 生效**——`codex exec`（非交互）不触发会话生命周期 hook（已实测确认）。

## 跨平台

- **Windows**：`.ps1`（已实测）。
- **macOS / Linux**：`.sh`（待补 + 待在原生环境验证）。`hooks.json` 已用 `command`（bash 调 `.sh`）+ `commandWindows`（powershell 调 `.ps1`）分流。

## 交互式验证（需真实终端，工具环境跑不了 TUI）

1. 装好后，在一个有 `.engram/` 锚点的项目目录开 `codex`（交互式）。
2. 首次会提示**信任** engram 的 SessionStart/Stop hook → 同意。
3. 问它「你上下文里有 engram 记忆热索引吗？复述第一条」→ 验证注入是否进了上下文。
4. 让 agent 主动检索（"以前处理过 X 吗"）→ 验证 engram skill 是否激活。
5. 多聊几轮后退出 → 看 `~/.engram/codex/hook.log` 与 `~/.engram/codex/pending/`（增量 ≥ 阈值会起复盘）。
