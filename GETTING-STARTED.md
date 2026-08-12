# Getting started

For anyone moving from a desktop AI app to the terminal for the first time.
No prior tmux, no prior vim, nothing assumed. Twenty minutes, once.

---

## 1. Why the terminal at all

In the desktop app you have one conversation, and it asks permission to touch
your files. In the terminal your agent *is* in your project: it reads the repo,
edits files, runs the tests, and you watch it happen.

The catch is that one agent working alone leaves you waiting. So people run
three or four at once, on different parts of the work. That is the moment the
terminal stops being pleasant: four windows, no idea which one needs you, and a
layout you rebuild every morning.

`agent-office` is one command that puts them all on one screen, in the same
place, every time.

---

## 2. The words you need

Five, and then you know the vocabulary.

| word | what it is |
|---|---|
| **terminal** | the app you type commands into. iTerm2, Terminal.app, Windows Terminal |
| **shell** | the program *inside* it that runs your commands. Usually zsh or bash |
| **tmux** | splits one terminal window into several, and keeps them running when you close it |
| **pane** | one of those splits. A pane is just a shell, with something running in it |
| **session** | in this tool, one running agent, living in one pane |

The important one is **tmux**. Without it, closing your terminal kills whatever
was running. With it, everything survives: you close the window, walk away,
come back, and your agents are still working. That is the whole reason it is
here.

---

## 3. Your first office

```sh
office on
```

```
┌─────────────────────────────┬──────────────┐
│ 1 CLAUDE                    │ 2 SHELL      │
│                             │              │
│   your agent lives here     ├──────────────┤
│                             │ 3 EDITOR     │
│                             │              │
└─────────────────────────────┴──────────────┘
```

Three panes. That is the whole tool.

**1. The agent (left, big).** Your agent, running in your project. Type here the
same way you type in the desktop app. Paste an image, drag a file in, ask it to
change something. This is where you spend your time, which is why it gets the
space.

**2. The shell (top right).** An ordinary command line, already in your project.
For `git status`, `npm test`, `ls`. You use it to *check* the agent's work: it
says it fixed the tests, so you run them.

**3. The editor (bottom right).** A file browser that follows the shell pane, so
the two work together: `cd` in the shell to aim, browse and open in the editor.
For reading what the agent did, or a quick manual fix.

There is a fourth, **chat**, closed by default. It is for agents that have a
separate conversational mode. Ignore it until you need it.

---

## 4. Moving around

**Click a pane with your mouse.** It works, and it is the honest answer for
your first day.

The keyboard version is **Ctrl+Shift and an arrow key**. Left, right, up, down,
exactly where you would expect. Only that. Do not learn more yet.

One thing worth knowing early: **Ctrl+Space, then `z`** blows the current pane
up to fill the whole window, and again to put it back. When the agent is writing
a lot and the pane feels cramped, that is the key.

That second one is the pattern for everything that is not movement: **press
Ctrl+Space, let go, then press a letter.** It is two keystrokes rather than a
three-finger chord, and unlike a chord it works in every terminal on every
operating system with nothing to set up.

---

## 5. The editor, and how to get out of it

This is the part that catches everyone, including people who have used
terminals for years.

Press **Ctrl+Space, then `e`** to open the editor pane. You get a list of files with a
search box. Type a few letters to filter, arrow up and down, **Enter** to open
one.

**It follows the shell pane.** Whatever directory the shell is standing in is
what the editor shows, listed the way a file tree reads. `cd src` in the shell,
and the editor is showing `src`. The directory is printed above the list.

To find something, just type part of its name or its folder: the list narrows as
you type. `Ctrl+Space z` zooms the pane so the list fills the screen.

Now you are inside a file, and here is the bit nobody remembers:

| key | |
|---|---|
| **Ctrl+S** | save |
| **Ctrl+Q** | close the file, back to the file list |
| **Ctrl+Z** | undo |
| **Ctrl+F** | find |
| **Esc** (at the file list) | leave the editor pane entirely |

**The editor shows these keys along its bottom edge while a file is open**, so
you do not have to remember them. Look down.

The path out is always the same: `Ctrl+Q` gets you back to the list, `Esc`
leaves the list, `Ctrl+Space e` hides the pane.

> **If your editor looks nothing like this** and shows no help at the bottom,
> you have vim, because your `$EDITOR` is set to it. If you did not choose that
> on purpose, put `export OFFICE_EDITOR=micro` in your `.zshrc`. If you did
> choose it, you already know how to quit.

---

## 6. Running more than one agent

**Ctrl+Space, then `n`** adds a second agent, below the first. Up to four. They share
the left column evenly, and each one is a separate conversation working on a
separate thing.

This is the actual point of the tool. One agent refactoring while another writes
tests, and you moving between them.

When one is finished, **Ctrl+Space, then `w`** closes that pane. It asks first.

---

## 7. The three commands worth memorising

| | |
|---|---|
| `office on` | start work. Opens everything, exactly as you left it |
| `office break` | stepping away. Detaches, and **everything keeps running**, exactly as you left it |
| `office off` | done for the day. Closes everything and **resets the layout**. Asks first |

**Closing your terminal window does not stop anything.** It is the same as
`office break`. Your agents keep working, and `office on` brings you back to
the same panes in the same places. Only `office off` actually ends things.

And `office off` is your escape hatch: it throws the layout away too, so if you
have dragged panes into a mess or something looks wrong, off and on gives you a
clean default office back. You cannot break it permanently.

That is the mental shift from a desktop app: the work is not tied to the window
you are looking at.

---

## 8. Every key, once you want them

Not for day one. Come back to this.

| | |
|---|---|
| `⌃⇧←↑↓→` | move between panes |

And `Ctrl+Space`, then:

| | |
|---|---|
| `n` | new agent session |
| `s` `e` `c` | show or hide shell / editor / chat |
| `a` | hide every agent at once, or bring them all back |
| `w` | close this pane for good |
| `x` | park this pane: hidden, still running |
| `z` | zoom this pane full screen, and back |


Each pane's top border shows the key that acts on it, and the bar along the
bottom lists the rest. **Whatever is bright on that bar is closed.**

If Ctrl+Shift+arrow does nothing, your terminal is not sending it. Use
**Ctrl+Space then an arrow** instead, or `h j k l`. Those always work.

---

## 9. When something looks stuck

Nothing here ever needs a restart of anything.

| what you see | what to do |
|---|---|
| a pane is frozen and its keys do nothing | it is in scroll mode. Press `q` |
| the panes are in silly positions | `office layout` |
| you closed something and cannot get it back | its key again, or `office show` |
| you have no idea what is running | `office doctor` |
| genuinely wedged | `office off`, then `office on`. Resets everything |

`office doctor` is worth running once now, just to see it. It lists every pane
and what it costs in memory. Agents are heavy, roughly half a gigabyte each,
which is the real reason to close ones you have finished with.

---

## 10. What to do next

1. `office on`
2. Ask the agent in pane 1 something small about your project. "What does this
   repo do?" is a fine start.
3. When it changes a file, look at it: `Ctrl+Space e`, find the file, read it,
   `Ctrl+Q`, `Esc`.
4. Run your tests in the shell pane.
5. `Ctrl+Space n`, and give the second agent something unrelated.

That is the loop. Everything else in the [README](README.md) is detail you can
pick up when you want it.
