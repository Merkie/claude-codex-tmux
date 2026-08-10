#!/bin/bash
# agent-tmux.sh — drive `claude` / `codex` CLI sessions inside tmux (for agent-to-agent use).
# Companion doc: README.md (https://github.com/Merkie/claude-codex-tmux)
#
# Usage:
#   agent-tmux.sh start <session> claude|codex [workdir]   # launch CLI in detached tmux session
#   agent-tmux.sh ask   <session> "prompt" [timeout_s]     # send prompt, wait for reply, print screen
#   agent-tmux.sh read  <session> [lines]                  # print last N non-blank screen lines (default 40)
#   agent-tmux.sh full  <session>                          # full transcript incl. scrollback (codex; claude inline mode)
#   agent-tmux.sh up    <session>                          # scroll one page up (send PageUp to the TUI)
#   agent-tmux.sh down  <session>                          # scroll one page down
#   agent-tmux.sh stop  <session>                          # graceful CLI exit, then kill the tmux session
set -u

CMD="${1:-}"; NAME="${2:-}"
die() { echo "agent-tmux: $*" >&2; exit 1; }
[ -n "$CMD" ] && [ -n "$NAME" ] || die "usage: agent-tmux.sh start|ask|read|full|up|down|stop <session> ..."

pane() { tmux capture-pane -p -t "$NAME"; }
busy() { pane | grep -qi 'esc to interrupt'; }

case "$CMD" in
start)
  CLI="${3:-}"; DIR="${4:-$PWD}"
  case "$CLI" in
    claude) LAUNCH='claude --dangerously-skip-permissions' ;;
    codex)  LAUNCH='codex --yolo' ;;
    *) die "start needs CLI type: claude or codex" ;;
  esac
  tmux has-session -t "$NAME" 2>/dev/null && die "session '$NAME' already exists (stop it first)"
  tmux new-session -d -s "$NAME" -x 200 -y 50 -c "$DIR" || die "tmux new-session failed"
  tmux set-environment -t "$NAME" AGENT_CLI "$CLI"
  tmux send-keys -t "$NAME" "$LAUNCH" Enter
  # Wait up to 30s for the input prompt, auto-answering known startup screens.
  SECONDS=0
  while [ "$SECONDS" -lt 30 ]; do
    SCREEN="$(pane)"
    if echo "$SCREEN" | grep -q 'Yes, I accept'; then          # claude bypass-permissions warning
      tmux send-keys -t "$NAME" 2; sleep 1; continue
    fi
    if echo "$SCREEN" | grep -q 'Update now'; then             # codex update prompt
      tmux send-keys -t "$NAME" 2; sleep 0.4; tmux send-keys -t "$NAME" Enter; sleep 1; continue
    fi
    # Both CLIs show a "❯"/"›" input line when ready; cheap proxy: screen non-empty and not busy
    if echo "$SCREEN" | grep -qE '^[❯›]' && ! busy; then
      echo "started $CLI in tmux session '$NAME' (dir: $DIR)"; exit 0
    fi
    sleep 1
  done
  die "timed out waiting for $CLI to become ready (inspect: tmux capture-pane -p -t $NAME)"
  ;;
ask)
  PROMPT="${3:-}"; TIMEOUT="${4:-600}"
  [ -n "$PROMPT" ] || die "ask needs a prompt"
  busy && die "agent is still working; wait or interrupt first"
  # Bracketed paste handles quotes/newlines safely; then submit with Enter.
  printf '%s' "$PROMPT" | tmux load-buffer -
  tmux paste-buffer -p -d -t "$NAME"
  sleep 0.4
  tmux send-keys -t "$NAME" Enter
  # Wait for the busy marker to appear (instant replies may skip it), then disappear.
  SECONDS=0
  while [ "$SECONDS" -lt 10 ] && ! busy; do sleep 0.3; done
  while [ "$SECONDS" -lt "$TIMEOUT" ] && busy; do sleep 1; done
  busy && die "timed out after ${TIMEOUT}s (agent still working; read with: agent-tmux.sh read $NAME)"
  sleep 1
  pane | grep -v '^[[:space:]]*$' | tail -40
  ;;
read)
  pane | grep -v '^[[:space:]]*$' | tail -"${3:-40}"
  ;;
full)
  # Includes tmux scrollback. Codex renders in the normal buffer so this is the whole transcript.
  # Claude in fullscreen TUI mode (alternate screen) has no tmux scrollback — use up/down instead.
  tmux capture-pane -p -t "$NAME" -S -
  ;;
up)
  if [ "$(tmux display-message -p -t "$NAME" '#{alternate_on}')" = "1" ]; then
    tmux send-keys -t "$NAME" PPage                            # TUI handles its own scrolling
  else
    tmux copy-mode -t "$NAME" 2>/dev/null; tmux send-keys -t "$NAME" -X halfpage-up
  fi
  sleep 0.4; pane
  ;;
down)
  if [ "$(tmux display-message -p -t "$NAME" '#{alternate_on}')" = "1" ]; then
    tmux send-keys -t "$NAME" NPage
  else
    tmux send-keys -t "$NAME" -X halfpage-down 2>/dev/null
    # Leave copy-mode automatically once back at the bottom
    [ "$(tmux display-message -p -t "$NAME" '#{scroll_position}')" = "0" ] && tmux send-keys -t "$NAME" -X cancel 2>/dev/null
  fi
  sleep 0.4; pane
  ;;
stop)
  CLI="$(tmux show-environment -t "$NAME" AGENT_CLI 2>/dev/null | cut -d= -f2)"
  case "$CLI" in
    claude) tmux send-keys -t "$NAME" -l '/exit'  && sleep 0.7 && tmux send-keys -t "$NAME" Enter ;;
    codex)  tmux send-keys -t "$NAME" -l '/quit'  && sleep 0.7 && tmux send-keys -t "$NAME" Enter ;;
  esac
  sleep 2
  tmux kill-session -t "$NAME" 2>/dev/null
  echo "session '$NAME' closed"
  ;;
*)
  die "unknown command: $CMD"
  ;;
esac
