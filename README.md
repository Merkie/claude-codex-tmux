# claude-codex-tmux

Teach Claude Code, OpenAI Codex CLI, or another shell-capable agent to consult the other CLI
through a controlled, interactive tmux session—for PR review, code review, plan critique,
adversarial analysis, second opinions, and follow-up discussion.

## Canonical instructions

Give the agent [`SKILL.md`](./SKILL.md). It is the complete and only operational playbook.

> **The peer must always be the real interactive Claude Code or Codex CLI running inside tmux.**
> **Never use `claude -p`, `claude --print`, `codex exec`, `codex e`, `codex exec review`, or any
> other headless/non-interactive substitute.**

Example request:

```text
Talk to Claude and have it review my PR. Verify its important findings, report any disagreements,
and close the tmux session when you are done.
```

The peer always launches unrestricted — `codex --yolo` or `claude --dangerously-skip-permissions`.
No sandbox, approval, or plan-mode flags. Scope the peer through the prompt, not through flags.

The workflow uses raw foreground tmux commands, bounded waits, exact session ownership,
follow-up prompts in the same interactive conversation, and verified cleanup.
There is no helper shell script and no secondary or legacy playbook in this repository.
