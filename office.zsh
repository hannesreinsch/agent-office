# agent-office — ONE command: `office`.
#
# https://github.com/hannesreinsch/agent-office
#
#   office on         walk in — open your office and start the day
#   office break      step out — detach; panes, sizes and agents all stay put
#   office off        go home — quit everything, and reset the layout to default
#
#   office <repo>     open a different repo (fuzzy name, e.g. `office myproj`)
#   office pick       fuzzy-pick from all your repos
#   office solo       like `on`, but start nothing but the tabs
#
#   office new [wt]   another session, in its OWN git worktree           (^Sn)
#   office task ...   another session, started on a task straight away
#   office desk       another session in THIS checkout, when you mean it
#   office chat       toggle the chat pane                           (^Sc)
#   office shell      toggle the shell pane                          (^Ss)
#   office edit       toggle the editor pane                         (^Se)
#   office hide/show  collapse the pane you are on / bring one back  (^Sx)
#   office layout     rebuild the two columns if they ever look wrong
#
#   office doctor     what's running and what it costs in RAM (read-only)
#   office clean      pick panes to close and reclaim their RAM
#   office sweep      close offices you walked away from, and all they run
#   office update     pull the newest agent-office (never happens on its own)
#
# Bare `office` prints this. `ao` and `o` are the short aliases.
# Key bindings live in office.tmux.conf; `office help` lists every one of them.
# Configure with the OFFICE_* variables below; see the README.

_OFFICE_OWN_PGID=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
_OFFICE_HOME=${0:A:h}                  # where this package lives, for its helpers
zmodload -F zsh/stat b:zstat 2>/dev/null
# what was on disk when this shell loaded it — see office() for why.
_OFFICE_MTIME=$(zstat +mtime "$_OFFICE_HOME/office.zsh" 2>/dev/null)
CODE_ROOT="${CODE_ROOT:-$HOME/code}"
OFFICE_DEFAULT="${OFFICE_DEFAULT:-}"        # repo `office on` opens; empty = the one you are in
# The chat pane: whatever talking to your agent looks like. Point it at your own
# chat command and it becomes that. Left as a plain shell by default.
# What a session IS. Point it at any agent CLI and the left column becomes that.
OFFICE_SESSION_CMD="${OFFICE_SESSION_CMD:-claude}"
# How every desk ends. Quitting the agent leaves the pane on a prompt — nothing
# is lost and the pane is yours — but a border still labelled CLAUDE over a bare
# shell reads like a broken window to anyone new. One line says otherwise.
# printf, not print: this string is run by tmux's default shell, not by zsh.
_OFFICE_DESK_END="; printf '\n  session ended — the pane is a shell now. Ctrl-Space n opens a new one.\n'; exec zsh"
OFFICE_SESSION_LABEL="${OFFICE_SESSION_LABEL:-CLAUDE}"
# Where `office new` looks for git worktrees. Claude Code's default location.
OFFICE_WORKTREE_DIR="${OFFICE_WORKTREE_DIR:-.claude/worktrees}"
# How much of the window the right strip takes. Wide enough that a chat pane
# does not wrap every sentence, narrow enough that the agents keep the room.
OFFICE_STRIP_WIDTH="${OFFICE_STRIP_WIDTH:-32}"
OFFICE_CHAT_LABEL="${OFFICE_CHAT_LABEL:-AGENT CHAT}"
_OFFICE_CHAT_UNSET="exec $SHELL"
OFFICE_CHAT_CMD="${OFFICE_CHAT_CMD:-$_OFFICE_CHAT_UNSET}"
# Open the chat pane at startup when there is actually a chat to open, which is
# the moment you point OFFICE_CHAT_CMD at your own agent. Left at its default it
# would just be a fourth shell, so it stays closed. OFFICE_CHAT_OPEN=1 or 0
# decides it outright.
[[ -n $OFFICE_CHAT_OPEN ]] || { [[ $OFFICE_CHAT_CMD == $_OFFICE_CHAT_UNSET ]] && OFFICE_CHAT_OPEN=0 || OFFICE_CHAT_OPEN=1 }

# ---------------------------------------------------------------- internals --
_office_sessname() { basename "$1" | tr ' .:' '___'; }
_office_root()     { git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null || print -r -- "${1:-$PWD}"; }

# Stand where the key was pressed. The bindings hand the pane's path in here
# instead of doing their own `cd`, because that pane can be standing in a
# directory that is GONE — a session worktree reaped by a sweep while its agent
# was still sat in it, which is the normal end of a desk's life. The bindings
# read `cd "<pane path>" && office …`, so the failed `cd` took the whole line
# with it and the key did NOTHING: not one broken key, EVERY office key in that
# pane, and silently, because a keybinding's output is muted on purpose. The
# nearest directory that is still there is inside the same repo, which is all
# any command here asks of $PWD.
_office_pane_cwd() {
  local d=${OFFICE_PANE_PATH:-}
  unset OFFICE_PANE_PATH
  [[ -n $d ]] || return 0
  until [[ -d $d ]]; do d=${d:h}; done   # :h of / is /, so this always lands
  cd "$d"
}

# WHICH office this pane is in. Ask tmux, never $PWD: deriving it from the
# directory meant one `cd` out of the repo (or into a different one) renamed the
# office out from under every helper — the editor stopped following the shell,
# and `office n`/`layout`/`show` quietly targeted a session that did not exist.
# Outside tmux there is no pane to ask, so the directory is still the answer.
_office_here() {
  local s
  [[ -n $TMUX ]] && s=$(tmux display -p -t "${TMUX_PANE:-}" '#{session_name}' 2>/dev/null)
  [[ -n $s ]] && print -r -- "$s" || _office_sessname "$(_office_root "$PWD")"
}

# every git repo under $CODE_ROOT, agent worktrees excluded
_office_repos() {
  fd --type d --max-depth 4 --hidden --no-ignore '^\.git$' "$CODE_ROOT" 2>/dev/null \
    | sed 's|/\.git/*$||' | grep -v "/${OFFICE_WORKTREE_DIR}/" | sort -u
}

_office_find() {                       # <name> -> absolute repo path
  local q=$1 hit
  [[ -d $q ]] && { (cd "$q" && pwd); return }
  hit=$(_office_repos | grep -iE "/${q}$" | head -1)
  [[ -n $hit ]] || hit=$(_office_repos | grep -i -- "$q" | head -1)
  [[ -n $hit ]] && print -r -- "$hit"
}

# attach. Plain tmux on purpose: ONE iTerm2 window, real splits inside it.
# (Control mode, -CC, turns every pane into a separate native iTerm2 tab, which
# is the opposite of a cockpit. It was behind an env var nobody ever set.)
_office_attach() {
  local s=$1
  if [[ -n $TMUX ]]; then tmux switch-client -t "=$s"
  else tmux attach-session -t "=$s"; fi
}

# A tmux server holds the config it read the day it started. Pull the package,
# move it, or edit a binding, and the server you walk back into is still on the
# old one — silently, which is worse than an error. Walking in is the moment to
# re-read it. ~/.tmux.conf and not office.tmux.conf: it sources the package AND
# the theme, in the order the theme needs (it overrides the pane border, so it
# has to come second). Same file `Ctrl-Space r` reloads.
_office_reload_conf() { tmux source-file ~/.tmux.conf 2>/dev/null }

# ZOOM LIES ABOUT GEOMETRY, and every layout answer in this file is geometry.
# While a pane is zoomed, tmux reports THAT pane at full-window coordinates:
# pane_left 0, pane_top 1, the whole width. The other panes keep their old
# numbers. So `_office_desk_pane` picks the zoomed pane as the bottom desk,
# `_office_desk_count` counts it into the left column, `_office_even_column`
# resizes a column that is not there, `_office_number` numbers by a position
# nothing is at — and `_office_layout_ok` sees a strip pane sitting at left 0,
# calls the office broken, and hands it to `_office_relayout`, which breaks
# EVERY pane out to the stash and rejoins them, all from a lie. That is how
# zooming a session and unzooming it again left one shell on screen.
#
# tmux was never going to keep the zoom anyway: its own resize-pane unzooms the
# window silently (check window_zoomed_flag after one). So drop it FIRST and on
# purpose. An office command that touches the room shows you the room.
_office_unzoom() {                     # <session>
  # A pane id, and nothing shorter. `resize-pane -t "=<session>"` is not a
  # target tmux accepts ("can't find pane"), and display-message -t "=session"
  # returns EMPTY for window flags — the same trap as window_height in
  # _office_even_column. Both fail silently, which is a guard that guards
  # nothing. Ask for the panes instead: the ACTIVE pane of every zoomed window,
  # which is the only pane a window can be zoomed on.
  local p n=0
  for p in ${(f)"$(tmux list-panes -s -t "=$1" -F '#{pane_id}' \
                   -f '#{&&:#{pane_active},#{window_zoomed_flag}}' 2>/dev/null)"}; do
    # ++n, never n++: post-increment EVALUATES to the OLD value, so `(( n++ ))`
    # on the first pane is arithmetic-false, ends the && chain, and in a shell
    # with err_return set returns out of whatever called this.
    [[ -n $p ]] && tmux resize-pane -Z -t "$p" 2>/dev/null && (( ++n ))
  done
  # and SAY so. The zoom going away silently is the half of this the operator
  # actually felt: the room came back while he was looking at one pane, so the
  # next Ctrl-Space z — pressed to zoom OUT — zoomed IN on whatever pane the
  # command had just left him on, and the screen went down to that one pane.
  # A toggle is never wrong about the state. It was the state that moved.
  (( n )) && _office_say "unzoomed — Ctrl-Space z zooms again"
  return 0
}

# the BOTTOM desk in the left column: a new session is split off it, so sessions
# append downwards and their numbers stay in the order you opened them. Splitting
# the tallest instead would drop session 3 in between 1 and 2.
# Returns a pane id (%N), the only target type that is unambiguous. The right
# strip is excluded structurally, by having a greater pane_left than the
# column's, so no label matching is involved.
_office_desk_pane() {
  tmux list-panes -t "=$1" -F '#{pane_left} #{pane_top} #{pane_id}' 2>/dev/null \
    | sort -k1,1n -k2,2nr | awk 'NR==1 { print $3 }'
}

# how many desks the left column is holding. Four is the cap: a fifth session in
# a 50-row window gets ~9 rows, which is not a desk, it is a slit.
_OFFICE_MAX_DESKS=4
_office_desk_count() {
  tmux list-panes -t "=$1" -F '#{pane_left}' 2>/dev/null \
    | sort -n | awk 'NR==1 {l=$1} $1==l {n++} END {print n+0}'
}

# --- the editor pane ---------------------------------------------------------
# Shipped, not assumed. This used to call a function that happened to exist on
# the author's machine, which meant the editor pane died with "command not
# found" for everybody else.
#
# $OFFICE_EDITOR, else $EDITOR, else the first of micro / nano / vi that is
# installed. micro first because it is the one you can drive with no manual:
# Ctrl-S saves, Ctrl-Q quits, arrows and the mouse behave.
_office_editor() {
  local e
  for e in $OFFICE_EDITOR $EDITOR micro nano vi; do
    # ${e%% *}, not ${${(z)e}[1]}: a nested substitution that produced ONE word
    # is a scalar, so [1] took the first CHARACTER. `EDITOR=micro` asked for `m`,
    # missed, and fell through to nano — which on macOS is a symlink to pico, no
    # colours, no mouse. `${e%% *}` keeps the point of it ("code -w" -> code).
    [[ -n $e ]] && command -v ${e%% *} >/dev/null && { print -r -- "$e"; return }
  done
  print -r -- vi
}

# fuzzy-pick a file and open it. Files you have changed come first: it is nearly
# always one of them. Returns non-zero when you cancel, which is what lets the
# editor pane loop until you actually want out.

# Where the shell pane is standing right now, or this shell's own directory when
# there is no office and no shell pane.
_office_shell_dir() {
  local s d
  s=$(_office_here)
  d=$(tmux list-panes -t "=$s" -F '#{@office_kind}|#{pane_current_path}' 2>/dev/null \
      | awk -F'|' '$1=="SHELL" {print $2; exit}')
  [[ -n $d && -d $d ]] && print -r -- "$d" || print -r -- "$PWD"
}

# When the shell pane moves, tell the editor. zsh fires chpwd on every `cd`, and
# office.zsh is already sourced in that pane, so the shell can announce it
# instead of the editor polling for it. The nudge is Ctrl-R, which is the
# editor's own reload key, and it is only sent when fzf is actually in the
# foreground there: pressing it into an open file would type into your file.
_office_editor_sync() {
  local s p
  [[ -n $TMUX ]] || return 0
  # Decided here, not at load: a pane sources this file before office has
  # finished labelling it, so asking at startup always said "not the shell".
  # And it has to be -t $TMUX_PANE: a bare `display -p` reports the ACTIVE pane,
  # which is whichever one you are looking at, never the one asking.
  [[ $(tmux display -p -t "$TMUX_PANE" '#{@office_kind}' 2>/dev/null) == SHELL ]] || return 0
  s=$(_office_here)
  local tty
  # NB: #{pane_current_command} says "zsh" here, because fzf is a child of the
  # loop rather than the pane's own process. Ask the pane's terminal instead.
  read -r p tty <<< "$(tmux list-panes -t "=$s" -F '#{pane_id} #{pane_tty} #{@office_kind}' 2>/dev/null \
      | awk '$3=="EDITOR" {print $1, $2; exit}')"
  [[ -n $p && -n $tty ]] || return 0
  # `-o comm=` is a bare name on macOS and a full path on some Linuxes, so match
  # the tail: an exact 'fzf' silently killed the nudge wherever it printed a path.
  ps -t "${tty#/dev/}" -o comm= 2>/dev/null | grep -qE '(^|/)fzf$' || return 0
  tmux send-keys -t "$p" C-r 2>/dev/null
  return 0
}

# Every interactive zsh inside tmux gets the hook; the function itself decides
# whether this pane is the office's shell. It costs one tmux query per `cd`.
if [[ -n $TMUX && -o interactive ]]; then
  autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _office_editor_sync
fi

# What the FILE EDITOR pane runs. ONE definition: it is spawned from
# _office_open and from `office edit`, and it grew a way back.
#
# Leaving the list (Esc, or quitting the editor twice) used to `exec zsh` and
# leave a bare prompt behind a border still labelled FILE EDITOR, which no key
# could revive: `office edit` saw a pane of that kind, hid it, and gave it back
# just as empty. The pane now says so on its way out, and marks itself dead so
# its own key rebuilds it.
_office_editor_loop() {
  while _office_pick_file; do :; done
  # -t $TMUX_PANE, never a bare `set -p`: that writes to whichever pane you are
  # LOOKING at, which is how a CLAUDE pane got marked dead instead of this one.
  tmux set -p -t "$TMUX_PANE" @office_live 0 2>/dev/null
  print -P "\n  %F{yellow}the file list is closed.%f  Ctrl-Space e brings it back."
  exec zsh
}
_OFFICE_EDITOR_CMD='zsh -ic _office_editor_loop'

_office_pick_file() {                  # [dir]
  local target=${1:-} where
  if [[ -z $target || -d $target ]]; then
    # Follow the SHELL pane. tmux tracks a pane's working directory live, so
    # `cd` over there and the next time this list opens you are browsing that
    # directory. The list reopens every time you close a file, which is the
    # natural moment to resync and costs nothing.
    where=${target:-$(_office_shell_dir)}
    [[ -d $where ]] || where=$PWD
    # Plain, sorted, relative: a file list you can read like a tree, where
    # typing a folder name narrows to it. Paths are relative to the directory in
    # the prompt, so the list stays readable no matter how deep you are.
    # height 100 so a zoomed pane is actually full of files.
    #
    # It follows the shell LIVE. `focus` fires whenever the highlighted line
    # changes, so moving the cursor is enough to notice a `cd` next door, and
    # `transform` only emits a reload when the directory actually differs.
    # $seen holds the last directory it drew, because fzf bindings are separate
    # processes with nowhere else to keep it.
    local cwd=$_OFFICE_HOME/bin/office-cwd sess seen
    sess=$(_office_here)
    seen=$(mktemp) && print -rn -- "$where" > $seen
    local list='fd --type f --hidden --follow --exclude .git --exclude node_modules --strip-cwd-prefix 2>/dev/null || find . -type f -not -path "*/.git/*" | sed "s|^\./||"'
    # NB: {} stands alone in the preview. fzf single-quotes the substitution, so
    # "$dir/{}" becomes "$dir/'file'" and the quote splits it into two arguments.
    target=$( cd "$where" && eval "$list" | sort \
      | fzf --prompt="${where:t}/ > " --height=100% --reverse \
            --header="$where" \
            --preview "d=\$($cwd $sess); cd \"\${d:-$where}\" 2>/dev/null; bat --style=numbers --color=always --line-range :300 {} 2>/dev/null || cat {}" \
            --preview-window=right:55%:wrap \
            --bind "focus:transform:d=\$($cwd $sess); [ -z \"\$d\" ] || [ \"\$d\" = \"\$(cat $seen)\" ] || { printf %s \"\$d\" > $seen; printf 'reload(cd %s && $list | sort)+change-prompt(%s/ > )+change-header(%s)' \"\$d\" \"\${d##*/}\" \"\$d\"; }" \
            --bind "ctrl-r:transform:d=\$($cwd $sess); [ -n \"\$d\" ] && { printf %s \"\$d\" > $seen; printf 'reload(cd %s && $list | sort)+change-prompt(%s/ > )+change-header(%s)' \"\$d\" \"\${d##*/}\" \"\$d\"; }" ) || { rm -f $seen; return 1 }
    where=$(<$seen); rm -f $seen
    [[ -n $target ]] || return 1
    target="$where/$target"
  fi
  [[ -n $target ]] || return 1
  local -a ed; ed=(${(z)$(_office_editor)})
  # Put the keys where you need them: in the editor, while the file is open.
  # Nobody remembers how to get back out of an editor they use twice a week.
  if [[ ${ed[1]:t} == micro ]]; then
    # softwrap, because a pane is narrower than a file: prose and long lines
    # would otherwise run off the right edge and be read by scrolling sideways.
    # scrollbar, so a long file shows how long it is. Both are micro defaults-off.
    $ed -statusline true -softwrap true -scrollbar true \
        -statusformatr "^S save   ^Q back to the file list   ^Z undo   ^F find" \
        "$target"
  else
    $ed "$target"
  fi
}


# --- the right strip: chat, shell, file editor, top to bottom ----------------
# The order is data, so a pane that is toggled off and back on lands where it
# belongs instead of at the bottom.
#
# The agent you built is at the TOP: it is the pane you actually talk to, so it
# gets the corner your eye goes to. Then the shell, then the file list, which is
# the pane you reach for least. With no chat wired up the strip is the shell and
# the editor, which is the same order with the top row missing.
typeset -gA _OFFICE_STRIP_ORDER=(CHAT 1 SHELL 2 EDITOR 3)
_office_rank() { print -r -- ${_OFFICE_STRIP_ORDER[$1]:-9} }

# where a <kind> pane belongs in the strip: "<pane-id> <split-flag>", where the
# flag is -b when it has to go ABOVE that pane (nothing ranks below it yet).
_office_strip_slot() {                 # <session> <kind>
  local line col id kind below last first want
  want=$(_office_rank "$2")
  for line in ${(f)"$(tmux list-panes -t "=$1" -F '#{pane_left}|#{pane_top}|#{pane_id}|#{@office_kind}' 2>/dev/null | sort -t'|' -k1,1nr -k2,2n)"}; do
    col=${col:-${line%%|*}}
    [[ ${line%%|*} == $col ]] || break          # left column starts, strip ends
    id=${${(s:|:)line}[3]}; kind=${${(s:|:)line}[4]}
    first=${first:-$id}
    (( $(_office_rank "$kind") <= want )) && last=$id
  done
  [[ -n $last ]] && { print -r -- "$last "; return }
  print -r -- "${first} -b"
}

# give every pane in a column the same height. tmux has no column-scoped layout,
# so the arithmetic is ours. `left` is the desks, `right` is the glance strip;
# a three-row shell is as useless as a three-row agent.
# Where a pane of <kind> belongs: a target pane plus split-window/join-pane flags.
#
# Both columns can vanish. Park every session and the left column is
# gone; park the shell, editor and chat and the strip is. tmux collapses a
# two-column layout the moment one side empties, and from then on "leftmost
# pane" and "rightmost pane" are the same pane, so everything coming back lands
# in one tall stack. This is what stops that: when a column is missing, the
# first pane that needs it rebuilds it.
# Put the two columns back, from any mess at all.
#
# tmux layouts are trees, and only a window with ONE pane can be split into two
# root-level columns. Splitting a pane that already sits inside a stack nests
# instead, which is how a rebuilt column ends up half height. So the honest
# repair is to break every pane out, keep one, and re-join them in the order the
# office wants: sessions down the left, glance panes down the right.
#
# Only runs when a column has actually gone missing, because it makes every pane
# redraw. `office layout` is the same thing on demand.
# Is the window actually shaped like an office? Every session sharing one left
# edge, every glance pane sharing another, and the sessions on the left. Counting
# distinct columns is not enough: a nested split also produces two of them, and
# that is exactly the broken state this has to catch.
_office_layout_ok() {                  # <session>
  local line kind left
  local -a dl sl
  # again here, and not only in office(): this is the ONE geometry read whose
  # wrong answer is destructive. It hands the room to _office_relayout, which
  # breaks every pane out to the stash. A zoomed pane reports left 0, so a strip
  # pane under zoom looks like it is sitting in the desk column and the office
  # is declared broken while nothing is wrong with it. Nothing calls this from
  # outside office() today; the guard is here so nothing has to remember.
  _office_unzoom "$1"
  for line in ${(f)"$(tmux list-panes -t "=$1" -F '#{pane_left}|#{@office_kind}' 2>/dev/null)"}; do
    left=${${(s:|:)line}[1]}; kind=${${(s:|:)line}[2]}
    if [[ $(_office_rank "$kind") == 9 ]]; then dl+=($left); else sl+=($left); fi
  done
  (( $#dl && $#sl )) || return 0       # one-sided is a legitimate shape
  dl=(${(u)dl}); sl=(${(u)sl})
  (( $#dl == 1 && $#sl == 1 )) && (( dl[1] < sl[1] ))
}

_office_relayout() {                   # <session>
  local s=$1 line kind id keep w prev
  local -a desks strip all
  for line in ${(f)"$(tmux list-panes -t "=$s" -F '#{pane_top}|#{pane_id}|#{@office_kind}' 2>/dev/null | sort -t'|' -k1,1n)"}; do
    id=${${(s:|:)line}[2]}; kind=${${(s:|:)line}[3]}
    if [[ $(_office_rank "$kind") == 9 ]]; then desks+=($id); else strip+=("$(_office_rank "$kind")|$id"); fi
  done
  strip=(${(f)"$(printf '%s\n' $strip | sort -t'|' -k1,1n | cut -d'|' -f2)"})
  (( $#desks && $#strip )) || return 0          # one-sided is not a two-column layout
  _office_stash_ensure
  keep=${desks[1]}
  all=(${desks[2,-1]} $strip)
  for id in $all; do tmux break-pane -d -s "$id" -t "=$_OFFICE_STASH:" -n "relayout-${id#\%}" 2>/dev/null; done
  # one pane left, so this split is the ROOT one: it is what makes two columns
  w=$(tmux list-windows -t "=$s" -F '#{window_width}' 2>/dev/null | head -1)
  tmux join-pane -h -l $(( w * OFFICE_STRIP_WIDTH / 100 )) -s "${strip[1]}" -t "$keep" 2>/dev/null
  prev=$keep
  for id in ${desks[2,-1]}; do tmux join-pane -v -s "$id" -t "$prev" 2>/dev/null && prev=$id; done
  prev=${strip[1]}
  for id in ${strip[2,-1]}; do tmux join-pane -v -s "$id" -t "$prev" 2>/dev/null && prev=$id; done
  _office_even_column "$s" left; _office_even_column "$s" right; _office_number "$s"
}

_office_place() {                      # <session> <kind> -> "<pane> <flags...>"
  local s=$1 kind=$2 cols l has_strip=0
  local -a sl
  cols=$(tmux list-panes -t "=$s" -F '#{pane_left}' 2>/dev/null | sort -un | wc -l | tr -d ' ')
  if (( cols >= 2 )); then                        # both columns exist: place normally
    if [[ $(_office_rank "$kind") == 9 ]]; then
      print -r -- "$(_office_desk_pane "$s") -v"
    else
      sl=($(_office_strip_slot "$s" "$kind")); print -r -- "${sl[1]} -v ${sl[2]}"
    fi
    return
  fi
  for l in ${(f)"$(tmux list-panes -t "=$s" -F '#{@office_kind}' 2>/dev/null)"}; do
    [[ $(_office_rank "$l") == 9 ]] || has_strip=1
  done
  if (( has_strip )) && [[ $(_office_rank "$kind") != 9 ]]; then
    sl=($(_office_strip_slot "$s" "$kind")); print -r -- "${sl[1]} -v ${sl[2]}"
  elif (( has_strip )) || [[ $(_office_rank "$kind") == 9 ]]; then
    # the column this pane belongs in does not exist. Land it anywhere: the
    # caller checks the shape afterwards and rebuilds, which is the only way to
    # get a root-level split back.
    print -r -- "$(_office_desk_pane "$s") -v"
  else
    print -r -- "$(_office_desk_pane "$s") -h -l ${OFFICE_STRIP_WIDTH}%"
  fi
}

_office_even_column() {                # <session> [left|right]
  local s=$1 side=${2:-left} h n target p sortflag
  local -a panes
  [[ $side == right ]] && sortflag=-k1,1nr || sortflag=-k1,1n
  panes=(${(f)"$(tmux list-panes -t "=$s" -F '#{pane_left} #{pane_top} #{pane_id}' 2>/dev/null \
        | sort $sortflag -k2,2n | awk 'NR==1 {l=$1} $1==l {print $3}')"})
  n=$#panes
  (( n > 1 )) || return 0
  # NB: display-message -t "=session" returns EMPTY for window_height; ask the
  # window list instead, or the target becomes 0 and every pane collapses to 1.
  h=$(tmux list-windows -t "=$s" -F '#{window_height}' 2>/dev/null | head -1)
  [[ $h == <-> ]] || return 0
  target=$(( (h - (n - 1)) / n ))
  (( target >= 6 )) || return 0        # below this it is a sliver, not a pane
  for p in ${panes[1,-2]}; do tmux resize-pane -t "$p" -y $target 2>/dev/null; done
}
_office_even_desks() { _office_even_column "$1" left }

# tmux numbers panes by their position in the LAYOUT TREE, and join-pane leaves
# that tree in an order the eye does not agree with: you get 4=EDITOR, 6=SHELL.
# Swapping cannot fix it (a swap moves the geometry too), and rebuilding the tree
# means breaking every pane out and back. So the border shows OUR number, taken
# straight from the geometry: down the left column, then down the right strip.
# The key strip, written into a tmux option rather than polled by the status bar
# with #(). A polled job is always one interval behind the thing it describes:
# you close a pane and the bar keeps saying it is open until the next tick. This
# is pushed, from the one function that already runs after every change.
#
# Three tones, and the ladder is one question: what is the key FOR right now?
#
#   white  the way BACK out of a state you are stuck in. Nothing else is white,
#          so white always means "press this to undo what you are looking at".
#          Only zoom has such a state: while a window is zoomed, every other
#          pane is invisible while still being open, so the open/closed reading
#          below cannot help you and the exit key has to say so itself.
#   lit    a pane that is CLOSED - the key brings it back. Worth your eye.
#   dim    a pane that is already open, and the actions, which have no
#          open-or-closed state to report at all.
#
# The prefix is lit, not dim: it is the key every other key on this bar needs
# first, so it is never "nothing to do here".
_OFFICE_BAR_OPEN='#[fg=#4e505a]'
_OFFICE_BAR_SHUT='#[fg=#9a9ca6]'
_OFFICE_BAR_BACK='#[fg=#f6f5f1]'
_OFFICE_BAR_SEP='#[fg=#3a3c44]'
_office_bar() {                        # <session>
  local open out sep="" pair kind name key tone
  open=" $(tmux list-panes -t "=$1" -F '#{@office_kind}' 2>/dev/null | tr '\n' ' ')"
  out="${_OFFICE_BAR_SHUT}^Space#[default] ${_OFFICE_BAR_SEP}│#[default] ${_OFFICE_BAR_OPEN}n new${_OFFICE_BAR_SEP} · #[default]"
  for pair in "CLAUDE:sessions:a" "CHAT:chat:c" "SHELL:shell:s" "EDITOR:editor:e"; do
    kind=${pair%%:*}; name=${${pair#*:}%%:*}; key=${pair##*:}
    [[ $open == *" $kind "* ]] && tone=$_OFFICE_BAR_OPEN || tone=$_OFFICE_BAR_SHUT
    out+="${sep}${tone}${name} ${key}#[default]"
    sep="${_OFFICE_BAR_SEP} · #[default]"
  done
  # One list, one separator. There used to be a second divider here marking
  # "toggles" from "actions", which is a distinction nothing else on the bar
  # shows: brightness means closed, and that is all it means.
  # Zoom is the one segment this function cannot answer, and the only one that
  # is a FORMAT rather than a tone: ^Space z is plain tmux, so it fires without
  # office running at all and a pushed tone would sit there stale, calling a
  # zoomed window flat until the next thing you happen to open. tmux resolves
  # this conditional itself, every redraw. It needs the theme's `#{E:` to be
  # expanded - a `#{...}` reached through `#{@office_bar}` comes out LITERAL
  # (checked on tmux 3.7b), which is why the E is not decoration.
  out+="${_OFFICE_BAR_SEP} · #[default]${_OFFICE_BAR_OPEN}q close${_OFFICE_BAR_SEP} · #[default]${_OFFICE_BAR_OPEN}x park${_OFFICE_BAR_SEP} · #[default]#{?window_zoomed_flag,${_OFFICE_BAR_BACK}z unzoom,${_OFFICE_BAR_OPEN}z zoom}#[default]"
  # Moving between panes, behind its own divider because it is the one chord on
  # this bar that does NOT want the prefix - the divider is the chord changing,
  # which is the same job the first one does after ^Space. It is the first thing
  # a new pair of eyes needs and the only key here nothing on screen hints at:
  # a pane border shows which pane you are in, never how to reach the next one.
  # Dim, like the other actions, because moving has no open-or-closed state.
  out+="${_OFFICE_BAR_SEP} │ #[default]${_OFFICE_BAR_OPEN}⇧←↑↓→ move#[default]"
  # NB: no "=" prefix here. set-option takes a plain session name and rejects
  # the exact-match form that every other tmux command accepts.
  tmux set -t "$1" @office_bar "$out" 2>/dev/null
}

_office_number() {                     # <session>
  local r n=0
  for r in ${(f)"$(tmux list-panes -t "=$1" -F '#{pane_left}|#{pane_top}|#{pane_id}' 2>/dev/null \
        | sort -t'|' -k1,1n -k2,2n)"}; do
    tmux set -p -t "${${(s:|:)r}[3]}" @office_num $(( ++n )) 2>/dev/null
  done
  _office_bar "$1"                     # the strip is only ever as fresh as this
}

# --- staying current, without surprising you ---------------------------------
# `office on` fetches in the BACKGROUND and says nothing except when you are
# behind. It never pulls on its own: this package is the thing drawing your
# window, and changing it under you mid-session is how a morning gets ruined.
# `office update` is the deliberate act, and it refuses on a dirty tree rather
# than merging over your edits.
_office_update_check() {
  [[ -d $_OFFICE_HOME/.git ]] || return 0
  ( git -C "$_OFFICE_HOME" fetch --quiet origin 2>/dev/null & ) >/dev/null 2>&1
  local behind
  behind=$(git -C "$_OFFICE_HOME" rev-list --count HEAD..@{upstream} 2>/dev/null)
  (( behind > 0 )) && print -P "%F{240}  agent-office is $behind commit(s) behind — 'office update'%f"
  return 0
}

# --- taking out the bins, so nobody has to remember to ---------------------
# A parked pane is the only kind you can forget: it is invisible, and a parked
# session still holds half a gigabyte. Anything parked and untouched this
# long is reaped when you next walk in.
#
# Panes you can SEE are never touched automatically. Those are a decision, and a
# script that closes an agent you were coming back to is worse than a full disk.
: ${OFFICE_REAP_HOURS:=12}
_office_reap() {
  tmux has-session -t "=$_OFFICE_STASH" 2>/dev/null || return 0
  local now=$(date +%s) line w act pid n=0 mb=0
  for line in ${(f)"$(tmux list-windows -t "=$_OFFICE_STASH" -F '#{window_id}|#{window_activity}' 2>/dev/null)"}; do
    w=${${(s:|:)line}[1]}; act=${${(s:|:)line}[2]}
    [[ $act == <-> ]] || continue
    (( (now - act) / 3600 >= OFFICE_REAP_HOURS )) || continue
    pid=$(tmux list-panes -t "$w" -F '#{pane_pid}' 2>/dev/null | head -1)
    [[ -n $pid ]] && mb=$(( mb + $(_office_pane_mb "$pid") ))
    tmux kill-window -t "$w" 2>/dev/null && (( n++ ))
  done
  (( $(tmux list-windows -t "=$_OFFICE_STASH" 2>/dev/null | wc -l) )) \
    || tmux kill-session -t "=$_OFFICE_STASH" 2>/dev/null
  (( n )) && print -P "%F{240}  tidied up: $n pane(s) parked over ${OFFICE_REAP_HOURS}h closed, ~${mb}MB back%f"
  # Offices left running from another day are only reported, never closed for
  # you: one of them might be four agents mid-task. `office sweep` is one word.
  local -a stale; stale=(${(f)"$(_office_stale ${OFFICE_REAP_HOURS})"})
  if (( $#stale )); then
    local smb=0 l; for l in $stale; do smb=$(( smb + ${${(z)l}[3]} )); done
    print -P "%F{yellow}  ${#stale} office(s) left open from earlier, holding ~${smb}MB%f — close them with '''office sweep'''"
  fi
  return 0
}

# --- making sure nothing outlives the office ---------------------------------
# tmux kill-server sends SIGHUP to each pane's children, which is enough for
# anything still attached to a terminal and not enough for anything that
# detached itself. Agent CLIs in particular leave host and daemon processes
# behind that no pane is the parent of, and they hold hundreds of megabytes.
#
# So: take the process GROUP of every pane before killing the server, then make
# sure those groups are gone afterwards. Our own group is excluded, because
# `office off` is nearly always run from inside the office it is closing.
_office_pane_groups() {                # [session]  (all offices when omitted)
  local p g
  local -a t; [[ -n $1 ]] && t=(-t "=$1") || t=(-a)
  for p in ${(f)"$(tmux list-panes $t -F '#{pane_pid}' 2>/dev/null)"}; do
    g=$(ps -o pgid= -p "$p" 2>/dev/null | tr -d ' ')
    [[ -n $g && $g != $_OFFICE_OWN_PGID && $g -gt 1 ]] && print -r -- "$g"
  done | sort -u
}

_office_kill_groups() {                # <pgid>...
  local g
  for g in "$@"; do kill -TERM -$g 2>/dev/null; done
  sleep 0.4
  for g in "$@"; do kill -KILL -$g 2>/dev/null; done
}

# Offices you walked away from. An office survives a closed terminal on purpose,
# which is the whole point of `office break`, and the cost is that one left over
# from days ago is still holding four agents and their memory with no window
# anywhere.
#
# Scoped to tmux sessions this tool created, and nothing else. An earlier
# version matched process NAMES, which swept in the desktop app, the tmux server
# and every unrelated shell: a broom that wide is a footgun, not a feature.
_office_stale() {                      # [hours] -> "<session> <idle-min> <MB>"
  local hours=${1:-12} now=$(date +%s) line name attached act mb pid
  for line in ${(f)"$(tmux list-sessions -F '#{session_name}|#{session_attached}|#{session_activity}' 2>/dev/null)"}; do
    name=${${(s:|:)line}[1]}; attached=${${(s:|:)line}[2]}; act=${${(s:|:)line}[3]}
    [[ $name == _* ]] && continue                  # the pane stash is not an office
    (( attached )) && continue                     # you are looking at this one
    [[ $act == <-> ]] || continue
    (( (now - act) / 3600 >= hours )) || continue
    mb=0
    for pid in ${(f)"$(tmux list-panes -t "=$name" -F '#{pane_pid}' 2>/dev/null)"}; do
      mb=$(( mb + $(_office_pane_mb "$pid") ))
    done
    print -r -- "$name $(( (now - act) / 60 )) $mb"
  done
}

# --- going home is a reset -----------------------------------------------------
# `office off` deliberately keeps NOTHING: not the pane sizes, not what you
# parked, not the shape you dragged things into. It is the fix-it-all, so
# whatever you broke fiddling with the layout, off and on gives you the default
# office back every time, with no saved state anywhere to explain it.
#
# `office break` is the other half: it detaches without stopping anything, and
# because the tmux server stays alive your layout survives exactly as it was.
# Two verbs, two behaviours, no configuration.

# label a pane. Borders carry IDENTITY only: which pane this is, what it is, and
# what it is doing. The keys all live on the status strip, in one place, because
# printing "^Space w" on a session was advertising a global action as if it
# belonged to that pane, and printing every key on every border is clutter.
#
# label a pane. An agent overwrites #{pane_title} with whatever it is doing,
# so the ROLE lives in a user option the app cannot touch, and the border shows
# both: "CLAUDE . rename the auth module".
#
# @office_kind is the STABLE identity (CHAT, SHELL, EDITOR, CLAUDE) that
# the toggles match on — the visible label carries a repo and a branch and moves.
_office_label() {                      # <pane> <label> [kind]
  # '#' is stripped: the label is rendered through tmux's format engine, where
  # #(...) runs a shell command. A branch name or an `office task` description
  # containing one would otherwise be executed every time the border redraws.
  tmux set -p -t "$1" @office_label "${2//\#/}" 2>/dev/null
  tmux set -p -t "$1" @office_kind "${3:-$2}" 2>/dev/null
}

# say something to the operator. A keybinding runs with no terminal attached, so
# a bare `print` becomes stray run-shell output — and tmux shows THAT by forcing
# the active pane into view-mode, where every office key stops working.
# The status line is the only safe place to talk from.
_office_say() {
  tmux display-message " office: $1" 2>/dev/null || print -u2 "office: $1"
}

# Is a session ALREADY running in this checkout? Two agents in one is the single
# way this layout bites: same branch, same files, each committing over the other,
# and nothing on screen says so — both borders read CLAUDE and both are right.
# It is a legitimate thing to want (one reading while one writes), so the callers
# say it and none of them block.
#
# :A on both sides, because tmux answers with the path symlinks resolve to while
# the caller's is whatever git printed. /tmp alone is enough to make two names
# for one directory look like two, and then this never fires in the exact case
# it exists for.
_office_desk_in() {                    # <session> <dir>
  local p want=${2:A}
  for p in ${(f)"$(tmux list-panes -t "=$1" -F "#{@office_kind}|#{pane_current_path}" 2>/dev/null)"}; do
    [[ $p == CLAUDE\|* && ${${p#CLAUDE|}:A} == $want ]] && return 0
  done
  return 1
}
_OFFICE_SHARED_MSG="2nd session in the same checkout — 'office new <name>' gives one its own worktree"

# the visible pane of a given kind, if it is on screen at all
_office_pane_of_kind() {               # <session> <kind>
  tmux list-panes -t "=$1" -F '#{pane_id}|#{@office_kind}' 2>/dev/null \
    | awk -F'|' -v k="$2" '$2==k {print $1; exit}'
}

# --- hiding a pane without killing it ----------------------------------------
# tmux cannot hide a pane, but it can move one to a window nobody is looking at.
# The stash is its own SESSION so no extra window ever shows up in the status
# bar, and the process inside keeps running the whole time.
_OFFICE_STASH=_stash
_office_stash_ensure() {
  tmux has-session -t "=$_OFFICE_STASH" 2>/dev/null \
    || tmux new-session -d -s "$_OFFICE_STASH" -n idle 'exec sleep 2147483647'
}

_office_hide() {                       # <pane-id>
  local kind sess
  kind=$(tmux display -p -t "$1" '#{@office_kind}' 2>/dev/null)
  sess=$(tmux display -p -t "$1" '#{session_name}' 2>/dev/null)
  [[ -n $kind ]] || kind=pane
  # again here, and not only in office(): the Ctrl-Space x binding is the one
  # that does NOT cd to the pane's path first, so _office_here up there can name
  # a different office (or none). The pane knows its own session; use that.
  _office_unzoom "$sess"
  _office_stash_ensure
  # two parked CLAUDE desks would otherwise both be a window called "claude", and
  # only ever one of them could be found again. The pane id makes it unique, and
  # _office_unhide matches on the "<kind>-<office>-" prefix.
  #
  # The office is in the name because the stash is ONE session for the whole
  # server: keyed by kind alone, parking the file editor in one office and
  # pressing Ctrl-Space e in another handed you the first office's pane, panel
  # and all.
  local name="${(L)kind}-${(L)sess}-${1#\%}"
  tmux break-pane -d -s "$1" -t "=$_OFFICE_STASH:" -n "$name" 2>/dev/null || return 1
  # the placeholder only exists because a session needs one window; once a real
  # pane is parked it is just noise in `office doctor`.
  (( $(tmux list-windows -t "=$_OFFICE_STASH" 2>/dev/null | wc -l) > 1 )) \
    && tmux kill-window -t "=$_OFFICE_STASH:idle" 2>/dev/null
  _office_number "${${(s.:.)$(tmux display -p '#{session_name}')}[1]}" 2>/dev/null
  return 0
}

# bring a stashed pane back to where its kind belongs. Fails (1) if none is stashed.
_office_unhide() {                     # <session> <kind>
  local w p
  local -a slot
  # THIS office's stash entry for that kind, or the exact window name when
  # `office show` passed one through.
  w=$(tmux list-windows -t "=$_OFFICE_STASH" -F '#{window_id} #{window_name}' 2>/dev/null \
      | awk -v n="${(L)2}" -v pfx="${(L)2}-${(L)1}-" '$2==n || index($2, pfx)==1 {print $1; exit}')
  [[ -n $w ]] || return 1
  p=$(tmux list-panes -t "$w" -F '#{pane_id}' 2>/dev/null | head -1)
  slot=($(_office_place "$1" "$2"))
  tmux join-pane ${slot[2,-1]} -s "$p" -t "${slot[1]}" || return 1
  # a column that was just rebuilt holds one pane; evening both is cheap and
  # always right, and the numbers follow the geometry afterwards.
  _office_layout_ok "$1" || _office_relayout "$1"
  _office_even_column "$1" left; _office_even_column "$1" right
  _office_number "$1"
}

# a short label for the bottom strip: repo name + current branch
_office_strip_title() {
  local b; b=$(git -C "$1" branch --show-current 2>/dev/null)
  print -r -- "SHELL · $(basename "$1")${b:+ · $b}"
}

# The cockpit. ONE window. LEFT: the agents that write code (claude, codex,
# whatever OFFICE_SESSION_CMD points at) —
# three of them, open and ready. The RIGHT strip holds everything you glance at,
# and every one of those four is a toggle:
#
#   +-------------------------------+-----------+
#   |  CLAUDE                       | CHAT      |  ^Sc  (opens on demand)
#   +-------------------------------+-----------+
#   |  CLAUDE 2                     | SHELL     |  ^Ss
#   |                               +-----------+
#   |                               | FILE ED.  |  ^Se
#   +-------------------------------+-----------+
#
# CHAT (^Sc) is the one pane that starts closed: point OFFICE_CHAT_CMD at your
# own agent's chat command first, or it is just another shell.
#
# ^Sn adds a session to the left column, ^Sq closes whatever pane you are on.
_OFFICE_DEFAULT_DESKS=${OFFICE_DEFAULT_DESKS:-1}
_office_open() {                       # <repo-path>
  local dir=$1 s
  s=$(_office_sessname "$dir")
  if ! tmux has-session -t "=$s" 2>/dev/null; then
    local main editor strip n prev chat
    main=$(tmux new-session -d -s "$s" -c "$dir" -n office -P -F '#{pane_id}' "$OFFICE_SESSION_CMD$_OFFICE_DESK_END")
    _office_label "$main" "$OFFICE_SESSION_LABEL" CLAUDE
    # the right strip first, at OFFICE_STRIP_WIDTH: these are glance surfaces, and
    # width once here is what leaves the sessions a full-width column.
    strip=$(tmux split-window -h -l ${OFFICE_STRIP_WIDTH}% -t "$main" -c "$dir" -P -F '#{pane_id}')
    _office_label "$strip" "$(_office_strip_title "$dir")" SHELL
    # then the chat, once you have given it something to run. -b: ABOVE the
    # shell, at the top of the strip, because it is the pane you talk to.
    if (( OFFICE_CHAT_OPEN )); then
      chat=$(tmux split-window -v -b -t "$strip" -c "$dir" -P -F '#{pane_id}' "$OFFICE_CHAT_CMD")
      _office_label "$chat" "$OFFICE_CHAT_LABEL" CHAT
    fi
    # the file editor comes up too, at the bottom: everyone needs a file open
    # sooner or later, and it is the pane you reach for least.
    editor=$(tmux split-window -v -t "$strip" -c "$dir" -P -F '#{pane_id}' "$_OFFICE_EDITOR_CMD")
    _office_label "$editor" "FILE EDITOR" EDITOR
    # three panes from three splits are 50/25/25. Even them, the same way every
    # toggle does, so the default office looks deliberate.
    _office_even_column "$s" right
    # the rest of the sessions, stacked down the left. Split the one just made,
    # not the tallest — otherwise desk 3 lands between 1 and 2 and the labels lie.
    local prev=$main
    # C-style, not {2..$N}: zsh counts a brace range DOWNWARDS when the start
    # is past the end, so a single-desk default would silently open three.
    for (( n = 2; n <= _OFFICE_DEFAULT_DESKS; n++ )); do
      prev=$(tmux split-window -v -t "$prev" -c "$dir" -P -F '#{pane_id}' "$OFFICE_SESSION_CMD$_OFFICE_DESK_END")
      _office_label "$prev" "$OFFICE_SESSION_LABEL $n" CLAUDE
    done
    _office_even_desks "$s"
    _office_number "$s"
    tmux select-pane -t "$main"
  fi
  cd "$dir"
  _office_number "$s"                  # also writes the key strip
  _office_reap                         # walking in takes the bins out
  _office_update_check
  _office_always_on_up                 # restore whatever `office off` stopped
  _office_reload_conf                  # the server may be older than the config
  _office_attach "$s"
}

# Has this worktree's branch LANDED — is every change on it already in the branch
# the repo merges into?
#
# The obvious test is whether its commits are ancestors of the default branch,
# and that test is wrong for any repo that squash-merges: a squash rewrites the
# branch's commits into one new commit, so the originals stay un-ancestored
# forever and every branch that ever landed still reads as unfinished. Merging
# the branch in memory and asking whether the RESULT differs from the default
# branch's tree answers the content question instead, which is what "finished"
# actually means.
#
# Fail-safe in the do-not-reuse direction: an unreadable ref, a conflict, or a
# git older than 2.38 (no `merge-tree --write-tree`) all say no, and the caller
# makes a new worktree instead of walking an agent into someone else's branch.
_office_wt_landed() {                  # <root> <worktree>
  local root=$1 d=$2 base branch merged tree
  branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  [[ -n $branch && $branch != HEAD ]] || return 1          # detached: not ours to judge
  base=$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  base=${base#*/}
  [[ -n $base ]] || base=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ -n $base && $base != $branch ]] || return 1
  [[ $(git -C "$root" rev-list --count "$base..$branch" 2>/dev/null) == 0 ]] && return 0
  merged=$(git -C "$root" merge-tree --write-tree "$base" "$branch" 2>/dev/null | head -1) || return 1
  tree=$(git -C "$root" rev-parse "$base^{tree}" 2>/dev/null)
  [[ -n $merged && $merged == $tree ]]
}

# Which worktree an unnamed extra desk gets. The first one nobody is sitting in
# and nobody left anything in, else a fresh desk-N. Reuse first, because a key
# you press several times a day that creates a directory every time is a key
# that fills your repo with them.
#
# "Left anything in" is the same two questions a session-worktree sweep asks
# before deleting one — uncommitted files, then unlanded commits — so a worktree
# this reuses is exactly a worktree such a sweep would consider finished. Same
# predicate, opposite verb.
_office_free_wt() {                    # <root> <session> -> a directory, or nothing
  local root=$1 s=$2 wt="$1/$OFFICE_WORKTREE_DIR" d n=2
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 1
  for d in $wt/*(N/); do
    _office_desk_in "$s" "$d" && continue
    [[ -n $(git -C "$d" status --porcelain 2>/dev/null) ]] && continue
    _office_wt_landed "$root" "$d" || continue
    print -r -- "$d"; return 0
  done
  # A free NUMBER is a free directory and a free branch. Removing a worktree
  # leaves its branch behind — `git worktree remove` does, and so does anything
  # else that cleans checkouts up — so desk-2's directory can be gone while the
  # branch is not. Then `worktree add -b desk-2` fails on the branch, this
  # returns nothing, and the caller falls back to the shared checkout: the exact
  # collision the whole command exists to prevent, arriving quietly.
  while [[ -e $wt/desk-$n ]] || git -C "$root" show-ref --quiet --verify "refs/heads/desk-$n"; do
    (( n++ ))
  done
  git -C "$root" worktree add -b "desk-$n" "$wt/desk-$n" >/dev/null 2>&1 || return 1
  print -r -- "$wt/desk-$n"
}

_office_new() {                        # [worktree-name] -> extra session
  local root wt dir label s
  root=$(_office_root "$PWD"); wt="$root/$OFFICE_WORKTREE_DIR"

  s=$(_office_here)
  tmux has-session -t "=$s" 2>/dev/null \
    || { _office_say "no office open — run 'office on' first"; return 0 }
  # The cap belongs here too. Only _office_add_pane counted, so this command
  # walked past it and split a fifth desk into a column sized for four — and it
  # is the door Ctrl-Space n uses now. Asked before anything is created, so a
  # full column never leaves a worktree behind for a pane that never opened.
  if (( $(_office_desk_count "$s") >= _OFFICE_MAX_DESKS )); then
    _office_say "left column is full ($_OFFICE_MAX_DESKS sessions) — close one with Ctrl-Space q"
    return 0
  fi

  if [[ -z $1 ]]; then
    # Typed in a shell, the picker asks. From a keybinding there is no terminal
    # to ask on and a prompt on the status bar is the thing this project already
    # threw out, so it takes a free worktree or makes one.
    if [[ -t 1 ]]; then
      dir=$( { print -r -- "$root"; [[ -d $wt ]] && fd --type d --max-depth 1 . "$wt" 2>/dev/null; } \
             | sed 's|/$||' | fzf --prompt='session in> ' --height=40% --reverse) || return
    else
      dir=$(_office_free_wt "$root" "$s")
      # Nothing git could give: not a repo, no commit to branch from, a worktree
      # that would not add. The key still has to open a session — a key that
      # does nothing reads as broken — so it opens one here, and the line at the
      # bottom says what sharing a checkout means.
      [[ -n $dir ]] || dir=$root
    fi
  elif [[ -d $wt/$1 ]]; then dir="$wt/$1"
  elif [[ -d $1 ]];    then dir=$(cd "$1" && pwd)
  else
    # No worktree by that name yet, so make one. This used to be an error, and
    # the error was the whole problem: the one command that promises a session
    # which cannot collide with the others worked only if some OTHER tool had
    # already created the checkout. So you went back to the shell, and the
    # cheaper thing to type is another session in the repo you are already in —
    # which is exactly the collision, two agents committing over each other on
    # one branch. Creating is additive: a branch and a directory, nothing
    # touched in the checkout you are standing in.
    git -C "$root" rev-parse --git-dir >/dev/null 2>&1 \
      || { print -u2 "office: no directory '$1', and $root is not a git repo"; return 1 }
    dir="$wt/$1"
    # -b first (a new branch off HEAD, the usual case); without it when the
    # branch already exists and you are picking it up in a fresh checkout.
    git -C "$root" worktree add -b "$1" "$dir" 2>/dev/null \
      || git -C "$root" worktree add "$dir" "$1" \
      || { print -u2 "office: could not create worktree '$1'"; return 1 }
    print -r -- "office: new worktree $dir"
  fi
  label=$(basename "$dir")
  [[ $dir == "$root" ]] && label="$OFFICE_SESSION_LABEL" || label="$OFFICE_SESSION_LABEL · $label"

  # Picking the repo root out of the picker lands in the checkout a session is
  # usually already in, which is the collision this command exists to avoid.
  local shared=0
  _office_desk_in "$s" "$dir" && shared=1

  # split the tallest desk in the left column, so agents stack down the left and
  # the right strip keeps its width
  local newp
  newp=$(tmux split-window -v -t "$(_office_desk_pane "$s")" -c "$dir" -P -F '#{pane_id}' "$OFFICE_SESSION_CMD$_OFFICE_DESK_END")
  _office_label "$newp" "$label" CLAUDE
  _office_even_desks "$s"
  # `_office_add_pane` has always ended this way and this one did not, so a desk
  # opened by `office new` sat there with a blank number on its border and a key
  # bar still describing the pane set from before it existed — until some other
  # office command happened to renumber. Nothing calls renumber on a timer.
  _office_number "$s"
  (( shared )) && _office_say "$_OFFICE_SHARED_MSG"
  # not inside tmux and not on a terminal (a run-shell keybinding) — nothing to attach to
  [[ -n $TMUX || ! -t 1 ]] || _office_attach "$s"
}

# add a pane running <command>. A ranked kind (CHAT/SHELL/EDITOR) lands in the
# right strip, in its place; anything else is a desk in the left column, which
# is capped and re-evened.
_office_add_pane() {                   # <label> <command> [dir] [kind]
  local s newp dir=${3:-$PWD} kind=${4:-${1}}
  local -a slot
  s=$(_office_here)
  tmux has-session -t "=$s" 2>/dev/null \
    || { _office_say "no office open — run 'office on' first"; return 0 }
  if [[ $(_office_rank "$kind") == 9 ]] && (( $(_office_desk_count "$s") >= _OFFICE_MAX_DESKS )); then
    _office_say "left column is full ($_OFFICE_MAX_DESKS sessions) — close one with Ctrl-Space q"
    return 0
  fi
  # Asked BEFORE the split and said after, so it is the last thing on the status
  # line rather than something the relayout overwrites.
  local shared=0
  [[ $(_office_rank "$kind") == 9 ]] && _office_desk_in "$s" "$dir" && shared=1
  slot=($(_office_place "$s" "$kind"))
  newp=$(tmux split-window ${slot[2,-1]} -t "${slot[1]}" -c "$dir" -P -F '#{pane_id}' "$2") || return 1
  _office_label "$newp" "$1" "$kind"
  _office_layout_ok "$s" || _office_relayout "$s"
  _office_even_column "$s" left; _office_even_column "$s" right
  _office_number "$s"
  (( shared )) && _office_say "$_OFFICE_SHARED_MSG"
  # not inside tmux and not on a terminal (a run-shell keybinding) — nothing to attach to
  [[ -n $TMUX || ! -t 1 ]] || _office_attach "$s"
}

# ONE verb for the three panes that come and go: on screen -> stash it;
# stashed -> put it back; never existed -> make it.
_office_toggle() {                     # <kind> <label> <command>
  local s p root; root=$(_office_root "$PWD"); s=$(_office_here)
  tmux has-session -t "=$s" 2>/dev/null \
    || { _office_say "no office open — run 'office on' first"; return 0 }
  p=$(_office_pane_of_kind "$s" "$1")
  # A pane that quit its job and left a bare prompt behind is not a pane to
  # hide. Pressing its key means "give it back", so give it back.
  if [[ -n $p ]]; then
    _office_revive "$p" "$3" && return
    _office_hide "$p"; return
  fi
  if _office_unhide "$s" "$1"; then
    _office_revive "$(_office_pane_of_kind "$s" "$1")" "$3"   # parked while dead
    return
  fi
  _office_add_pane "$2" "$3" "$root" "$1"
}

# Put a pane that gave up back to work. The job marks itself dead on the way out
# (@office_live 0), so this never guesses from process names and can never kill
# a pane that is still running something.
_office_revive() {                     # <pane> <command> -> 0 if it was revived
  [[ -n $1 ]] || return 1
  [[ $(tmux display -p -t "$1" '#{@office_live}' 2>/dev/null) == 0 ]] || return 1
  tmux set -p -t "$1" @office_live '' 2>/dev/null
  tmux respawn-pane -k -t "$1" "$2" 2>/dev/null || return 1
  tmux select-pane -t "$1" 2>/dev/null
  return 0
}

# every tmux session that is an office (i.e. all of them)
# every tmux session that is an office. The pane stash (`_stash`) is not one:
# it holds panes you collapsed, and it must never show up as somewhere to go.
_office_sessions() { tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v '^_' }

# --- what is actually costing you memory -------------------------------------
# RSS of a pane, summed over its whole process group (the shell AND the agent
# / node / server running under it). ponytail: RSS double-counts shared pages,
# so treat it as a ranking signal, not an exact number.
_office_pane_mb() {
  local pgid; pgid=$(ps -o pgid= -p "$1" 2>/dev/null | tr -d ' ')
  [[ -n $pgid ]] || { print 0; return }
  ps -eo pgid=,rss= 2>/dev/null | awk -v g="$pgid" '$1==g {s+=$2} END {printf "%d", s/1024}'
}

# one line per PANE. Field 1 is the pane id (%7), so `clean` can act on a pick.
#   %4   CLAUDE 2                  670MB   idle  12m   myproj
_office_inventory() {
  local now=$(date +%s) id sess title pid act mb idle
  tmux list-panes -a -F '#{pane_id}|#{session_name}|#{@office_label}|#{pane_pid}|#{window_activity}|#{pane_current_command}' 2>/dev/null \
  | while IFS='|' read -r id sess title pid act cmd; do
      mb=$(_office_pane_mb "$pid")
      idle=$(( (now - act) / 60 ))
      [[ -z $title ]] && title=$cmd
      printf '%-5s %-26s %6sMB   idle %4sm   %s\n' "$id" "$title" "$mb" "$idle" "$sess"
    done
}

# total MB across every office
_office_total_mb() { _office_inventory | awk '{for(i=1;i<=NF;i++) if ($i ~ /MB$/) {gsub(/MB/,"",$i); s+=$i}} END {printf "%d", s+0}' }

# --- your own start and stop commands ----------------------------------------
# `office off` kills every process group its panes own, which covers everything
# you started inside the office. It cannot cover what you started OUTSIDE it: a
# launchd service, a systemd unit, a docker stack, a tunnel. Those survive any
# amount of killing inside tmux, and on macOS they are usually the reason the
# machine will not sleep.
#
# There is no way for this package to guess what yours is, so you name it once
# and `office on` / `office off` become the switch for it too:
#
#   OFFICE_ON_CMD          run when you walk in
#   OFFICE_OFF_CMD         run when you go home
#   OFFICE_RUNNING_CHECK   exits 0 when it is already up, so `office on` does
#                          not start it twice
#
# (The older OFFICE_ALWAYS_ON_START / _STOP / _CHECK names still work.)
#
# Empty by default, because the honest default is to touch nothing you did not
# ask for. Set them and going home really does mean everything is off.
: ${OFFICE_ON_CMD:=${OFFICE_ALWAYS_ON_START:-}}                # run by `office on`
: ${OFFICE_OFF_CMD:=${OFFICE_ALWAYS_ON_STOP:-}}                # run by `office off`
: ${OFFICE_RUNNING_CHECK:=${OFFICE_ALWAYS_ON_CHECK:-false}}    # exits 0 when it is up
_office_always_on() { eval "$OFFICE_RUNNING_CHECK"; }

# walking in restores whatever going home stopped — `office on` is the exact
# undo of `office off`. Skip it with `office solo` (tabs only, nothing started).
_office_always_on_up() {
  [[ -n $OFFICE_SOLO || -z $OFFICE_ON_CMD ]] && return 0
  # same trap as _office_editor: a one-word OFFICE_ON_CMD would be tested one
  # character at a time and the stack would never come up.
  command -v ${OFFICE_ON_CMD%% *} >/dev/null || return 0
  _office_always_on && return 0
  print -P "%F{green}==> $OFFICE_ON_CMD%f"
  eval "$OFFICE_ON_CMD"
}

_office_help() {
  local g="%F{green}" d="%F{240}" r="%f"
  print -P "${g}office${r} — your whole workday, in one command.${d}  (short alias: o)${r}\n"

  print -P "${g}YOUR DAY${r} ${d}— these three are 95%% of it${r}"
  print -P "  ${g}office on${r}      Start working. Opens your office, and starts whatever"
  print -P "                 ${d}else you told it to start (OFFICE_ON_CMD).${r}"
  print -P "                 ${d}Use it every morning, and to come back from a break.${r}"
  print -P "  ${g}office break${r}   Stepping away. Nothing stops — agents keep running,"
  print -P "                 ${d}the Mac stays busy. Lunch, a meeting, closing the laptop lid.${r}"
  print -P "  ${g}office off${r}     Done for the day. Quits every office and every agent in"
  print -P "                 ${d}them${OFFICE_OFF_CMD:+, and runs '$OFFICE_OFF_CMD'}. Asks first.${r}\n"

  print -P "${g}WHAT YOU GET${r} ${d}— ONE window. Everything visible at once.${r}"
  print -P "    ${d}┌─────────────────────────────┬──────────────┐${r}"
  print -P "    ${d}│${r} ${g}$OFFICE_SESSION_LABEL${r}                      ${d}│${r} ${g}$OFFICE_CHAT_LABEL${r}   ${d}│${r} ${g}^Space c${r}"
  print -P "    ${d}├─────────────────────────────┼──────────────┤${r}"
  print -P "    ${d}│${r} ${g}$OFFICE_SESSION_LABEL 2${r}   ${d}^Space n adds${r}  ${d}│${r} ${g}SHELL${r}        ${d}│${r} ${g}^Space s${r}"
  print -P "    ${d}│${r}              ${d}one more${r}       ${d}├──────────────┤${r}"
  print -P "    ${d}│${r}                             ${d}│${r} ${g}FILE EDITOR${r}  ${d}│${r} ${g}^Space e${r}"
  print -P "    ${d}└─────────────────────────────┴──────────────┘${r}"
  print -P "    ${d}  the agents that build it        the agent${r}"
  print -P "    ${d}  claude / codex / your own       you built${r}"
  print -P "  ${d}LEFT is whatever OFFICE_SESSION_CMD points at, up to four, kept even.${r}"
  print -P "  ${d}RIGHT is a shell, an editor, and a chat wired to the agent YOU built:${r}"
  print -P "  ${d}give OFFICE_CHAT_CMD a command and that pane is your control surface,${r}"
  print -P "  ${d}with no dashboard to stand up and no Slack app to register.\n${r}"

  print -P "${g}THE KEYS${r} ${d}— two rules, and the second one covers everything${r}"
  print -P "  ${g}Shift-←↑↓→${r}         move between panes"
  print -P "  ${d}...and Ctrl-Space, then one letter:${r}"
  print -P "  ${g}n${r}    a new session            ${d}its own worktree, left column, max 4${r}"
  print -P "  ${g}c${r}    toggle the CHAT          ${g}s${r}  toggle the SHELL"
  print -P "  ${g}e${r}    toggle the FILE EDITOR   ${g}a${r}  park/restore ALL sessions"
  print -P "  ${g}q${r}    CLOSE this pane          ${g}x${r}  park it, still running"
  print -P "  ${g}z${r}    zoom this pane           ${g}m${r}  mouse reporting on/off"
  print -P "  ${g}←↑↓→${r} move too                  ${d}the one way out of an open file${r}"
  print -P "  ${g}|${r} ${g}-${r}  split raw               ${g}X${r}  close the whole office"
  print -P "  ${g}Enter${r}  scrollback / copy mode  ${g}r${r}  reload the tmux config"
  print -P "  ${d}Only the arrows are a chord, because they carry their modifier natively.${r}"
  print -P "  ${d}Everything else is the prefix: no terminal setup, same on every OS.${r}"
  print -P "  ${d}Each border shows the key for that pane. Or just click one with the mouse:${r}"
  print -P "  ${d}drag across text to copy it, or double-click a word — either way it${r}"
  print -P "  ${d}is on the clipboard when you let go.
${r}"

  print -P "${g}RUNNING SEVERAL AGENTS${r} ${d}— the whole point of this setup${r}"
  print -P "  ${g}Ctrl-Space n${r}   One more session, in its OWN git worktree — a free one, or a"
  print -P "                 ${d}new desk-N. Press it 2-4x: the left column splits evenly and${r}"
  print -P "                 ${d}each agent edits a separate checkout, so they never collide.${r}"
  print -P "  ${g}office new X${r}   Straight into worktree X — created if it is not there yet."
  print -P "  ${g}office task X${r}  A new session already working on X."
  print -P "  ${g}office desk${r}    One more session in THIS checkout, when you mean it: two"
  print -P "                 ${d}agents on one branch, which the status line says out loud.${r}"
  print -P "                 ${d}Four desks is the cap, whichever door you use.${r}"
  print -P "  ${g}office edit${r}    Toggle the FILE EDITOR pane — fuzzy-pick a file, edit it in place."
  print -P "                 ${d}Ctrl-S saves · Ctrl-Z undo · mouse works.${r}"
  print -P "                 ${d}Ctrl-Q closes the FILE and returns you to the list;${r}"
  print -P "                 ${d}Esc at the list leaves the editor. Ctrl-Space e hides the pane.${r}"
  print -P "  ${g}office chat${r}    Toggle the $OFFICE_CHAT_LABEL pane. ${d}Ctrl-Space c inline.${r}"
  print -P "  ${g}office shell${r}   Toggle the SHELL pane. ${d}Ctrl-Space s inline.${r}"
  print -P "                 ${d}Toggled-off panes keep running — nothing is killed.${r}\n"

  print -P "${g}KEEPING IT LEAN${r} ${d}— nothing ever dies on its own, so check now and then${r}"
  print -P "  ${g}office doctor${r}  What is running and what it costs in RAM. Read-only,"
  print -P "                 ${d}nothing is touched. Every agent pane is 400-700MB.${r}"
  print -P "  ${g}office clean${r}   Added too many? This is the way out. Pick panes to close:"
  print -P "                 ${d}Tab marks, Enter closes them, Esc closes nothing. Heaviest${r}"
  print -P "                 ${d}first, and collapsed panes are in the list too — they still${r}"
  print -P "                 ${d}cost RAM. One at a time: Ctrl-Space q on the pane itself.${r}"
  print -P "  ${g}office list${r}    Same as doctor."
  print -P "  ${g}office update${r}  Pull the newest agent-office. Never happens on its own:"
  print -P "                 ${d}'office on' only tells you when you are behind.${r}"
  print -P "  ${g}office sweep${r}   Offices you walked away from, still holding memory with no"
  print -P "                 ${d}window anywhere. Lists them, asks, then closes them and${r}"
  print -P "                 ${d}everything inside. 'office sweep 2' for a 2-hour threshold.${r}"
  print -P "                 ${d}That is Claude Code's 'conversation moved to the background'${r}"
  print -P "                 ${d}screen, not the list. This restarts it. Nothing else is touched.${r}\n"

  print -P "${g}A DIFFERENT REPO${r}"
  print -P "  ${g}office <name>${r}  Open any repo by name — fuzzy, so 'proj' finds 'my-project'."
  print -P "  ${g}office pick${r}    Not sure of the name? Pick from every repo in $CODE_ROOT."
  print -P "  ${g}office solo${r}    Like 'on', but starts nothing — just the tabs."
  print -P "                 ${d}Use when you want the panes without the rest.${r}\n"

  print -P "${g}EDITING FILES${r} ${d}— no vim knowledge required${r}"
  print -P "  ${g}edit${r} / ${g}e${r}       Fuzzy-pick a file and edit it. Files you have changed"
  print -P "                 ${d}are listed first. Ctrl-S save · Ctrl-Q quit · Ctrl-Z undo${r}"
  print -P "                 ${d}Ctrl-F find · mouse and normal copy-paste all work.${r}"
  print -P "  ${g}edit <file>${r}    Open (or create) that file directly."
  print -P "  ${g}office edit${r}    A dedicated FILE EDITOR pane. ${d}Ctrl-Space e does it inline.${r}"
  print -P "  ${g}n${r}              Neovim instead, when you want the full IDE.\n"

  print -P "${g}IF YOU FORGET ONE THING, REMEMBER THIS${r}"
  print -P "  Closing the window never kills anything. ${g}office on${r} always brings"
  print -P "  you back exactly where you were, panes and all. Only ${g}office off${r} ends things."
}

# ------------------------------------------------------------------ office ---
# office <on|break|off|repo|pick|new|solo|doctor|clean> — your whole workspace, one word.
office() {
  local cmd=${1:-help} dir
  _office_pane_cwd                     # a key press stands where its pane stood
  # A shell keeps running the copy of this file it sourced when it started. That
  # is how `office off; office on` right after an update gives you back the OLD
  # office, in an old shape, with the fix you just installed nowhere in it —
  # and nothing on screen says why. If the file on disk has moved since, load it
  # and run the new one. Re-sourcing is idempotent: every setting is a default,
  # and add-zsh-hook does not double up.
  local _m; _m=$(zstat +mtime "$_OFFICE_HOME/office.zsh" 2>/dev/null)
  if [[ -n $_m && -n $_OFFICE_MTIME && $_m != $_OFFICE_MTIME ]]; then
    source "$_OFFICE_HOME/office.zsh" && { office "$@"; return }
  fi
  # ONE place, because every verb that moves a pane comes through here — typed,
  # aliased, or fired by a key binding's run-shell. See _office_unzoom for what
  # a zoomed window does to the geometry underneath. The exemptions are the
  # verbs that only print, detach, or close the whole thing: those never read a
  # column, so taking the operator's zoom away for them would be rude.
  [[ $cmd == (help|-h|--help|list|ls|status|doctor|check|update|upgrade|sweep|stale|break|pause|bg|away|brb|off|out|end|quit|stop|home) ]] \
    || _office_unzoom "$(_office_here)"
  case $cmd in
    on|up|in|back|work|resume)
      dir=$(_office_find "$OFFICE_DEFAULT") || true
      [[ -z $dir ]] && dir=$(_office_root "$PWD")
      _office_open "$dir" ;;
    pick)
      dir=$(_office_repos | sed "s|^$HOME/|~/|" \
            | fzf --prompt='repo> ' --height=60% --reverse \
                  --preview "eza -la --icons --git --color=always \$(echo {} | sed \"s|^~|$HOME|\") 2>/dev/null | head -40") || return
      _office_open "${dir/#\~/$HOME}" ;;
    new|+)
      shift; _office_new "$@" ;;
    solo)
      OFFICE_SOLO=1 office on ;;
    desk|claude)
      _office_add_pane "$OFFICE_SESSION_LABEL" "$OFFICE_SESSION_CMD$_OFFICE_DESK_END" "$(_office_root "$PWD")" CLAUDE ;;
    task|do|go)
      shift
      (( $# )) || { print -u2 "usage: office task <what you want done>"; return 1 }
      _office_add_pane "$OFFICE_SESSION_LABEL · $*" "$OFFICE_SESSION_CMD ${(q)*}$_OFFICE_DESK_END" "$(_office_root "$PWD")" CLAUDE ;;
    # the three right-strip panes are TOGGLES: same word closes what it opened.
    chat|talk)
      _office_toggle CHAT   "$OFFICE_CHAT_LABEL" "$OFFICE_CHAT_CMD" ;;
    shell|sh|term)
      _office_toggle SHELL  "$(_office_strip_title "$(_office_root "$PWD")")" 'exec zsh' ;;
    edit|editor|files)
      # loop the picker: quitting a file (Ctrl-Q) drops you back at the file
      # list, not at a shell. Esc at the list is how you actually leave.
      _office_toggle EDITOR "FILE EDITOR" "$_OFFICE_EDITOR_CMD" ;;
    sessions|desks)
      # the whole left column, in one key. Park them all, or bring them all back.
      local s p n=0
      s=$(_office_here)
      for p in ${(f)"$(tmux list-panes -t "=$s" -F '#{pane_id}|#{@office_kind}' 2>/dev/null | awk -F'|' '$2=="CLAUDE"{print $1}')"}; do
        [[ -n $p ]] || continue
        _office_hide "$p"; (( n++ ))
      done
      (( n )) && { _office_number "$s"; return }
      # Restoring is bounded by the cap, not by what happens to be in the stash:
      # sessions parked one at a time weeks ago should not all come flooding
      # back because you pressed the group toggle.
      local back=0
      while (( $(_office_desk_count "$s") < _OFFICE_MAX_DESKS )); do
        _office_unhide "$s" CLAUDE || break
        (( back++ ))
      done
      # Nothing visible and nothing parked: make one. This key must never do
      # nothing. A silent no-op reads as a broken binding, and the honest answer
      # to "show me my sessions" when there are none is to open one. Every other
      # toggle already worked this way; this was the one that did not.
      (( back )) || _office_add_pane "$OFFICE_SESSION_LABEL" "$OFFICE_SESSION_CMD$_OFFICE_DESK_END" \
                      "$(_office_root "$PWD")" CLAUDE
      _office_number "$s" ;;
    update|upgrade)
      [[ -d $_OFFICE_HOME/.git ]] || { print -u2 "office: $_OFFICE_HOME is not a git checkout"; return 1 }
      if [[ -n $(git -C "$_OFFICE_HOME" status --porcelain) ]]; then
        print -u2 "office: $_OFFICE_HOME has local changes. Commit or stash them first."
        git -C "$_OFFICE_HOME" status --short | sed 's/^/  /'
        return 1
      fi
      git -C "$_OFFICE_HOME" pull --ff-only || return 1
      _office_reload_conf
      print "updated. The next 'office' command in any shell runs the new version;"
      print "panes already open keep what they are running until you close them." ;;
    renumber)
      _office_number "$(_office_here)" ;;
    sweep|stale)
      # `office sweep [hours]` — offices nobody has looked at in that long, and
      # everything inside them. Default 12h, so yesterday's office is fair game
      # and the one you detached at lunch is not.
      local -a stale; stale=(${(f)"$(_office_stale ${2:-12})"})
      if (( ! $#stale )); then print "office: nothing stale. Every office is either open or recent."; return; fi
      local mb=0 line
      for line in $stale; do mb=$(( mb + ${${(z)line}[3]} )); done
      print -P "%F{yellow}${#stale} office(s) detached and idle, holding ~${mb}MB:%f"
      for line in $stale; do
        print "  ${${(z)line}[1]}  idle $(( ${${(z)line}[2]} / 60 ))h  ${${(z)line}[3]}MB"
      done
      if [[ $2 == (-y|--yes) || $3 == (-y|--yes) ]]; then :
      else
        print -n "close them, and everything running inside? [y/N] "; read -q _ans 2>/dev/null; print
        [[ $_ans == y ]] || { unset _ans; print "left alone."; return }
        unset _ans
      fi
      local -a groups
      for line in $stale; do
        groups+=(${(f)"$(_office_pane_groups "${${(z)line}[1]}")"})
        tmux kill-session -t "=${${(z)line}[1]}" 2>/dev/null
      done
      (( $#groups )) && _office_kill_groups ${(u)groups}
      print -P "swept ${#stale} office(s). %F{green}~${mb}MB%f back." ;;
    layout|fix|repair)
      _office_relayout "$(_office_here)"; print "layout rebuilt." ;;
    hide|collapse)
      _office_hide "${2:-$(tmux display -p '#{pane_id}')}" ;;
    show|restore|back)
      local s k; s=$(_office_here)
      k=${2:-$(tmux list-windows -t "=$_OFFICE_STASH" -F '#{window_name}' 2>/dev/null \
               | fzf --prompt='bring back> ' --height=40% --reverse)}
      [[ -n $k ]] || return
      _office_unhide "$s" "${(U)k}" || print -u2 "office: nothing stashed as '$k'" ;;
    break|pause|bg|away|brb)
      local -a live; live=(${(f)"$(_office_sessions)"})
      (( $#live )) || { print "office: nothing running"; return }
      print -P "%F{green}on a break%f — ${#live} office(s) and everything in them keep running:"
      printf '  %s\n' $live
      print -P "  back in with %F{green}office on%f"
      [[ -n $TMUX ]] && tmux detach-client ;;

    off|out|end|quit|stop|home)
      local -a live always; live=(${(f)"$(_office_sessions)"})
      _office_always_on && always=1
      if (( ! $#live )) && (( ! $#always )); then print "office: nothing running"; return; fi
      print "going home means:"
      (( $#live )) && { print "  quit ${#live} office(s) + every agent in them:"; printf '    %s\n' $live }
      (( $#live )) && print "  reset the layout to default: sizes, parked panes, all of it"
      (( $#live )) && print "  kill every process any pane started, detached ones included"
      (( $#always )) && print "  run '$OFFICE_OFF_CMD' (stops the always-on stack, Mac can sleep)"
      if [[ $2 != (-y|--yes) ]]; then
        print -n "go home? [y/N] "; read -q _ans 2>/dev/null; print
        [[ $_ans == y ]] || { unset _ans; print "still here."; return }
        unset _ans
      fi
      (( $#always )) && { print -P "%F{green}==> $OFFICE_OFF_CMD%f"; eval "$OFFICE_OFF_CMD" }
      local -a groups; groups=(${(f)"$(_office_pane_groups)"})
      tmux kill-server 2>/dev/null
      (( $#groups )) && _office_kill_groups $groups
      print -P "%F{green}office closed. see you tomorrow.%f" ;;

    list|ls|status|doctor|check)
      local -a inv; inv=(${(f)"$(_office_inventory)"})
      if (( $#inv )); then
        print -P "%F{green}PANE  WHAT                          MEMORY   IDLE      OFFICE%f"
        printf '%s\n' $inv
        local total idle_mb
        total=$(_office_total_mb)
        idle_mb=$(printf '%s\n' $inv | awk '{m=0; for(i=1;i<=NF;i++){ if ($i ~ /MB$/){gsub(/MB/,"",$i); m=$i} if ($i ~ /^[0-9]+m$/){gsub(/m/,"",$i); if ($i+0>=60) s+=m} }} END {printf "%d", s+0}')
        print -P "\n${#inv} pane(s), %F{green}${total}MB%f total"
        (( idle_mb > 0 )) && print -P "  %F{yellow}${idle_mb}MB sitting in panes idle over an hour%f — reclaim with 'office clean'"
      else
        print "no offices running"
      fi
      _office_always_on \
        && print -P "always-on: %F{green}up%f (stop with '$OFFICE_OFF_CMD')" \
        || print "always-on: down (start with 'office on')" ;;

    clean|gc|tidy)
      local -a inv sel; inv=(${(f)"$(_office_inventory)"})
      (( $#inv )) || { print "office: nothing running"; return }
      # `office clean --idle [hours]` skips the picker and closes anything that
      # has sat untouched that long. For a cron or a shell alias, not for you.
      if [[ $2 == (--idle|-i) ]]; then
        local hrs=${3:-2} n=0 freed=0 line f
        for line in $inv; do
          [[ $line == *"idle "*[0-9]m* ]] || continue
          local mins=${${${line##*idle }%%m*}// /}
          (( mins >= hrs * 60 )) || continue
          for f in ${(z)line}; do [[ $f == *MB ]] && freed=$(( freed + ${f%MB} )); done
          tmux kill-pane -t "${line%% *}" 2>/dev/null && (( n++ ))
        done
        print "closed $n pane(s) idle over ${hrs}h, ~${freed}MB reclaimed."
        return
      fi
      sel=(${(f)"$(printf '%s\n' $inv | sort -t M -k1 -nr | fzf -m --height=60% --reverse \
            --header='Tab marks a pane to close, Enter closes them. Esc = close nothing.' \
            --prompt='close> ')"}) || return
      (( $#sel )) || { print "nothing closed."; return }
      local line target freed=0 f
      for line in $sel; do
        target=${line%% *}
        for f in ${(z)line}; do [[ $f == *MB ]] && freed=$(( freed + ${f%MB} )); done
        tmux kill-pane -t "$target" 2>/dev/null
      done
      print -P "closed ${#sel} pane(s), %F{green}~${freed}MB%f reclaimed."
      tmux list-sessions >/dev/null 2>&1 || print "  (that was the last one — no offices left)" ;;
    help|-h|--help)
      _office_help ;;
    *)
      dir=$(_office_find "$cmd")
      [[ -n $dir ]] || { print -u2 "office: no repo matching '$cmd' (try: office pick)"; return 1 }
      _office_open "$dir" ;;
  esac
}

alias o=office
alias ao=office
