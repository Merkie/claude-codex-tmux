# Controlling Claude Code & Codex CLI via tmux (agent-to-agent playbook)

Verified working on this Mac on 2026-08-09 (tmux 3.7b, Claude Code v2.1.226, Codex v0.146.0).
Audience: Claude, Codex, or any other agent that can run shell commands. Use this to consult
the *other* CLI for code review, plan critique, or a second opinion — then close the session.

**Fast path:** use the helper script `~/Desktop/agent-tmux.sh` (section 2). Raw tmux commands
are in section 3 if you need finer control. Both are proven end-to-end.

---

## 1. The golden workflow

1. **Start** the peer CLI in a detached tmux session.
2. **Ask** your question (review request, plan critique, etc.).
3. **Wait** for the reply, **read** it (scroll if needed), optionally ask follow-ups.
4. **Close the session** as soon as you have the answer/opinion or the work is done.
   Don't leave idle AI sessions running — this is part of the workflow, not optional.

Launch commands: `claude --dangerously-skip-permissions` and `codex --yolo`
(both fully autonomous — no permission prompts during the conversation).

---

## 2. Helper script (recommended)

```bash
~/Desktop/agent-tmux.sh start <session> claude|codex [workdir]  # launch (handles startup screens)
~/Desktop/agent-tmux.sh ask   <session> "prompt" [timeout_s]    # send, wait for reply, print screen
~/Desktop/agent-tmux.sh read  <session> [lines]                 # re-print last N non-blank lines
~/Desktop/agent-tmux.sh full  <session>                         # whole transcript incl. scrollback
~/Desktop/agent-tmux.sh up    <session>                         # scroll one page up
~/Desktop/agent-tmux.sh down  <session>                         # scroll one page down
~/Desktop/agent-tmux.sh stop  <session>                         # graceful /exit|/quit + kill session
```

Example — code review by the peer agent:

```bash
~/Desktop/agent-tmux.sh start reviewer codex ~/Desktop/huzi/huzi-core-api
~/Desktop/agent-tmux.sh ask reviewer 'Review the uncommitted changes in this repo (git diff).
Act as an adversarial reviewer: list concrete bugs, edge cases, and design problems.
Write your findings to REVIEW.md in the repo root.' 900
~/Desktop/agent-tmux.sh stop reviewer
```

Example — plan critique:

```bash
~/Desktop/agent-tmux.sh start critic claude ~/Desktop/huzi/satori
~/Desktop/agent-tmux.sh ask critic 'Read PLAN.md. Act as an adversarial critic: pick apart weak
assumptions, missing steps, and risks. Be specific and blunt. Reply inline.' 600
~/Desktop/agent-tmux.sh read critic 60      # re-read the answer any time
~/Desktop/agent-tmux.sh stop critic
```

Tips:
- `ask` supports multi-line prompts (it uses tmux bracketed paste, so newlines don't submit early).
- For long outputs, have the peer **write a file** (REVIEW.md etc.) and read that — more reliable
  than scraping a TUI screen.
- Prompts are single conversations: follow-up `ask` calls continue the same chat with full context.

---

## 3. Raw tmux commands (what the script does)

### Start

```bash
tmux new-session -d -s peer -x 200 -y 50 -c /path/to/repo   # detached, big pane, correct cwd
tmux send-keys -t peer 'claude --dangerously-skip-permissions' Enter   # or: 'codex --yolo'
```

Always give `-x/-y` (default detached size is tiny) and `-c` (the CLI reads the cwd's repo).

### Startup screens you may hit

- **Claude bypass-permissions warning** (first run on a machine): screen says
  *"WARNING: Claude Code running in Bypass Permissions mode"* with
  `1. No, exit` / `2. Yes, I accept`. **Press `2`** (accepts immediately, no Enter needed):
  `tmux send-keys -t peer 2`. On this Mac it's permanently skipped via
  `"skipDangerousModePermissionPrompt": true` in `~/.claude/settings.json`, so you normally
  go straight to the prompt. (Historical versions used `1` to accept — always `capture-pane`
  and read the options rather than pressing blind.)
- **Codex update prompt**: `1. Update now / 2. Skip / 3. Skip until next version` —
  press `2` then `Enter` to skip.

### Send a prompt

```bash
tmux send-keys -t peer -l 'Your single-line prompt here'   # -l = literal (no key-name parsing)
sleep 0.4                                                  # let the TUI register the text
tmux send-keys -t peer Enter                               # submit — separate call, never with -l
```

Multi-line / quote-heavy prompts — use bracketed paste instead of `send-keys -l`:

```bash
printf '%s' "$PROMPT" | tmux load-buffer -
tmux paste-buffer -p -d -t peer     # -p = bracketed paste → newlines don't auto-submit
sleep 0.4; tmux send-keys -t peer Enter
```

### Wait for the reply (works for BOTH CLIs)

Both TUIs show **`esc to interrupt`** on screen while working. Poll for it to appear, then disappear:

```bash
until tmux capture-pane -p -t peer | grep -qi 'esc to interrupt'; do sleep 0.3; done   # started
until ! tmux capture-pane -p -t peer | grep -qi 'esc to interrupt'; do sleep 1; done   # finished
```

Add a timeout guard for real use (see the script). Claude also prints a `✻ Worked for Ns`-style
line when done; Codex's answer is the last `•` bullet above the input box.

### Read the screen

```bash
tmux capture-pane -p -t peer                    # visible screen
tmux capture-pane -p -t peer | grep -v '^\s*$' | tail -40   # trimmed
```

### Scroll the history (two different mechanisms!)

Check which buffer the CLI renders into: `tmux display-message -p -t peer '#{alternate_on}'`

- **Claude Code** (`alternate_on=1` — fullscreen TUI on this machine, set via `"tui": "fullscreen"`):
  tmux scrollback is **empty**; the TUI scrolls itself. Send PageUp/PageDown keys:
  ```bash
  tmux send-keys -t peer PPage    # scroll up (repeat as needed; shows "Jump to bottom: fn+↓")
  tmux send-keys -t peer NPage    # scroll down / back to live view
  ```
  Claude even prints "tmux detected · scroll with PgUp/PgDn" in its footer. Capture between
  keypresses to read each page.
- **Codex** (`alternate_on=0` — normal buffer): tmux-native scrollback works.
  ```bash
  tmux capture-pane -p -t peer -S -           # ENTIRE transcript in one shot — usually all you need
  tmux copy-mode -t peer                      # or scroll interactively:
  tmux send-keys -t peer -X -N 40 scroll-up
  tmux send-keys -t peer -X -N 40 scroll-down
  tmux send-keys -t peer -X cancel            # IMPORTANT: leave copy-mode before typing prompts
  ```
  Codex collapses long tool output ("+53 lines, ctrl+t to view transcript") — collapsed lines are
  NOT in scrollback. If you need them, `tmux send-keys -t peer C-t` toggles the transcript view,
  or better: have Codex write results to a file.

### Close the session (do this when done — good hygiene)

```bash
tmux send-keys -t peer -l '/exit'  ; sleep 0.7; tmux send-keys -t peer Enter   # Claude
tmux send-keys -t peer -l '/quit'  ; sleep 0.7; tmux send-keys -t peer Enter   # Codex
sleep 2
tmux kill-session -t peer          # definitive cleanup (safe even if the CLI already exited)
```

Graceful exit prints a resume hint you can save if the conversation might continue later:
`claude --resume <uuid>` / `codex resume <uuid>`. `tmux kill-session` alone is also safe —
both CLIs autosave transcripts — but prefer the slash-command first.

`tmux ls` should list nothing you own when you're finished. Check it.

---

## 4. Gotchas learned the hard way

- **Text and Enter in separate `send-keys` calls**, with ~0.4s between — sending them together
  can submit before the TUI registers the text.
- **`-l` flag** for prompt text (else words like "Enter"/"Space" get parsed as key names);
  never put `Enter` inside a `-l` call (it would be typed literally).
- **Completion-detection race**: wait for `esc to interrupt` to APPEAR before waiting for it to
  disappear, with a short cap on the appear-wait (instant replies may skip it).
- **Codex sometimes ends a turn with no text answer** (turn ends on a tool call). The busy marker
  goes away and nothing is printed. Just ask "So what is the answer?" — the session is fine.
- **Copy-mode swallows keystrokes**: if a pane is in copy-mode, prompts you type go nowhere.
  `tmux send-keys -t peer -X cancel` first (the `q` key also works).
- **Session names collide**: `tmux has-session -t name` before creating; use task-specific names
  (`reviewer`, `critic`, `peer-claude`), not generic ones another agent might also pick.
- **zsh eats bare `=`**: `echo ===` fails in zsh (`=foo` is a path expansion). Quote such strings.
- Claude's suggested-prompt placeholder in the input box (e.g. "Try …") is UI decoration,
  not real input — ignore it in captures.
- These are full autonomous sessions — treat the peer's answer like any reviewer's opinion,
  and give it file paths to write big outputs to instead of scraping the screen.

## 5. Session naming convention

To avoid two orchestrating agents colliding, prefix with who owns it:
`cl-` for sessions Claude starts, `cx-` for sessions Codex starts — e.g. `cl-reviewer`,
`cx-critic`. Kill your own sessions when done; never kill the other prefix.
