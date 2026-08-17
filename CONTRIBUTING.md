# Contributing

Pull requests are welcome. `main` is protected, so everything lands through
one, mine included.

## How to propose a change

1. Fork, branch off `main`.
2. Make the change, and **say how you verified it**. See below.
3. Open a PR against `main` describing what you saw before and after.

Small, obviously-correct fixes get merged quickly. Anything that changes the
layout model or adds a command is worth an issue first, so you do not build
something that turns out to be out of scope.

## What this project is

A tmux cockpit for running several coding-agent sessions at once. Around 650
lines of zsh, a tmux config, and one iTerm2 profile.

**In scope:** making that faster, clearer or harder to get wrong. Support for
agents other than Claude Code, provided it stays a variable and not a special
case.

**One action, one key.** No aliases, no "this still works if your fingers know
it": a second way to close a pane is a second row in every table and a key bar
that has to choose. A key that is replaced is removed, and `unbind`-ed by name
in `office.tmux.conf` so a long-running server drops it on the next reload.

**Out of scope:** a plugin system, a config file, a daemon, a package manager,
a dependency that does what twenty lines already do. If a feature needs
persistent state, it probably needs a rethink instead. `office off` kills the
tmux server, and everything has to survive that.

## The rules the code follows

- **zsh and tmux, nothing else at runtime.** `fzf`, `fd`, `git`, `micro` and
  `bat` are the only external commands, and each is either required at install
  or degrades to nothing.
- **`office.tmux.conf` sets no colours.** Not one. A user's theme has to
  survive installation. Anything visual belongs in `theme/`.
- **A key the office does not bind reaches the pane unchanged.** The office owns
  Shift-arrow and the Ctrl-Space table; every other key belongs to whatever is
  running in the pane, including the modified keys ASCII has no byte for
  (Shift-Enter, Ctrl-Enter). tmux swallows those by default, which is why
  `extended-keys always` is set — a person should not lose a keystroke that
  works in every other window just because this one has a layout. Same rule one
  layer up: the installer names the parent iTerm profile and writes **no**
  `Keyboard Map`, so a binding you add later is inherited rather than frozen out.
  Changing key handling means probing what every OTHER key now sends, not just
  the one you meant to fix.
- **Nothing destructive without a confirmation**, except `office clean --idle`,
  which exists to be unattended and says so.
- **Keybindings never print.** Output from a `run-shell` binding makes tmux
  force the active pane into view-mode, where every office key stops working. Use
  `_office_say`, which goes to the status line.
- **Anything shown on a pane border is untrusted.** Labels are stripped of `#`
  before storage, because tmux renders them through its format engine where
  `#(...)` runs a shell command.
- **Comments say why, not what.** The interesting comments in here are the ones
  recording a trap someone already fell into. Add to them.

## Verifying a change

There is no test suite, because almost everything here is a side effect on a
live tmux server. Instead, every change should come with the commands you ran
and what you saw. The pattern that works:

```sh
# build a throwaway office, look at it, tear it down
d=$(mktemp -d)/t; mkdir -p $d; git -C $d init -q
OFFICE_SOLO=1 _office_open "$d"; s=$(_office_sessname "$d"); sleep 4
tmux list-panes -t "=$s" -F '#{@office_num} #{pane_left},#{pane_top} #{@office_kind}' | sort -n
tmux kill-session -t "=$s"; rm -rf "${d:h}"
```

`OFFICE_SOLO=1` skips the always-on hooks. Always tear the session down, and
never test against an office you are working in.

Touched anything about keys? Run `bin/key-probe`. It builds a throwaway office
on its own socket, attaches a REAL client on a pty and types raw bytes at it,
then checks both halves at once: a bound key moves you and never reaches the
pane, every other key reaches the pane byte for byte. The keys worth checking
are the twenty you did not mean to change. It exits non-zero if any moved.

`tmux send-keys` cannot stand in for that client: it writes to the pane's tty
and never consults a key table, so Shift-Left looks broken under send-keys and
is perfectly fine for a human.

Touched the mouse or copy mode? Run `bin/mouse-probe`. Same throwaway office and
same real client, but it writes raw SGR mouse bytes: a drag has to land on the
clipboard in every pane kind, and Escape and a click have to get you out of copy
mode. Two things it catches that reading the config does not. Cancelling copy
mode on a click must wait for the mouse *release* and must skip a selection
already in flight, or a double-click loses its word and strands the pane in the
hidden copy mode it opened. And a double-click cannot be read back for a full
second: tmux holds it for its own 500ms triple-click window before the binding
starts, so a check that looks sooner reports a working gesture as broken.

Touched anything that reads `pane_left`, `pane_top` or a window size? Run
`bin/zoom-probe`. It builds a throwaway office, zooms a pane, and runs every
command that moves one. **A zoomed pane reports full-window coordinates**, so
every "which column is this in" question in `office.zsh` is answered about a
room that is not on screen — and `_office_layout_ok` then calls a perfectly good
office broken and hands it to `_office_relayout`, which breaks every pane out to
the stash. Reading the code does not show you this; the probe does.

Touched `bin/office-attn`, `@office_attn_gate` or a `pane-border-format`? Run
`bin/attn-probe`. It builds a throwaway office and puts fake agents in the desks
that move the way real ones do, then drives the real watcher. Two cases in it are
the whole reason the file is shaped the way it is, and neither is visible in the
code: **an idle agent pane is not perfectly still** (Claude Code rotates a hint
line under its input box, so "still" has to tolerate a line moving), and **an
agent that is thinking moves exactly one line** (its spinner, which that same
tolerance then eats — worth eighteen seconds of a border saying "your turn"
mid-task before it was measured). One case here rotates a line and must still
count as waiting; another animates one line at 10Hz and must never. It also
checks the gate by expanding the expression that ships rather than a copy of it.

One thing that probe cannot do, and it is worth knowing before you write another:
**`display-message -p` expands formats with jobs switched off**, so a `#()` in
one is always empty there. Measured on 3.7b — five calls over five seconds and
the command never ran once. A drawn border does run it; a probe reading one back
does not.

Run `zsh -n office.zsh` before you push. It catches most of it.

## Reporting a bug

Include `tmux -V`, your terminal, and the output of:

```sh
office doctor
tmux list-panes -a -F '#{session_name} #{pane_id} #{@office_kind} #{pane_left},#{pane_top}'
tmux list-keys -T root | grep -E ' M-| C-S-|Mouse|Click'
```

If a key does nothing, that last one plus your terminal's name is usually the
whole answer. It covers the mouse too: a drag or a double-click that does not
copy shows up there as a missing or shadowed binding.
