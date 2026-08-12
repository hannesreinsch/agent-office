# agent-office

**Run several Claude Code sessions side by side, in one window, with one
command.**

```sh
office up
```

```
┌─────────────────────────────┬──────────────┐
│ 1 CLAUDE                    │ 4 AGENT VIEW │  ⌃⇧a
│                             │              │
├─────────────────────────────┼──────────────┤
│ 2 CLAUDE 2      ⌃⇧n adds    │ 5 SHELL      │  ⌃⇧s
│                 one more    ├──────────────┤
├─────────────────────────────┤ 6 EDITOR     │  ⌃⇧e
│ 3 CLAUDE 3                  ├──────────────┤
│                             │ 7 AGENT CHAT │  ⌃⇧c
└─────────────────────────────┴──────────────┘
        your agents               you, watching
```

Agents own the wide left column, stacked and kept at equal height. Everything
you only glance at shares the narrow strip on the right, and each of those four
panes opens and closes with one chord. Closing the window kills nothing:
`office up` puts you back exactly where you were, panes, layout and all.

## Why

Running three or four coding agents at once is normal now, and the tooling for
it is not. You end up with a pile of terminal tabs, no idea which one is
waiting on you, and a layout you rebuild by hand every morning.

`office` is one command that opens the whole thing, one chord scheme to move
around it, and no state you have to maintain. It is about 600 lines of zsh and
a tmux config. There is no daemon, no plugin manager, and no config file.

## Install

```sh
git clone https://github.com/hannesreinsch/agent-office.git ~/code/agent-office
~/code/agent-office/install.sh
exec zsh && office up
```

The installer appends one line to your `.zshrc`, one line to your `.tmux.conf`,
and writes an iTerm2 profile if you have iTerm2. It is idempotent, so re-run it
after a `git pull`. To do it by hand instead:

```sh
# .zshrc
source ~/code/agent-office/office.zsh
# .tmux.conf
source-file ~/code/agent-office/office.tmux.conf
```

**Requires:** `tmux` 3.4 or newer, `zsh`, `git`, [`fzf`](https://github.com/junegunn/fzf),
[`fd`](https://github.com/sharkdp/fd), and of course
[Claude Code](https://claude.com/claude-code).
**Optional:** [`micro`](https://micro-editor.github.io) for the editor pane,
[`bat`](https://github.com/sharkdp/bat) for its file preview, iTerm2 for the
Ctrl-Shift chords.

## Three commands

`office up`, `office break`, `office off`. Everything else has a key.

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
| `⌃⇧n` | new Claude session, appended to the left column |
| `⌃⇧t` | **type a task, get a session already working on it** |
| `⌃⇧a` `⌃⇧s` `⌃⇧e` `⌃⇧c` | toggle agent view / shell / editor / chat |
| `⌃⇧w` | close this pane, and get the memory back |
| `⌃⇧x` | park this pane, still running, same key brings it back |
| `⌃⇧z` | zoom this pane fullscreen and back |

Every one also works as `Ctrl-Space` then the same letter, so nothing depends
on the chord layer. The mouse works too: click a pane to focus it, drag a
border to resize, and your layout is remembered.

### Typing a task without knowing the chord

`⌃⇧t` opens a prompt on the status bar. If you would rather not remember a
chord, put a field there that is always visible and opens the same prompt when
you click it:

```tmux
set -g status-left "#[range=user|task] task: ⌃⇧t #[norange]"
set -g status-left-length 24
bind -n MouseDown1Status if -F '#{==:#{mouse_status_range},user}' \
  { command-prompt -p "task:" 'run-shell -b "zsh -ic \"cd \\\"#{pane_current_path}\\\" && office task \\\"%%\\\"\" >/dev/null 2>&1"' } \
  { select-window -t= }
```

**That prompt takes text only.** You can paste text into it, but not an image
and not a dragged file: it is a tmux input, and tmux has no idea what an image
is. When a task needs one, open an empty session with `⌃⇧n` and paste into
Claude Code's own prompt, which handles images and file drops. `⌃⇧t` is the
fast path for a task you can say in a sentence.

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

`⌃⇧w` closes a pane for good. Parking is not free, a parked Claude session
still holds its 400 to 700MB, and `office doctor` lists parked panes alongside
live ones for exactly that reason.

## Commands

| | |
|---|---|
| `office up` | walk in: open the office, start your always-on stack |
| `office break` | step out: detach, everything keeps running |
| `office off` | go home: quit every office, stop the stack, asks first |
| `office <name>` | open another repo by fuzzy name |
| `office pick` | fuzzy-pick from every repo under `$CODE_ROOT` |
| `office desk` | one more Claude session |
| `office task <what>` | one more Claude session, already working on `<what>` |
| `office new [wt]` | one more Claude session in its own git worktree |
| `office chat` `shell` `agents` `edit` | toggle a right-strip pane |
| `office hide` / `office show` | park the current pane / bring one back |
| `office doctor` | what is running and what it costs in RAM, read-only |
| `office clean` | pick panes to close, heaviest first (rarely needed) |
| `office clean --idle [h]` | no picker: close anything idle over `h` hours |
| `office fixagents` | restart the agent view when it stops responding |
| `office help` | all of the above, with the diagram |

The command is `office`. `ao` and `o` are aliases for it.

## Configuration

Environment variables, set before sourcing `office.zsh`. All optional.

| variable | default | |
|---|---|---|
| `OFFICE_DEFAULT` | *(empty)* | repo that bare `office on` opens |
| `CODE_ROOT` | `~/code` | where `office pick` looks for repos |
| `OFFICE_DEFAULT_DESKS` | `1` | Claude sessions opened at startup |
| `OFFICE_REAP_HOURS` | `12` | parked panes older than this are closed on `office up` |
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
| agent view will not scroll or accept typing | `office fixagents` |
| one pane's keys do nothing, the others are fine | it is in tmux copy-mode. Press `q` |
| changed `OFFICE_CHAT_CMD`, the pane is unchanged | close it with `⌃⇧w`, reopen with `⌃⇧c` |
| the chords do nothing at all | the iTerm profile is not your default. See below |
| need an image in a task | `⌃⇧n`, then paste into Claude's own prompt |
| everything is wedged | `office off`, then `office up`. Only the panes are lost |

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

**What it cannot do:** a session dispatched from inside the agent view can
never become a pane. It belongs to Claude Code's daemon, and Claude Code
refuses a second attachment in as many words:

```
Session ... is currently running as a background agent (bg).
Use `claude agents` to find and attach to it, or add --fork-session
to branch off a copy.
```

Forking would give you a second agent duplicating the first one's work, which
is worse than useless. So `office` goes through the door that does work:
`⌃⇧t`, type the task, and a Claude session opens in the left column already
working on it. Same thought, one keystroke, and it is a real pane.

## Your status bar stays yours

`office.tmux.conf` sets bindings, pane borders and the cursor. It sets no
colours, no status bar and no window styling, so your own theme is untouched.
The two things it does own on the border are documented in the file itself:
`@office_num` (the pane number, taken from geometry) and the derived label.

If you want office facts on your status line, they are all plain formats:

```tmux
# panes in this office, and whether any Claude is waiting on you
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
| `office fixagents` | restarts the agent view's process, losing nothing else |

The three `OFFICE_ALWAYS_ON_*` variables are evaluated as shell, because that
is what they are for. They come from your own config, so treat them the way you
treat any line in your `.zshrc`.

Pane labels are stripped of `#` before being stored. tmux renders them through
its format engine, where `#(...)` executes a shell command, so a git branch or
an `office task` description containing one would otherwise run on every
border redraw.

## License

MIT. See [LICENSE](LICENSE).

---

Built by [Hannes Reinsch](https://github.com/hannesreinsch) while building
[Zyx](https://runzyx.xyz), an AI company runtime that lives inside the tools
you already use. If `agent-office` is useful to you, that probably is too.
