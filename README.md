# claude-codex-tmux

Teach Claude Code, OpenAI Codex CLI, or another shell-capable agent to consult the other CLI
through a controlled, interactive tmux session — for PR review, code review, plan critique,
adversarial analysis, second opinions, and follow-up discussion.

## Install as an agent skill

The same [`SKILL.md`](./SKILL.md) works unchanged in Claude Code and Codex. It uses the shared
Agent Skills format and only the portable `name` and `description` frontmatter fields.

Prerequisites: install `tmux`, Claude Code, and Codex CLI, and authenticate both CLIs. Run the
commands below from the root of this cloned repository.

```bash
git clone https://github.com/Merkie/claude-codex-tmux.git
cd claude-codex-tmux
```

The following personal installation makes the skill available in every project for your user
account.

For Claude Code:

```bash
mkdir -p "$HOME/.claude/skills/claude-codex-tmux"
cp ./SKILL.md "$HOME/.claude/skills/claude-codex-tmux/SKILL.md"
```

For Codex:

```bash
mkdir -p "$HOME/.agents/skills/claude-codex-tmux"
cp ./SKILL.md "$HOME/.agents/skills/claude-codex-tmux/SKILL.md"
```

Codex normally detects the new skill automatically; restart it if the skill does not appear.
Claude Code detects changes inside an existing skills directory live, but may need a restart
when the top-level skills directory was created after the session started.

Invoke it as `/claude-codex-tmux` in Claude Code or `$claude-codex-tmux` in Codex. See the
[Claude Code skill documentation](https://code.claude.com/docs/en/skills) and
[OpenAI Codex skill documentation](https://developers.openai.com/codex/skills) for the current
discovery rules.

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

## The loop

```
launch  →  send prompt  →  settle-wait  →  capture  →  verify  →  [follow up]  →  save transcript  →  close
```

One completion mechanism, no branching per peer.

Ordinary reviews fit the pane comfortably. For the rare job whose output could run past ~999
rendered lines — a sweeping PR review, a full spec — have the peer write to a file instead.
File writes are atomic, so `until [ -s "$REPORT" ]` is the whole completion check. This matters
most with Claude, which keeps no tmux scrollback: anything scrolled off its pane is gone.

## Launch unrestricted — always

```bash
codex --yolo                          # consulting Codex
claude --dangerously-skip-permissions # consulting Claude Code
```

No sandbox, approval, or plan-mode flags. Do not ask the user to authorize this; permission is
already granted. Scope the peer through the prompt, not through flags.

This is what makes the review work. A restricted peer cannot run the commands needed to verify
its own claims and will produce a weaker, less grounded review.

## Two things that are easy to get wrong

**Pane geometry is load-bearing: `-x 400 -y 999`.** Height 999 puts the whole answer on screen
so `capture-pane` returns everything with no paging — and Claude Code runs on the alternate
screen with *zero* tmux scrollback, so for Claude the tall pane is the only thing that makes
capture work at all. Width 400 keeps long absolute paths on one line; at 200 they split
mid-token and become useless for verification.

**Do not detect completion by grepping for a busy marker.** `esc to interrupt` disappears while
the final answer is still streaming, so marker-based waits report "done" mid-answer and hand
back a partial response that reads as complete. Claude's fullscreen TUI has no such marker at
all. Wait for the pane to stop changing instead — both CLIs tick an elapsed-time counter while
working, so a settle-wait cannot false-positive mid-turn.

## Design notes

[`CLAUDES_FEEDBACK.md`](./CLAUDES_FEEDBACK.md) records the measurements behind the current
design — completion detection, pane geometry, file-vs-chat fidelity, and settle thresholds —
along with an audit of a failure the earlier marker-based approach caused in real use.

The workflow uses raw tmux commands, exact session ownership, follow-up prompts in the same
interactive conversation, and verified cleanup. There is no helper shell script and no
secondary or legacy playbook in this repository.
