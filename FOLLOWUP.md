# Follow-up: owner feedback and revised guidance

This doc records feedback from the repo owner (Archer) after the first real use of this
playbook, and revises the recommended approach accordingly. If you are an agent reading this
repo: **this doc overrides anything it contradicts in README.md.**

## 1. The zombie shells incident — clean up after yourself, automatically

While building this playbook, the Claude agent launched background shell loops to wait for
responses (`until tmux capture-pane … grep …; do sleep …; done` as detached background tasks).
Three of them had a busy-marker that never matched, so they never exited — and they kept
spinning even after the tmux sessions they watched were killed, because `capture-pane` against
a dead server errors forever. The owner had to notice "3 shells running" himself and ask about
it. **He is pissed about this, justifiably:**

- The whole point of the hygiene rule in this repo is *nothing left running when the work is
  done*. That applies to the watcher processes just as much as the tmux sessions themselves.
- An agent should never leave it to the human to spot orphaned processes. If you start a
  background process, you own its lifecycle: bound it with a timeout, kill it when its purpose
  is served, and verify (`tmux ls`, check your own background tasks) before declaring done.

## 2. The shell script is too black-box — the markdown IS the product

The owner doesn't like `agent-tmux.sh` as the recommended interface. A script is a black box:
you hand an agent a file it calls blindly, and when something goes wrong (like the busy-marker
bug above — which hid inside the script and made `ask` silently return early on long Claude
tasks) nobody sees it. A plain markdown playbook is transparent: people can hand it directly
to their Claude or Codex agents, the agent reads the actual commands, understands them, and
can adapt them when a TUI changes.

**Revised guidance:** the markdown playbook (README.md) is the canonical artifact. Give agents
the doc, not the script. `agent-tmux.sh` stays in the repo only as a worked reference of the
logic — treat it as documentation you can execute, not as the interface.

## 3. Use raw foreground tmux commands — no background shells, no subagents

The owner prefers this workflow to be driven with **plain tmux commands run in the foreground**,
not with background watcher shells and not by delegating to subagents. Reasons: everything is
visible in the conversation as it happens, nothing can outlive the turn, and there is no
orphaned-process class of bug at all.

The revised waiting pattern — a bounded foreground poll, run as a normal command:

```bash
# after sending the prompt: poll up to ~120s, checking every 2s, all in the foreground
for i in $(seq 1 60); do
  sleep 2
  screen="$(tmux capture-pane -p -t peer 2>/dev/null)" || break   # session gone? stop looping
  if ! echo "$screen" | grep -qiE 'esc to interrupt' \
     && ! echo "$screen" | grep -qE '^[^ ]{1,4} [[:upper:]][^ ]*…'; then
    break                                                          # no busy marker → done
  fi
done
tmux capture-pane -p -t peer | grep -v '^ *$' | tail -40
```

Notes:
- The `for`/`seq` bound means the loop *cannot* run forever — worst case it returns after the
  cap and you look at the screen and decide.
- The `|| break` on `capture-pane` means a dead session ends the loop instead of spinning.
- For long tasks (a real review can take minutes), just run the same bounded poll again —
  several short foreground checks beat one immortal background watcher.
- Everything else in README.md (starting sessions, sending prompts, scrolling, closing) was
  already raw tmux and stands as written. Only the *waiting* step ever used background shells,
  and it shouldn't.

## The rules, condensed

1. **Foreground raw tmux commands only.** No background watcher shells, no subagent delegation
   for driving these CLIs.
2. **Every wait is bounded** — a fixed iteration count, plus bail out if the session is gone.
3. **When the answer is in hand: close the CLI (`/exit` / `/quit`), kill the session, and
   confirm `tmux ls` is clean — including anything else you spawned along the way.** The human
   should never be the one who discovers a leftover process.
4. **Hand agents the markdown, not the script.**
