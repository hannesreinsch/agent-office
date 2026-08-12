# agent-office

**Run several coding-agent sessions side by side, in one window, with one
command.** Claude Code out of the box, any agent CLI with one variable.

```sh
office on
```

```
┌─────────────────────────────┬──────────────┐
│ 1 CLAUDE                    │ 4 SHELL      │  ⌃⇧s
│                             │              │
├─────────────────────────────┼──────────────┤
│ 2 CLAUDE 2      ⌃⇧n adds    │ 5 EDITOR     │  ⌃⇧e
│                 one more    │              │
├─────────────────────────────┼──────────────┤
│ 3 CLAUDE 3                  │ 6 AGENT CHAT │  ⌃⇧c
│                             │              │
└─────────────────────────────┴──────────────┘
        your agents               you, working
```

Agents own the wide left column, stacked and kept at equal height. Everything
you only glance at shares the narrow strip on the right, and each of those four
panes opens and closes with one chord. Closing the window kills nothing:
`office on` puts you back exactly where you were, panes, layout and all.

## Why

Running three or four coding agents at once is normal now, and the tooling for
it is not. You end up with a pile of terminal tabs, no idea which one is
waiting on you, and a layout you rebuild by hand every morning.

`office` is one command that opens the whole thing, one chord scheme to move
around it, and no state you have to maintain. It is about 600 lines of zsh and
a tmux config. There is no daemon, no plugin manager, and no config file.

## Setup

### macOS

```sh
brew install tmux fzf fd micro bat          # needs Homebrew: https://brew.sh
git clone https://github.com/hannesreinsch/agent-office.git ~/agent-office
~/agent-office/install.sh
exec zsh && office on
```

Clone it wherever you like; the installer works out its own path. Examples in
this README use `~/agent-office`.

The installer adds one line to your `.zshrc`, one to your `.tmux.conf`, and if
you use iTerm2 it writes a profile carrying the one-key chords. It prints the
single manual step: **iTerm2 > Settings > Profiles > "office" > Other Actions >
Set as Default**, then open a new window.

**You do not need iTerm2.** Terminal.app, Ghostty, WezTerm and Alacritty all
work; you lose only the one-key form, and `Ctrl-Space` then the same letter does
everything. Apple Silicon and Intel are identical here, it is all shell.

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
git clone https://github.com/hannesreinsch/agent-office.git ~/agent-office
~/agent-office/install.sh
exec zsh && office on
```

That is Ubuntu or Debian, which is what `wsl --install` gives you. On Fedora or
Arch swap in `dnf` or `pacman`; the package names are the same and `fd` is not
renamed there.

The installer detects WSL and points at `terminals/windows-terminal-keys.json`.
Paste those entries into Windows Terminal (Settings, then "open JSON file") for
the one-key chords. Skip it and `Ctrl-Space` plus the letter still does
everything.

### Any other terminal

The chords are ordinary escape sequences. Make `Ctrl-Shift+<letter>` send `ESC`
followed by that letter, and `Ctrl-Shift+<arrow>` send `CSI 1;6 A-D`. The files
in `terminals/` and `iterm/` are worked examples of exactly that.

**A note if you do not use zsh.** `office` is a zsh function, so zsh has to be
installed, but it does not have to be your login shell: run `zsh` and source it
there, or add `source /path/to/office.zsh` to a zsh startup file and start your
day with `zsh -ic 'office on'`. Everything inside the panes is your normal
shell.

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

| chord | |
|---|---|
| `⌃⇧←↑↓→` | move between panes |
| `⌃⇧n` | new session, appended to the left column |
| `⌃⇧t` | **type a task, get a session already working on it** |
| `⌃⇧s` `⌃⇧e` `⌃⇧c` | toggle shell / editor / chat |
| `⌃⇧a` | park every session at once, or bring them all back |
| `⌃⇧w` | close this pane, and get the memory back |
| `⌃⇧x` | park this pane, still running, same key brings it back |
| `⌃⇧z` | zoom this pane fullscreen and back |

Every one also works as `Ctrl-Space` then the same letter, so nothing depends
on the chord layer. The mouse works too: click a pane to focus it, drag a
border to resize, and your layout is remembered.

### The keys are on the status bar

A pane's border carries the chord that toggles it, which is no help at all once
the pane is closed and the border went with it. So the bar carries the whole
set:

```
+ new ⌃⇧n   │  sessions ⌃⇧a · shell ⌃⇧s · editor ⌃⇧e · chat ⌃⇧c
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


### Why Ctrl-Shift needs iTerm2 for the letters

A terminal cannot encode Ctrl+Shift for a letter. `Ctrl+Z` and `Ctrl+Shift+Z`
arrive as the same byte, `0x1A`, because Shift is simply not part of the wire
format for control characters. Arrows are the exception: they travel as
`CSI 1;6 A-D`, with the modifier as a number.

So the letter chords are made real one level lower: an iTerm2 dynamic profile
rewrites each one to `ESC`+letter, and tmux reads that as `M-<letter>`. That is
all `iterm/office-keys.json` does. Without iTerm2 you lose nothing except the
one-key form, because the `Ctrl-Space` prefix covers every command.

Two things the installer handles that are easy to get wrong by hand:

- A dynamic profile **replaces** the parent profile's keyboard map instead of
  merging into it. Your existing entries (Natural Text Editing's option-arrow
  word jump, option-delete, cmd-arrow line ends) vanish silently. The installer
  copies them over first.
- iTerm watches the DynamicProfiles **folder**. A symlink pointing out of it
  will not trigger a reload when you edit the target, so the file is written
  into the folder directly.

## Park versus close

`⌃⇧x` parks a pane: it is moved to a hidden tmux session and keeps running.
Its own toggle brings it back, in its proper place, or `office show` picks from
everything parked.

`⌃⇧w` closes a pane for good. Parking is not free, a parked agent session
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
| `office desk` | one more session |
| `office task <what>` | one more session, already working on `<what>` |
| `office new [wt]` | one more session in its own git worktree |
| `office chat` `shell` `edit` | toggle a right-strip pane |
| `office sessions` | park or restore the whole left column |
| `office renumber` | renumber the panes (the tmux hooks call this) |
| `office hide` / `office show` | park the current pane / bring one back |
| `office doctor` | what is running and what it costs in RAM, read-only |
| `office clean` | pick panes to close, heaviest first (rarely needed) |
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

That is the whole integration. `⌃⇧n` opens one. `⌃⇧t` opens one already working
on a task, by running `$OFFICE_SESSION_CMD "<your task>"`, so that one needs an
agent that takes a prompt as its first argument. If yours does not, `⌃⇧n` still
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
| `OFFICE_WORKTREE_DIR` | `.claude/worktrees` | where `office new` looks for worktrees |
| `OFFICE_EDITOR` | `$EDITOR`, else micro/nano/vi | what the editor pane opens files in |
| `OFFICE_DEFAULT_DESKS` | `1` | sessions opened at startup |
| `OFFICE_REAP_HOURS` | `12` | parked panes older than this are closed on `office on` |
| `OFFICE_CHAT_LABEL` | `AGENT CHAT` | name on the chat pane's border |
| `OFFICE_CHAT_CMD` | your shell | what the chat pane runs |
| `OFFICE_ALWAYS_ON_CHECK` | `false` | exits 0 when your stack is up |
| `OFFICE_ALWAYS_ON_START` | *(empty)* | run by `office on` |
| `OFFICE_ALWAYS_ON_STOP` | *(empty)* | run by `office off` |

The chat pane is the interesting one. Point `OFFICE_CHAT_CMD` at whatever
talking to your agent looks like for you, and that becomes the pane:

```sh
OFFICE_CHAT_LABEL="ASK"
OFFICE_CHAT_CMD="zsh -ic my-agent-chat"
```

The always-on trio is for anything that should come up when you sit down and go
down when you leave, a local server, a tunnel, a sync daemon:

```sh
OFFICE_ALWAYS_ON_CHECK='pgrep -q my-server'
OFFICE_ALWAYS_ON_START='my-stack up'
OFFICE_ALWAYS_ON_STOP='my-stack down'
```

## If something looks stuck

Nothing here ever needs a reboot. In rough order of how often you will want them:

| what you see | what to do |
|---|---|
| changed a setting, want it live | `Ctrl-Space r`, or `tmux source-file ~/.tmux.conf` |
| one pane's keys do nothing, the others are fine | it is in tmux copy-mode. Press `q` |
| changed `OFFICE_CHAT_CMD`, the pane is unchanged | close it with `⌃⇧w`, reopen with `⌃⇧c` |
| the chords do nothing at all | the iTerm profile is not your default. See below |
| need an image in a task | `⌃⇧n`, then paste into your agent's own prompt |
| the columns look scrambled | `office layout` |
| a pane went red with `returned 1` | it is in a mode. Any office chord now cancels it, or press `q` |
| everything is wedged | `office off`, then `office on`. Only the panes are lost |

**A parked or toggled pane keeps its old process.** After changing what a pane
*runs*, close it with `⌃⇧w` and reopen it rather than toggling it off and on.

**If the chords do nothing:** iTerm2 > Settings > Profiles > "office" > Other
Actions > Set as Default, then open a new window. Until then, `Ctrl-Space` and
the same letter does everything the chords do.

## Details worth knowing

**Pane numbers are ours, not tmux's.** tmux numbers panes by their position in
the layout tree, which moving a pane leaves in an order your eye disagrees with
(you get 4 = EDITOR, 6 = AGENT). `office` numbers them from actual geometry, so
they always read down the left column and then down the right strip.

**Each pane's border shows the key that acts on it**: the chord that toggles a
glance pane, `⌃⇧w` on a session, since closing is what you want from those. 
**Nothing can trap you in a mode.** tmux drops a pane into view-mode on its own,
and its key table does not inherit the root one, so every chord goes dead and
the pane looks frozen (often with a red `returned 1` line). Every office
keybinding exits non-zero-proof now, and the movement, zoom, close and park
chords all cancel the mode first, so there is always a way out.

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

**Your layout is remembered.** Drag the borders where you want them. A detach
keeps the layout because the tmux server is still alive; `office off` kills the
server, which is the one moment it would be lost, so that is where it is saved
to `~/.local/state/office/`.

**Keybinding output is silenced on purpose.** Stray output from a `run-shell`
binding makes tmux force the active pane into view-mode, where every Ctrl-Shift
chord stops working and the pane looks frozen. Messages go to the status line
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
colour is allowed on the bar. It also brings the clickable `task:` field
described above, and a hook for your own status line:

```sh
OFFICE_STATUS_CMD=~/bin/my-status   # prints one line, refreshed every 5s
```

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

No network calls anywhere in the code. Nothing is uploaded, phoned home or
fetched at runtime, and there are no dependencies to install beyond the tools
listed above.

**What the installer touches**, and nothing else:

- appends one `source` line to your `.zshrc` and one to your `.tmux.conf`,
  after checking they are not already there
- reads your iTerm2 preferences, in order to copy your existing key mappings
  into the new profile so they survive (see above)
- writes `office-keys.json` into iTerm2's DynamicProfiles folder

**What can destroy something.** Every destructive action is a tmux operation,
so the blast radius is panes and sessions, never files:

| | |
|---|---|
| `⌃⇧w`, `prefix x` | close a pane, after a y/n confirmation |
| `prefix X` | close the session, after a y/n confirmation |
| `office off` | quits every office, lists what it will do and asks first |
| `office clean` | you pick the panes, Esc closes nothing |
| `office clean --idle` | **no confirmation, by design.** It is the unattended form |

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

There is no test suite, because almost everything here is a side effect on a
live tmux server. Instead, say how you verified it: build a throwaway office,
look at it, tear it down. [CONTRIBUTING.md](CONTRIBUTING.md) has the exact
snippet, along with the constraints that are not obvious from reading the code.

**Especially welcome:**

- other terminals: the chord layer is two files in `terminals/` and `iterm/`,
  and Ghostty, WezTerm, Kitty and Alacritty all deserve one
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

Built by [Hannes Reinsch](https://github.com/hannesreinsch) while building
[Zyx](https://runzyx.xyz), an AI company runtime that lives inside the tools
you already use. If `agent-office` is useful to you, that probably is too.
