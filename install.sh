#!/bin/zsh
# install.sh — wire `office` into your shell, tmux and (optionally) iTerm2.
# Idempotent: safe to re-run after a git pull.
set -e
HERE=${0:A:h}
say() { print -P "%F{green}==>%f $*" }
warn() { print -P "%F{yellow} !%f  $*" }

# --- 1. shell ----------------------------------------------------------------
RC=${ZDOTDIR:-$HOME}/.zshrc
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
  python3 - "$HERE/iterm/office-keys.json" "$DYN/office-keys.json" <<'PY'
import json, plistlib, pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
prof = json.loads(src.read_text())

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
            if b.get("Guid") == guid:
                inherited = dict(b.get("Keyboard Map") or {})
                prof["Profiles"][0]["Dynamic Profile Parent Name"] = b.get("Name")
    except Exception:
        pass
prof["Profiles"][0]["Keyboard Map"] = {**inherited, **prof["Profiles"][0]["Keyboard Map"]}
dst.write_text(json.dumps(prof, indent=2) + "\n")
print(f"    {len(inherited)} of your own key mappings carried over")
PY
  say "iTerm2 profile written: $DYN/office-keys.json"
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
