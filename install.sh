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

# --- 1. shell ----------------------------------------------------------------
RC=${ZDOTDIR:-$HOME}/.zshrc
# office is a zsh function. zsh does not have to be your login shell, but it does
# have to be installed, and this is the file it reads.
command -v zsh >/dev/null || { print -u2 " !  zsh is not installed. Install it first."; exit 1 }
[[ ${SHELL:t} == zsh ]] || warn "your login shell is ${SHELL:t}, not zsh. Start the office with: zsh -ic 'office on'"
LINE="source $HERE/office.zsh"
if grep -qF "$LINE" $RC 2>/dev/null; then
  say "already sourced from $RC"
else
  print "\n# office — one command for a multi-agent tmux cockpit\n$LINE" >> $RC
  say "added to $RC"
fi

# --- 2. tmux -----------------------------------------------------------------
TLINE="source-file $HERE/office.tmux.conf"
if grep -qF "$TLINE" $HOME/.tmux.conf 2>/dev/null; then
  say "already sourced from ~/.tmux.conf"
else
  print "\n# office — bindings and pane borders (colours stay yours)\n$TLINE" >> $HOME/.tmux.conf
  say "added to ~/.tmux.conf"
  warn "if you set pane-border-format yourself, keep it AFTER that line"
fi
tmux source-file $HOME/.tmux.conf 2>/dev/null && say "reloaded a running tmux"

# --- 3. the chord layer (optional, per terminal) ------------------------------
# Only the terminal can deliver Ctrl-Shift plus a LETTER: that combination has
# no encoding (Ctrl+Z and Ctrl+Shift+Z are the same byte), so the terminal has
# to translate the chord and send ESC+letter. Skip this and everything still
# works with the Ctrl-Space prefix.
DYN="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
if [[ -d ${DYN:h} ]]; then
  mkdir -p $DYN
  python3 - "$HERE/iterm/office-keys.json" "$DYN/office-keys.json" "$THEME" <<'PY'
import json, plistlib, pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
theme = sys.argv[3] if len(sys.argv) > 3 else ""
prof = json.loads(src.read_text())
me = prof["Profiles"][0]

# A dynamic profile REPLACES the parent's keyboard map rather than merging into
# it, so a user's existing entries (Natural Text Editing's option-arrow word
# jump, option-delete, cmd-arrow line ends) would silently disappear. Carry them
# over; ours win on a collision.
pl = pathlib.Path.home()/"Library/Preferences/com.googlecode.iterm2.plist"
inherited = {}
if pl.exists():
    try:
        d = plistlib.loads(pl.read_bytes())
        guid = d.get("Default Bookmark Guid")
        for b in d.get("New Bookmarks", []):
            # Skip ourselves: once you follow the printed instruction and make
            # "office" the default, a re-run would otherwise parent this profile
            # to itself.
            if b.get("Guid") == guid and guid != me.get("Guid"):
                inherited = dict(b.get("Keyboard Map") or {})
                me["Dynamic Profile Parent Name"] = b.get("Name")
    except Exception:
        pass

# ...and once "office" IS your default there is no other profile left to read,
# so the answer is whatever the last run already worked out. Without this, the
# second install after following the instruction above silently hands your
# option-arrow word jump back.
if not inherited and dst.exists():
    try:
        prev = json.loads(dst.read_text())["Profiles"][0]
        inherited = dict(prev.get("Keyboard Map") or {})
        if prev.get("Dynamic Profile Parent Name"):
            me["Dynamic Profile Parent Name"] = prev["Dynamic Profile Parent Name"]
    except Exception:
        pass

me["Keyboard Map"] = {**inherited, **me["Keyboard Map"]}

# The look, only when asked for. Appearance keys merge on top of whatever the
# parent profile already gives you; anything not in the file stays yours.
if theme:
    look = json.loads(pathlib.Path(theme).read_text())
    me.update({k: v for k, v in look.items() if not k.startswith("_")})

dst.write_text(json.dumps(prof, indent=2) + "\n")
print(f"    {len(inherited)} of your own key mappings carried over")
if theme:
    print("    palette, transparency and blur applied")
PY
  say "iTerm2 profile written: $DYN/office-keys.json"
  [[ -n $THEME ]] || print "      (bindings only. Want the look too? ./install.sh --theme)"
  warn "iTerm2 > Settings > Profiles > 'office' > Other Actions > Set as Default"
elif [[ -n $WSL_DISTRO_NAME || -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
  say "WSL detected. For the one-key chords, add the bindings from"
  print "      $HERE/terminals/windows-terminal-keys.json"
  print "      to Windows Terminal: Settings, then \"open JSON file\"."
  warn "until then, Ctrl-Space and the same letter does everything"
else
  say "no iTerm2 and no WSL: skipping the chord layer"
  warn "Ctrl-Space and the same letter does everything the chords do"
  print "      To wire the chords up in your own terminal, make Ctrl-Shift+<letter>"
  print "      send ESC followed by that letter. See terminals/ for two examples."
fi

print
say "done. Open a new shell and run: office on"
