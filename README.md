# Agent Office

### Four agents. One window.

Each one in its own git worktree. The one that has stopped and is waiting on you
says so, on its own border, without being asked.

[![CI](https://github.com/ZyxWorks/agent-office/actions/workflows/ci.yml/badge.svg)](https://github.com/ZyxWorks/agent-office/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-c9903f)](LICENSE)
![Platform: macOS, Linux and WSL2](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2-6a6c77)
![No daemon](https://img.shields.io/badge/daemons-0-6a6c77)

**Build agents with agents, and talk to what you built, in one window.**
Several coding-agent sessions side by side, each in its own git worktree, plus a
shell, a file editor that follows that shell, and a chat pane wired to your own
agent. Claude Code out of the box, Codex or any other CLI with one variable.

[**The product page**](https://zyxworks.github.io/agent-office/) ·
[Our other tools](https://zyxworks.com/) ·
[What we do for companies](https://runzyx.xyz)

```sh
office on
```

```
┌─────────────────────────────┬──────────────┐
│ 1 CLAUDE                    │ 4 AGENT CHAT │  ^Space c
│                             │              │
├─────────────────────────────┼──────────────┤
│ 2 CLAUDE 2   ^Space n adds  │ 5 SHELL      │  ^Space s
│                 one more    │              │
├─────────────────────────────┼──────────────┤
│ 3 CLAUDE 3                  │ 6 FILE EDITOR│  ^Space e
│                             │              │
└─────────────────────────────┴──────────────┘
   the agents that build it       the agent
   claude / codex / your own      you built
```

**Left: the agents that build.** Claude Code, Codex, or whatever CLI you use,
stacked and kept at equal height. One variable points them at your agent, so
nothing here knows or cares which one you run.

**Right: the agent you built.** Once your own agent has a chat command, that
pane is it: you talk to the thing you have been building, in the same window you
built it in, and it does the work. No dashboard to stand up, no Slack app to
register, no browser tab. If it runs in a terminal, it belongs in that pane.

Closing the window kills nothing: `office on` puts you back exactly where you
were, panes, layout and all.

> **New to running an agent in the terminal?**
> Start with **[GETTING-STARTED.md](GETTING-STARTED.md)**: what each pane is,
> how to move around, and how to get back out of the editor. Twenty minutes,
> once, no prior tmux assumed.

## Why

Running three or four coding agents at once is normal now. The tooling for it
was not: a heap of terminal windows, a layout you rebuilt every morning, and no
idea which one was stuck. Every window looked equally busy, so finding the one
waiting on you meant reading all four, then doing it again five minutes later.
That last part is why this exists. The window is the easy half.

| 4 | 20s | 0 |
|---|---|---|
| agents in one window, each in its own git worktree | before a desk that has stopped says so on its border | daemons, config files and dashboards to stand up |

Four is the cap because a fifth session in a fifty-row window gets about nine
rows, which is a slit and not a desk. Twenty seconds is the default and it is
one variable. Four agents you can keep track of is a different tool from four
agents in four windows.

That is the first half of what this fixes. The second half is what you do with
those agents. People building an agent of their own hit the same wall every
time: the thing works in a terminal, and then they lose a week standing up a
dashboard or wiring a Slack app just to talk to it. The chat pane is that,
already built. Point it at your agent and it is a place to give it work.

So the shape is: **agents on the left writing the code, the agent you built on
the right doing the work.** One window, one command, and no web app in the
middle. It is one zsh file, one tmux config and three small helpers, about 1,900
lines all in, plus five probes that drive a real tmux server to check it. No
daemon, no plugin manager, no config file, and one `git fetch` you can switch
off.

## Setup

### macOS

```sh
brew install tmux fzf fd micro bat          # needs Homebrew: https://brew.sh
git clone https://github.com/ZyxWorks/agent-office.git ~/agent-office
~/agent-office/install.sh
exec zsh && office on
```

Clone it wherever you like; the installer works out its own path. Examples in
this README use `~/agent-office`.

`exec zsh` only because a function needs a shell that has read it — `office`
also goes on your `PATH` as `~/.local/bin/office`, so the terminals you already
had open find it too, without being restarted.

The installer adds one line to your `.zshrc`, one to your `.tmux.conf` and that
symlink. That is the whole install: **no keyboard map, in any terminal.** Every office key is
either `Shift+arrow` or the `Ctrl-Space` prefix, and every terminal on every OS
already sends both.

It changes no colours. If you want the look as well, that is
`./install.sh --theme`, which writes an iTerm2 profile — see
[the theme](#the-theme-if-you-want-it) below.

**Any terminal works.** iTerm2, Terminal.app, Ghostty, WezTerm, Alacritty: the
keys are identical in all of them, with nothing to configure. Apple Silicon and
Intel are identical here too, it is all shell.

### Windows

tmux does not run natively on Windows, so this lives inside **WSL2**, which is
where you run your agent too.

```powershell
wsl --install          # then reboot and open your new Linux terminal
```

Then, inside WSL:

```sh
sudo apt update && sudo apt install -y tmux zsh git fzf fd-find micro bat
mkdir -p ~/.local/bin && ln -sf "$(which fdfind)" ~/.local/bin/fd   # Debian calls it fdfind
git clone https://github.com/ZyxWorks/agent-office.git ~/agent-office
~/agent-office/install.sh
exec zsh && office on
```

That is Ubuntu or Debian, which is what `wsl --install` gives you. On Fedora or
Arch swap in `dnf` or `pacman`; the package names are the same and `fd` is not
renamed there.

Windows Terminal needs nothing pasted into it: `Shift+arrow` and `Ctrl-Space`
are ordinary sequences it already sends.

**A note if you do not use zsh.** zsh has to be installed, because `office` is
written as a zsh function, but it does not have to be your login shell: the
installer puts `office` on your `PATH`, and that file runs it in zsh for you.
Type `office on` in bash or fish and it works. Everything inside the panes is
your normal shell. The one thing only the function can do is leave your shell
in the repo it opened, since no subprocess can `cd` for its parent.

**Requires** `tmux` 3.4+, `zsh`, `git`, [`fzf`](https://github.com/junegunn/fzf),
[`fd`](https://github.com/sharkdp/fd), and an agent CLI such as
[Claude Code](https://claude.com/claude-code).
**Optional:** [`micro`](https://micro-editor.github.io) for the editor pane,
[`bat`](https://github.com/sharkdp/bat) for its file preview.

## Three commands

`office on`, `office break`, `office off`. Everything else has a key.

Nothing accumulates behind your back, so there is no housekeeping to remember.
Walking in reaps anything you parked and never came back to (12 hours by
default, `OFFICE_REAP_HOURS`), and going home takes the whole tmux server with
it. `office doctor` and `office clean` are there when you want to look, not
because you have to.

Panes you can see are never closed automatically. A script that kills an agent
you were coming back to is worse than a full disk.

## The keys

| | |
|---|---|
| `⇧←↑↓→` | move between panes |

Everything else is **`Ctrl-Space`, then one letter**:

| | |
|---|---|
| `n` | new session, in its own git worktree |
| `c` `s` `e` | toggle chat / shell / file editor. On a pane that quit whatever it was running, the same key restarts it |
| `a` | park every session, bring them all back, or open one if there are none |
| `q` | close this pane |
| `x` | park this pane. Still running, `office show` brings it back |
| `z` | zoom this pane full screen, and back |
| arrows | move, and the only way out of a file you have open |


Two rules, and the second covers everything. Movement is a chord because it is
what you do most and arrows carry their modifier natively; every action is the
prefix, which is the tmux convention and needs **no terminal configuration on
any platform**. **One action, one key** — there is no second way to close a
pane or move between them, because a scheme with synonyms is one you have to
read twice to learn once. The mouse works too: click a pane to focus it, drag a
border to resize, and **drag across text to copy it** — it is on the system
clipboard the moment you let go, in the shell and in the file editor both. It
stays that way until `office off`.

### The keys are on the status bar

A pane's border carries the key that toggles it, which is no help at all once
the pane is closed and the border went with it. So the bar carries the whole
set:

```
^Space then  │  n new  sessions a · shell s · editor e · chat c
               ^^^^^^^^ dim = open            lit = closed ^^^^
```

It updates the instant a pane opens or closes, because `office` writes it into
a tmux option rather than the status bar polling a command. A polled job is
always one interval behind the thing it describes.

Brightness means one thing and one thing only: **lit means that pane is
closed**, so the thing standing out is the thing you cannot find. `new` sits
behind a divider because it is an action rather than a state. Clicking the
strip opens a new session.

It ships with the optional theme, or take it on its own:

```tmux
set -g status-left "#{@office_bar} "
set -g status-left-length 70
```

### Which one is waiting on you

A desk that has stopped moving for twenty seconds says so on its own border,
with how long it has been waiting:

```
 2 CLAUDE · desk-2 · rewrite the auth module              your turn 4m
```

Nothing to press, nothing to install, and no hook in your agent's settings. It
works this out by watching the pane rather than by knowing anything about what is
running in it, so it is the same for `claude`, `codex` or whatever
`OFFICE_SESSION_CMD` points at: an agent that is working **redraws** — a spinner,
an elapsed timer, output arriving — and an agent that has stopped does not.

It takes two looks half a second apart, because either one alone is wrong, and
both of those were measured rather than reasoned about. An idle Claude Code pane
is not perfectly still: it rotates a hint line under the input box every eight
seconds, so a screen fingerprint never settles and the marker would never appear.
An agent that is *thinking* moves exactly one line, its spinner, so tolerating a
line means the border says "your turn" for as long as the agent takes to think —
eighteen seconds of it, in the session that produced this. What separates them is
the rate, not the amount: a spinner moves within half a second, a hint that
rotates every eight does not.

The pane you are sitting in never says it, because you are already looking at it,
and neither do the shell and the file list. With the theme it arrives in
`$ACCENT`, which now has exactly one meaning anywhere on the screen. The wait is
`OFFICE_ATTN_SECS` and it is the only knob: raise it if your agent can go quiet
mid-task without redrawing anything at all. `bin/attn-probe` is the check.

**The number keeps counting, and past the hour it means something else.** It is
the time since that agent last did anything at all, so it is also the age of its
session:

```
 3 CLAUDE · desk-3 · port the payment tests           your turn 1h20m
```

Most providers stop caching a conversation that has been idle that long — Claude
Code's own prompt cache holds for an hour — so the next thing you say to that
desk is charged as if the conversation were new. `1h20m` says that at a glance
and `80m` does not. The office does not know anybody's billing rules and does not
pretend to: it states the age, and you know what an hour costs you.

### How full each desk's context window is

The other number you had to walk into a pane to learn. Every desk carries it:

```
 2 CLAUDE · desk-2 · port the payment tests            412k   your turn 4m
```

Quiet while it is furniture, and it climbs when it becomes a decision: plain
under `OFFICE_CTX_WARN` (400k), the theme's accent above it, and its alarm colour
above `OFFICE_CTX_ALARM` (600k). Move both to suit the window your plan gets —
`120000` and `170000` are the sensible pair for a 200k window. Now you can see
which of four desks to compact without interrupting any of them to ask.

It is the same figure `/context` reports: input plus cache-creation plus
cache-read on that session's last turn, read straight out of Claude Code's own
transcript. Finding it needs no configuration and no hook in your settings —
Claude Code writes `~/.claude/sessions/<pid>.json` for every session it runs, so
a pane asks its own process group which of its children has one of those and
reads the session id out of it. Exact even with two desks in one checkout, which
is more than guessing from directory names can manage.

**This is the one Claude Code special case in the package**, and it costs nothing
to anyone else: no `~/.claude/sessions` and `bin/office-ctx` exits on its second
line, so a `codex` or `aider` desk simply has no number. It is one screen of
`sh` with the file layout written down at the top, so when Claude Code moves
those files it is a ten-minute fix. `bin/ctx-probe` is the check, and it needs no
API call: a fake `$HOME` with those two files in it is a complete stand-in.

### The one chord, and why it is only arrows

`Shift+arrow` is `CSI 1;2 A-D`, which **every terminal already sends** on every
operating system. Nothing to install, and nothing else claims it: not macOS
Mission Control (that is Ctrl+arrow), not word-jump (Option+arrow).

The one thing Shift+arrow normally does is select text, and that matters only
while a file is actually open. tmux can see the difference (the pane reports
`micro` with a file open and `zsh` while the file list is showing), so the file
list moves you like every other pane and only an open file keeps the key.

**Every pane is reachable with Shift+arrow except a file you have open**, and
there `Ctrl+Q` closes it back to the list, or `Ctrl+Space` and an arrow moves
out directly. The prefix always wins, from anywhere, including from inside an
editor or a scrollback.

This used to answer to `Ctrl+Shift+arrow` as well, and that alias is **gone**.
It was the only reason the installer ever asked to write a key map into your
terminal: `Ctrl+Shift` on a *letter* cannot be sent at all (`Ctrl+Z` and
`Ctrl+Shift+Z` are the same byte, `0x1A`), and on an *arrow* it needed a
per-terminal translation layer for a movement `Shift+arrow` already does. One
scheme, no setup, nothing to relearn per machine.

### What the mouse does, and where it stops

The mouse does one thing here, and it is **copying**. Drag across text and it is
on the system clipboard when you let go; a double-click takes the word under it.
Nothing to press afterwards, in the shell and in the file editor both.

**And you can always get back to the prompt.** Scrolling a pane back puts it in
tmux's copy mode, where the arrows walk a cursor through scrollback and nothing
you type reaches the shell. A **click** puts you back at the live prompt, and so
does **Escape**. Both of those did nothing at all until 2026-08-15 — tmux binds
Escape to clearing a selection you do not have, and a click to focusing a pane
you are already in, so both failed silently and `q` was the only way out. A pane
that had merely scrolled looked like a terminal that had died, and the drag that
copies out of it looked broken too, because copying snaps the view back to the
bottom and the jump reads as nothing having happened.

The rule is that **an app that asked for the mouse keeps it.** A drag inside
`htop` or `lazygit` is theirs, a double-click still opens the file you hit in
the file list and still places a cursor in an open file.

The FILE EDITOR is the one exception, and it is deliberate. micro and fzf both
hold the mouse there, and neither can reach the system clipboard on macOS —
micro copies a mouse selection to the PRIMARY selection, which is an X11 idea
macOS does not have, so the text went nowhere you could paste from. Office keeps
the *drag* for tmux in that one pane kind, gated on `@office_kind`, so the pane
you read files in copies like the pane you read output in. Clicks still belong
to the app, and Shift+arrow still selects inside an open file.

**A double-click does not zoom, and briefly did.** It was a mouse synonym for
`Ctrl-Space z`, removed for two measured reasons: it could never work in a pane
running micro, fzf or Claude Code, because taking the double-click from them
would cost the file list its click-to-open and Claude Code its own
select-to-copy; and even where it worked it was slow, because tmux cannot fire a
double-click until the triple-click window has passed, and that wait is not
tunable. A key that works in every pane and answers instantly wins.


## Park versus close

`Ctrl-Space x` parks a pane: it is moved to a hidden tmux session and keeps running.
Its own toggle brings it back, in its proper place, or `office show` picks from
everything parked.

`Ctrl-Space q` closes a pane for good. Parking is not free, a parked agent session
still holds its 400 to 700MB, and `office doctor` lists parked panes alongside
live ones for exactly that reason.

## Commands

| | |
|---|---|
| `office on` | walk in: open the office, start your always-on stack |
| `office break` | step out: detach, everything keeps running |
| `office off` | go home: quit every office, stop the stack, asks first |
| `office <name>` | open another repo by fuzzy name |
| `office pick` | fuzzy-pick from every repo under `$CODE_ROOT` |
| `office solo` | like `on`, but starts nothing: the panes and nothing in them |
| `office new [wt]` | one more session in its own git worktree — `Ctrl-Space n`. A free one, or a new `desk-N`, or the worktree you name, created if it is not there yet |
| `office task <what>` | one more session, already working on `<what>` |
| `office desk` | one more session in THIS checkout, when you mean it |
| `office chat` `shell` `edit` | toggle a right-strip pane |
| `office sessions` | park or restore the whole left column |
| `office renumber` | renumber the panes and redraw the key bar (every office command that changes the panes already does) |
| `office layout` | rebuild the layout when a pane ends up somewhere wrong |
| `office hide` / `office show` | park the current pane / bring one back |
| `office doctor` | what is running and what it costs in RAM, read-only |
| `office clean` | pick panes to close, heaviest first (rarely needed) |
| `office sweep [h]` | close offices you walked away from, and everything in them |
| `office update` | pull the newest agent-office |
| `office clean --idle [h]` | no picker: close anything idle over `h` hours |
| `office help` | all of the above, with the diagram |

The command is `office`. `ao` and `o` are aliases for it.

## Bringing your own agent

`office` does not know what Claude Code is. A session is a command and the chat
pane is a command. Point them at yours.

**The sessions** in the left column:

```sh
OFFICE_SESSION_CMD="my-agent"        # whatever you type to start it
OFFICE_SESSION_LABEL="MY AGENT"      # what its panes are called
```

That is the whole integration. `Ctrl-Space n` opens one. `office task <what>`
opens one already working
on a task, by running `$OFFICE_SESSION_CMD "<your task>"`, so that one needs an
agent that takes a prompt as its first argument. If yours does not, `Ctrl-Space n` still
works and you type the task into the pane.

**The chat pane** is separate, and it is for the conversational side of your
agent rather than a coding session. Three shapes cover almost everything:

```sh
# 1. your agent has a REPL
OFFICE_CHAT_CMD="my-agent chat"

# 2. your agent writes a log and you want to watch it live
OFFICE_CHAT_CMD="sh -c 'tail -f ~/.my-agent/stream.log'"

# 3. a stream to watch AND a prompt to type at, in one pane
OFFICE_CHAT_CMD="sh -c 'tail -f ~/.my-agent/stream.log & while read -r q; do my-agent ask \"$q\"; done'"
OFFICE_CHAT_LABEL="MY AGENT"
```

Shape 3 is what a streaming chat actually is: something following the output in
the background, and a loop reading your input. Anything that behaves like a
terminal program works, because the pane is a terminal and nothing more.

Put those lines in your `.zshrc` **above** the `source .../office.zsh` line,
then `office off` and `office on`.

## Configuration

Environment variables, set before sourcing `office.zsh`. All optional.

| variable | default | |
|---|---|---|
| `OFFICE_DEFAULT` | *(empty)* | repo that bare `office on` opens |
| `CODE_ROOT` | `~/code` | where `office pick` looks for repos |
| `OFFICE_SESSION_CMD` | `claude` | **what a session is.** Any agent CLI |
| `OFFICE_SESSION_LABEL` | `CLAUDE` | what its panes are called |
| `OFFICE_WORKTREE_DIR` | `.claude/worktrees` | where `office new` looks for worktrees, and puts the ones it creates |
| `OFFICE_EDITOR` | `$EDITOR`, else micro/nano/vi | what the editor pane opens files in. Set it to `micro` if `$EDITOR` is vim and you would rather it were not |
| `OFFICE_DEFAULT_DESKS` | `1` | sessions opened at startup |
| `OFFICE_STRIP_WIDTH` | `32` | percent of the window the right strip takes |
| `OFFICE_REAP_HOURS` | `12` | parked panes older than this are closed on `office on` |
| `OFFICE_ATTN_SECS` | `20` | how long a desk sits still before its border says **your turn** |
| `OFFICE_CTX_WARN` | `400000` | context tokens at which a desk's number takes the accent colour |
| `OFFICE_CTX_ALARM` | `600000` | ...and the alarm colour. Use `120000` / `170000` for a 200k window |
| `OFFICE_UPDATE_CHECK` | `1` | `0` stops the background `git fetch` on `office on`. The only network call there is |
| `OFFICE_CHAT_LABEL` | `AGENT CHAT` | name on the chat pane's border |
| `OFFICE_CHAT_CMD` | your shell | what the chat pane runs |
| `OFFICE_CHAT_OPEN` | on once `OFFICE_CHAT_CMD` is set | whether the chat pane opens at startup |
| `OFFICE_ON_CMD` | *(empty)* | your own command, run when you walk in |
| `OFFICE_OFF_CMD` | *(empty)* | your own command, run when you go home |
| `OFFICE_RUNNING_CHECK` | `false` | exits 0 when it is already up |

The chat pane is the interesting one. Point `OFFICE_CHAT_CMD` at whatever
talking to your agent looks like for you, and that becomes the pane:

```sh
OFFICE_CHAT_LABEL="ASK"
OFFICE_CHAT_CMD="zsh -ic my-agent-chat"
```

The always-on trio is for anything that should come up when you sit down and go
down when you leave, a local server, a tunnel, a sync daemon:

```sh
OFFICE_ON_CMD='my-stack up'
OFFICE_OFF_CMD='my-stack down'
OFFICE_RUNNING_CHECK='pgrep -q my-server'
```

(The older `OFFICE_ALWAYS_ON_START` / `_STOP` / `_CHECK` names still work.)

## If something looks stuck

Nothing here ever needs a reboot. In rough order of how often you will want them:

| what you see | what to do |
|---|---|
| changed a setting, want it live | `Ctrl-Space r`, or `tmux source-file ~/.tmux.conf` |
| one pane's keys do nothing, the arrows walk a cursor around, the others are fine | it scrolled into copy-mode. **Click in it, or press Escape.** Until 2026-08-15 only `q` did that and nothing on screen said so, so the pane read as dead |
| Shift-Enter submits instead of making a line break, and does the right thing outside the office | an old `office.tmux.conf`. `office update`, then `Ctrl-Space r`. tmux drops the modifier on any key ASCII has no byte for unless it is told not to; the office tells it |
| changed `OFFICE_CHAT_CMD`, the pane is unchanged | close it with `Ctrl-Space q`, reopen with `Ctrl-Space c` |
| `Ctrl-Space w` does nothing | `w` is gone: it is `Ctrl-Space q` now, and it is the only close key |
| need an image in a task | `Ctrl-Space n`, then paste into your agent's own prompt |
| the columns look scrambled | `office layout` |
| the file editor pane is just a shell prompt | you left the file list. `Ctrl-Space e` rebuilds it |
| the chat pane quit and left a prompt | `Ctrl-Space c` restarts it |
| a pane went red with `returned 1` | it is in a mode. Any office key now cancels it, or press `q` |
| everything is wedged | `office off`, then `office on`. That resets the layout completely |

**A parked or toggled pane keeps its old process.** After changing what a pane
*runs*, close it with `Ctrl-Space q` and reopen it rather than toggling it off and on.
The one exception is a pane that has *stopped* running it: its own key restarts it
instead of hiding it, so there is no way to end up with a pane you cannot revive.

**If a key does nothing, it is not your terminal.** Nothing office binds needs
terminal support beyond `Shift+arrow` and `Ctrl-Space`. Reload with
`Ctrl-Space r`, and if a retired key still answers somewhere, that server has
not re-read the config: `tmux source-file ~/.tmux.conf`.

## Details worth knowing

**Desk 1 is the checkout you opened. Every extra desk gets its own worktree.**
`Ctrl-Space n` takes a free worktree under `.claude/worktrees/` — nobody
sitting in it, nothing uncommitted, nothing on its branch that has not landed
in the default branch — or makes `desk-2`, `desk-3` when there is none. "Landed"
is asked by merging the branch in memory and comparing trees, not by ancestry,
so a **squash-merged** branch reads as finished instead of unfinished forever.
Anything git cannot answer means "not free", and you get a new worktree rather
than an agent dropped into somebody's branch. That is the
whole point of running several agents at once: they edit separate checkouts, so
two of them cannot land on one branch and commit over each other. When git
cannot give one (not a repo, no commit to branch from) the session still opens,
in the checkout you are in, and the status line says so. `office desk` is that
on purpose, and says it too.

**Pane numbers are ours, not tmux's.** tmux numbers panes by their position in
the layout tree, which moving a pane leaves in an order your eye disagrees with
(you get 4 = FILE EDITOR, 6 = AGENT). `office` numbers them from actual geometry, so
they always read down the left column and then down the right strip.

**Pane borders stay quiet.** A border shows the pane's number, what it is, the
key that acts on it, and what it is currently doing, but only when that last one
is worth saying: a plain shell reports the machine's hostname as its title, so
that gets suppressed rather than repeated on every pane.

**Borders carry identity, the bar carries keys.** A border shows which pane it
is, what it is, and what it is currently doing. It does not repeat the
keybindings: printing one key per border meant advertising a global action as
though it belonged to that pane, and printing all of them on all of them is
noise. They are on the status strip, once. 
**Nothing can trap you in a mode.** tmux drops a pane into view-mode on its own,
and its key table does not inherit the root one, so every key goes dead and
the pane looks frozen (often with a red `returned 1` line). Every office
keybinding exits non-zero-proof now, and the movement, zoom, close and park
keys all cancel the mode first, so there is always a way out.

**A missing column rebuilds itself.** Park every session, or every glance pane,
and tmux collapses the two-column layout: from then on the leftmost and
rightmost pane are the same one, and everything coming back lands in a single
tall stack. Only a window with one pane can be split into two root-level
columns, so when the shape is wrong `office` breaks the panes out, keeps one,
and re-joins them in order. `office layout` does it on demand.

**Pane labels are derived, not trusted.** Claude Code can move a conversation
to the background and swap which pane displays the agent list. A label pinned
at startup starts lying, and you steer by it and wonder why the arrows do
nothing. The border reads `#{pane_title}`, which is what the pane shows right
now.

**`office off` kills everything an office started.** Not just the panes:
`kill-server` only sends SIGHUP to a pane's children, which anything that
detached itself survives, and agent CLIs leave host and daemon processes behind
that no pane is the parent of. So the process *group* of every pane is taken
first and made sure of afterwards. Nothing outlives going home.

**Updates never happen behind your back.** `office on` fetches in the
background and says nothing unless you are behind, because this package is the
thing drawing your window and changing it under you mid-session is how a morning
gets ruined. `office update` is the deliberate act, and it refuses on a dirty
tree rather than merging over your edits.

**`office sweep` is for the offices you never closed.** An office survives a
closed terminal on purpose, and the cost is that one from three days ago is
still holding four agents with no window anywhere. `office sweep` lists every
detached office idle longer than 12 hours (`office sweep 2` for a shorter
threshold), asks, then closes them and everything inside. `office on` mentions
them when it finds them, and never closes them for you: one of those might be
four agents mid-task.

It is scoped to tmux sessions this tool created and nothing else. An earlier
attempt matched process *names*, which swept in the desktop app and the tmux
server itself. A broom that wide is a footgun.

**`office off` is a reset, on purpose.** It keeps nothing: not the pane sizes,
not what you parked, not the shape you dragged things into. That makes it the
fix-it-all. Whatever you broke fiddling with the layout, off and on gives you
the default office back, every time, with no saved state anywhere to explain the
difference.

**`office break` is the other half.** It detaches without stopping anything, and
because the tmux server stays alive your layout survives exactly as it was, down
to the pixel. Two verbs, two behaviours, nothing to configure.

**Keybinding output is silenced on purpose.** Stray output from a `run-shell`
binding makes tmux force the active pane into view-mode, where every office key
stops working and the pane looks frozen. Messages go to the status line
instead.

**It works with any agent CLI.** A session is just `OFFICE_SESSION_CMD`, so
`office` has no idea what Claude Code is:

```sh
OFFICE_SESSION_CMD="codex"
OFFICE_SESSION_LABEL="CODEX"
```

There is deliberately no integration with any one agent's own session manager.
An office pane is a terminal running your agent, and that is the whole
contract: whatever the agent can do in a terminal, it can do here, including
pasting images and dropping files.

## The theme, if you want it

`office.tmux.conf` ships no colours at all, so your own theme survives
installation. If you would rather take mine, it is one more line:

```tmux
source-file ~/agent-office/office.tmux.conf              # required
source-file ~/agent-office/theme/office-theme.tmux.conf  # optional
```

Source it second, because it overrides the pane border. Monochrome by
conviction: state is tone, weight and inversion, never hue, and exactly one
colour is allowed anywhere — it means **your turn**, and nothing else on the
screen is ever given it. It also brings the clickable strip described above.

**The right-hand side of the bar is yours.** The theme puts a git branch and a
clock there and nothing else. To add your own, put one line in your
`~/.tmux.conf` after the `source-file` line and it wins:

```tmux
set -g status-right "#[fg=#f6f5f1]#(~/bin/my-status)  #[fg=#6a6c77]%H:%M "
```

Whatever is in `#()` runs every five seconds and its first line is printed. Keep
it fast, keep it one line.

### And the terminal window, on iTerm2

The tmux theme paints the bar and the borders, which leaves the window itself —
background, the ANSI sixteen, the cursor, the glass — still set by your terminal.
On iTerm2 you can take that too:

```sh
~/agent-office/install.sh --theme      # or: OFFICE_ITERM_THEME=1 ~/agent-office/install.sh
```

It writes `theme/iterm-office-theme.json` into an `office` dynamic profile,
which is the *only* thing office puts in iTerm2 now that the key layer is gone.
Same palette as the tmux theme, the ANSI sixteen
desaturated toward it so `git diff` and test output stay readable without
glowing, and transparency `0.15` over a blur radius of `12`.

**It is appearance only.** No font, no shell, no key mappings: a font you do not
have installed is worse than the one you chose, so the theme does not touch it.
Your own profile's key map is copied across untouched, and office adds nothing
to it. Anything the file does not name stays inherited from your own profile.

Re-run without `--theme` and the colours stay — a dynamic profile is just a
file. To undo, delete the `office-keys.json` iTerm2 writes into
`~/Library/Application Support/iTerm2/DynamicProfiles/`, or make your old
profile the default again. (That filename is history: it used to carry the
Ctrl-Shift key map. A `--theme` install overwrites it in place, dropping those
entries, and keeps the same profile GUID so it stays your default if you made
it one.) Two numbers are worth
knowing: `Transparency` and `Blur Radius` are single keys in that JSON, so if
`0.15` is too much glass for your desktop, edit it rather than dropping the
theme.

## Your status bar stays yours

`office.tmux.conf` sets bindings, pane borders and the cursor. It sets no
colours, no status bar and no window styling, so your own theme is untouched.
The two things it does own on the border are documented in the file itself:
`@office_num` (the pane number, taken from geometry) and the derived label.

If you want office facts on your status line, they are all plain formats:

```tmux
# panes in this office
set -g status-right "#{window_panes} panes  #{session_name}"
```

Put your own `set -g pane-border-format` and status lines AFTER the
`source-file` line, and they win.

## Safety

**One network call, and you can turn it off.** `office on` runs `git fetch` in
the background against this repo's own remote, so it can tell you when you are
behind, and it never pulls on its own. That is the only socket anything here
opens: nothing is uploaded, nothing is phoned home, no telemetry, no analytics,
and there are no dependencies to install beyond the tools listed above.
`OFFICE_UPDATE_CHECK=0` and even that one is gone.

**What the installer touches**, and nothing else:

- appends one `source` line to your `.zshrc` and one to your `.tmux.conf`,
  after checking they are not already there
- with `--theme` only: reads your iTerm2 preferences, in order to copy your
  existing key mappings into the themed profile so they survive (see above),
  and writes `office-keys.json` into iTerm2's DynamicProfiles folder — the same
  file the retired chords used to live in, now overwritten without them

**What can destroy something.** Nothing here deletes a file. Every destructive
action is a tmux operation, so the blast radius is panes and sessions:

| | |
|---|---|
| `Ctrl-Space q` | close a pane, after a y/n confirmation |
| `Ctrl-Space X` | close the session, after a y/n confirmation |
| `office off` | quits every office, lists what it will do and asks first |
| `office clean` | you pick the panes, Esc closes nothing |
| `office clean --idle` | **no confirmation, by design.** It is the unattended form |

**The one thing that writes to disk** is `Ctrl-Space n` / `office new`: it runs
`git worktree add` under `.claude/worktrees/`, which adds a directory and a
branch and changes nothing in the checkout you are standing in. It reuses a
worktree that is free — nobody sitting in it, nothing uncommitted, nothing on
its branch that has not landed — before making another, and it never
removes one. Deleting a worktree is `git worktree remove <path>`, yours to run,
because a checkout an agent worked in is exactly the thing you do not want a
window manager throwing away.

The three `OFFICE_ALWAYS_ON_*` variables are evaluated as shell, because that
is what they are for. They come from your own config, so treat them the way you
treat any line in your `.zshrc`.

Pane labels are stripped of `#` before being stored. tmux renders them through
its format engine, where `#(...)` executes a shell command, so a git branch or
an `office task` description containing one would otherwise run on every
border redraw.

## Contributing

Yes, please. This is small enough that one person can read all of it in an
afternoon, which is the whole idea.

**Something is broken:** open an issue. The template asks for three commands;
paste them even when the problem looks obvious, because a key that does nothing
is almost always a terminal that never sent it, and those three lines say so
immediately.

**You want to change something:** fork, branch off `main`, open a pull request.
`main` is protected so everything lands through one, mine included. Small and
obviously-correct gets merged quickly. Anything that changes the layout model or
adds a command is worth an issue first, so you do not build something that turns
out to be out of scope.

There are no unit tests, because almost everything here is a side effect on a
live tmux server. What there is instead is five probes in `bin/` that drive a
real one, attach real clients on a pty and type raw bytes at them; CI runs every
one of them on macOS and Ubuntu, on tmux 3.7b and 3.4, on every push. For
anything a probe does not cover, say how you verified it: build a throwaway
office, look at it, tear it down. [CONTRIBUTING.md](CONTRIBUTING.md) has the exact
snippet, along with the constraints that are not obvious from reading the code.

**Especially welcome:**

- other terminals: the keys need no per-terminal layer any more, so what is
  worth reporting is any terminal where `Shift+arrow` or `Ctrl-Space` does not
  arrive as sent
- other agents: `OFFICE_SESSION_CMD` should be all it takes, and if it is not
  for yours, that is a bug worth hearing about
- Linux and WSL: the author develops on macOS, so those paths get the least
  wear

**Not in scope,** so nobody wastes an afternoon: a plugin system, a config file,
a daemon, or a dependency doing what twenty lines already do. `office off` kills
the tmux server, and everything has to survive that.

## License

MIT. See [LICENSE](LICENSE).

---

## Where this comes from

Agent Office is one of the tools **[ZyxWorks](https://runzyx.xyz)**, a product
studio and forward deployed engineering practice, built for itself and gave away.
It is the room [Zyx](https://runzyx.xyz#zyx) gets built in, and Zyx is the runtime
the studio runs on. If this is useful to you, that probably is too.

The other one is **[MurmurFlow](https://zyxworks.github.io/murmurflow/)**:
hold a key, say it, let go, and the words land at your cursor in any app,
transcribed on your own machine.

**Product:** [page](https://zyxworks.github.io/agent-office/) ·
[all our tools](https://zyxworks.com/) ·
[getting started](GETTING-STARTED.md) ·
[issues](https://github.com/ZyxWorks/agent-office/issues)

**Studio:** [what we do for companies](https://runzyx.xyz) ·
[Zyx](https://runzyx.xyz#zyx) ·
[GitHub](https://github.com/ZyxWorks)

**Legal:** [MIT licence](LICENSE) ·
[privacy](https://runzyx.xyz/legal#privacy) ·
[imprint](https://runzyx.xyz/legal#imprint)

*Agent Office is not affiliated with, endorsed by, or connected to tmux,
Anthropic, or any agent vendor.*
