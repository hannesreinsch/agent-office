#!/bin/zsh
# install.sh — wire `office` into your shell, tmux and (optionally) iTerm2.
# Idempotent: safe to re-run after a git pull.
#
#   ./install.sh            bindings only. Your colours are untouched.
#   ./install.sh --theme    also take the look: palette, transparency, blur.
#
set -e
HERE=${0:A:h}
say() { print -P "%F{green}==>%f $*" }
warn() { print -P "%F{yellow} !%f  $*" }

# The look is opt-in on purpose, the same way theme/office-theme.tmux.conf is:
# an installer that repaints a terminal you already tuned is a bad guest.
THEME=""
if [[ $1 == --theme || -n $OFFICE_ITERM_THEME ]]; then
  THEME="$HERE/theme/iterm-office-theme.json"
fi

# --- 0. what office actually needs --------------------------------------------
# Checked before anything is written, because "command not found: tmux" three
# steps later reads like the installer broke rather than like a missing package.
# Deliberately NOT an installer for any of these: piping someone else's install
# script is a thing you then owe maintenance on, and every one of these projects
# documents its own better than a third party can.
missing=()
for c in tmux fzf fd micro bat; do command -v $c >/dev/null || missing+=($c) done
if (( ${#missing} )); then
  warn "not installed: ${missing}"
  if command -v brew >/dev/null; then
    print "      brew install ${missing}"
  elif command -v apt >/dev/null; then
    print "      sudo apt install ${missing/fd/fd-find}   # fd is fd-find on Debian and Ubuntu"
  else
    print "      install them with your package manager, then run this again"
  fi
  # tmux is the whole thing. fzf and fd are the file picker and micro is what
  # edits what you pick, so office still opens without them and only that pane is
  # poorer — without micro it falls back to nano, which on macOS is pico: no
  # colours, no mouse, no visible way out. bat is only the preview's highlighting.
  if ! command -v tmux >/dev/null; then
    print -u2 " !  office is tmux. Install it and run this again."
    exit 1
  fi
fi

# --- 1. shell ----------------------------------------------------------------
RC=${ZDOTDIR:-$HOME}/.zshrc
# office is a zsh function. zsh does not have to be your login shell, but it does
# have to be installed, and this is the file it reads.
command -v zsh >/dev/null || { print -u2 " !  zsh is not installed. Install it first."; exit 1 }
[[ ${SHELL:t} == zsh ]] || warn "your login shell is ${SHELL:t}, not zsh. Start the office with: zsh -ic 'office on'"
LINE="source $HERE/office.zsh"
# Ask a real login shell, not the file: plenty of people source office.zsh from
# a file their .zshrc pulls in, and grepping only this one file would append a
# second copy every time they re-run the installer.
if zsh -ic 'whence -w office' 2>/dev/null | grep -q function; then
  say "already loaded by your zsh startup files"
elif grep -qF "$LINE" $RC 2>/dev/null; then
  say "already sourced from $RC"
else
  print "\n# office — one command for a multi-agent tmux cockpit\n$LINE" >> $RC
  say "added to $RC"
fi

# ...and on PATH, because the line above only reaches shells started after it.
# Every terminal you already have open would otherwise answer "command not
# found" until you closed it, which is what this installer used to hand people.
# A symlink is found by all of them, now.
BIN=$HOME/.local/bin
mkdir -p $BIN
ln -sf $HERE/bin/office $BIN/office
say "office is a command now: $BIN/office"
if [[ :$PATH: != *:$BIN:* ]]; then
  print "\n# office — and everything else you install for yourself\nexport PATH=\"\$HOME/.local/bin:\$PATH\"" >> $RC
  warn "$BIN was not on your PATH. Added it to $RC — new shells only"
fi

# --- 2. tmux -----------------------------------------------------------------
TLINE="source-file $HERE/office.tmux.conf"
# ~ and the full path are the same line to tmux, so match both — otherwise a
# re-run appends a duplicate that re-sources AFTER anything you set yourself.
if grep -qF -e "$TLINE" -e "source-file ${HERE/#$HOME/~}/office.tmux.conf" $HOME/.tmux.conf 2>/dev/null; then
  say "already sourced from ~/.tmux.conf"
else
  print "\n# office — bindings and pane borders (colours stay yours)\n$TLINE" >> $HOME/.tmux.conf
  say "added to ~/.tmux.conf"
  warn "if you set pane-border-format yourself, keep it AFTER that line"
fi
tmux source-file $HOME/.tmux.conf 2>/dev/null && say "reloaded a running tmux"

# --- 3. the iTerm2 look (only with --theme) -----------------------------------
# There is no key layer any more. Every office key is Shift-arrow or the
# Ctrl-Space prefix, and every terminal already sends both, so nothing here has
# to touch your keyboard map. What is left is the palette, if you asked for it.
DYN="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
# An earlier install wrote the retired Ctrl-Shift-arrow map into this same file.
# It is OVERWRITTEN here, never deleted, and both the filename and the GUID stay
# what they always were: iTerm remembers your default profile by GUID, and for
# anyone who followed the old instruction and made "office" their default,
# removing the file would take their default profile with it. The new file
# carries no "Keyboard Map" at all, which is also what drops those retired
# entries from an existing install.
if [[ -n $THEME && -d ${DYN:h} ]]; then
  mkdir -p $DYN
  python3 - "$HERE/iterm/office-profile.json" "$DYN/office-keys.json" "$THEME" <<'PROFILE'
import json, plistlib, pathlib, sys
src, dst, theme = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
prof = json.loads(src.read_text())
me = prof["Profiles"][0]

# A dynamic profile does not inherit from the profile you actually use unless it
# is told to, so a themed office profile would otherwise hand you iTerm's stock
# keyboard map and lose Natural Text Editing's option-arrow word jump. Name the
# parent, which is the whole mechanism: iTerm resolves an unspecified attribute
# against that profile every time it loads this file.
#
# It used to ALSO copy the parent's "Keyboard Map" in here, and that is the bug
# this file is not allowed to have again. A dynamic profile is rewritten from
# its JSON on every load, so a copied map is frozen at install time AND
# uneditable afterwards: a binding you add in iTerm's own settings, or one a
# tool like `claude /terminal-setup` installs next month, never reaches the
# office profile and cannot be put there. Naming the parent and writing no map
# at all gets the inheritance the copy was imitating, live and for ever.
#
# The rule, for anything added here later: office may set what office is FOR
# (its look). Nothing about your keyboard is office's to own.
pl = pathlib.Path.home()/"Library/Preferences/com.googlecode.iterm2.plist"
parent = None
if pl.exists():
    try:
        d = plistlib.loads(pl.read_bytes())
        guid = d.get("Default Bookmark Guid")
        for b in d.get("New Bookmarks", []):
            # Skip ourselves: once you follow the printed instruction and make
            # "office" the default, a re-run would otherwise parent it to itself.
            if b.get("Guid") == guid and guid != me.get("Guid"):
                parent = b.get("Name")
    except Exception:
        pass

# ...and once "office" IS your default there is no other profile to point at,
# so keep whatever the last run worked out. "Default" is the last resort: iTerm
# always has one by that name.
if not parent and dst.exists():
    try:
        parent = json.loads(dst.read_text())["Profiles"][0].get("Dynamic Profile Parent Name")
    except Exception:
        pass
me["Dynamic Profile Parent Name"] = parent or "Default"

# The look merges on top of whatever the parent profile already gives you;
# anything not in the file stays yours.
me.update({k: v for k, v in json.loads(pathlib.Path(theme).read_text()).items()
           if not k.startswith("_")})

dst.write_text(json.dumps(prof, indent=2) + "\n")
print(f"    keys inherited live from your \"{me['Dynamic Profile Parent Name']}\" profile, none written")
print("    palette, transparency and blur applied")
PROFILE
  say "iTerm2 profile written: $DYN/office-keys.json (look only, no key entries)"
  warn "iTerm2 > Settings > Profiles > 'office' > Other Actions > Set as Default"
elif [[ -n $THEME ]]; then
  say "no iTerm2: skipping the look. Every key works without it"
else
  say "the keys need no terminal setup. Want the look too? ./install.sh --theme"
fi

print
say "done. Run: office on   (here, in any shell you have open — no restart)"
