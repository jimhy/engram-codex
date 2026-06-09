# engram-codex

[Engram](https://github.com/jimhy/engram) 仿人脑分层长期记忆系统的 **Codex 适配器**。让 [Codex](https://developers.openai.com/codex) 用上 engram:**会话开始注入记忆热索引、会话结束自动复盘巩固**,并提供一个 engram skill 让 agent 在该检索时**主动回溯记忆**。单 Rust 引擎二进制、零外部依赖。

## 安装

```bash
codex plugin marketplace add jimhy/engram-codex
codex plugin add engram@engram-codex
```

开 `codex`,首次会提示信任 engram 的 hook,同意即可。卸载:`codex plugin remove engram@engram-codex`。

## 干什么

| 对接点 | codex 机制 |
|---|---|
| 会话开始**注入热索引** | `SessionStart` hook → `engram hot-index` → 注入 `additionalContext` |
| 会话结束**复盘巩固** | `Stop` hook → `review-prepare` 算增量 → `codex exec` 无头复盘落库 |
| **主动检索**(agent) | `skills/engram/SKILL.md`:recall-first,被问"以前处理过 X 吗 / 还剩什么待办"先查记忆 |

记忆库与 Claude Code 版 engram **共用**(`~/.engram/general.redb` + 各项目 `<proj>/.engram/engram.redb`),两边记忆互通。

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

## 跨平台

- **Windows**:`.ps1`(已实测)
- **macOS / Linux**:`.sh`(`hooks.json` 用 `command`/`commandWindows` 分流)

## 与 Claude 适配器的关系

本仓库是 **Codex 专用**适配器,与 [engram 主项目](https://github.com/jimhy/engram)(Claude Code 插件)一比一对称、共用同一套引擎与记忆库。详细设计见 [`plugin/README.md`](plugin/README.md)。

## License

MIT
