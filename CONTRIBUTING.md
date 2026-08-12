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
other terminals that can deliver the chords. Support for agents other than
Claude Code, provided it stays a variable and not a special case.

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
- **Nothing destructive without a confirmation**, except `office clean --idle`,
  which exists to be unattended and says so.
- **Keybindings never print.** Output from a `run-shell` binding makes tmux
  force the active pane into view-mode, where every chord stops working. Use
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

Run `zsh -n office.zsh` before you push. It catches most of it.

## Reporting a bug

Include `tmux -V`, your terminal, and the output of:

```sh
office doctor
tmux list-panes -a -F '#{session_name} #{pane_id} #{@office_kind} #{pane_left},#{pane_top}'
tmux list-keys -T root | grep -E ' M-| C-S-'
```

If a key does nothing, that last one plus your terminal's name is usually the
whole answer.
