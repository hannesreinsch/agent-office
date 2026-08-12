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
#   office desk       add another session to the left column         (^Sn)
#   office task ...   ...and start it on a task straight away
#   office new [wt]   ...the same, but in its own git worktree
#   office chat       toggle the chat pane                           (^Sc)
#   office shell      toggle the shell pane                          (^Ss)
#   office edit       toggle the editor pane                         (^Se)
#   office hide/show  collapse the pane you are on / bring one back  (^Sx)
#   office layout     rebuild the two columns if they ever look wrong
#
#   office doctor     what's running and what it costs in RAM (read-only)
#   office clean      pick panes to close and reclaim their RAM
#
# Bare `office` prints this. `ao` and `o` are the short aliases.
# Key bindings live in office.tmux.conf; `office help` lists every one of them.
# Configure with the OFFICE_* variables below; see the README.

_OFFICE_HOME=${0:A:h}                  # where this package lives, for its helpers
CODE_ROOT="${CODE_ROOT:-$HOME/code}"
OFFICE_DEFAULT="${OFFICE_DEFAULT:-}"        # repo `office on` opens; empty = the one you are in
# The chat pane: whatever talking to your agent looks like. Point it at your own
# chat command and it becomes that. Left as a plain shell by default.
# What a session IS. Point it at any agent CLI and the left column becomes that.
OFFICE_SESSION_CMD="${OFFICE_SESSION_CMD:-claude}"
OFFICE_SESSION_LABEL="${OFFICE_SESSION_LABEL:-CLAUDE}"
# Where `office new` looks for git worktrees. Claude Code's default location.
OFFICE_WORKTREE_DIR="${OFFICE_WORKTREE_DIR:-.claude/worktrees}"
# How much of the window the right strip takes. Wide enough that a chat pane
# does not wrap every sentence, narrow enough that the agents keep the room.
OFFICE_STRIP_WIDTH="${OFFICE_STRIP_WIDTH:-32}"
OFFICE_CHAT_LABEL="${OFFICE_CHAT_LABEL:-AGENT CHAT}"
OFFICE_CHAT_CMD="${OFFICE_CHAT_CMD:-exec $SHELL}"

# ---------------------------------------------------------------- internals --
_office_sessname() { basename "$1" | tr ' .:' '___'; }
_office_root()     { git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null || print -r -- "${1:-$PWD}"; }

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
    [[ -n $e ]] && command -v ${${(z)e}[1]} >/dev/null && { print -r -- "$e"; return }
  done
  print -r -- vi
}

# fuzzy-pick a file and open it. Files you have changed come first: it is nearly
# always one of them. Returns non-zero when you cancel, which is what lets the
# editor pane loop until you actually want out.
zmodload -F zsh/stat b:zstat 2>/dev/null

# Where the shell pane is standing right now, or this shell's own directory when
# there is no office and no shell pane.
_office_shell_dir() {
  local s d
  s=$(_office_sessname "$(_office_root "$PWD")")
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
  s=$(_office_sessname "$(_office_root "$PWD")")
  local tty
  # NB: #{pane_current_command} says "zsh" here, because fzf is a child of the
  # loop rather than the pane's own process. Ask the pane's terminal instead.
  read -r p tty <<< "$(tmux list-panes -t "=$s" -F '#{pane_id} #{pane_tty} #{@office_kind}' 2>/dev/null \
      | awk '$3=="EDITOR" {print $1, $2; exit}')"
  [[ -n $p && -n $tty ]] || return 0
  ps -t "${tty#/dev/}" -o comm= 2>/dev/null | grep -qx 'fzf' || return 0
  tmux send-keys -t "$p" C-r 2>/dev/null
  return 0
}

# Every interactive zsh inside tmux gets the hook; the function itself decides
# whether this pane is the office's shell. It costs one tmux query per `cd`.
if [[ -n $TMUX && -o interactive ]]; then
  autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _office_editor_sync
fi

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
    sess=$(_office_sessname "$(_office_root "$PWD")")
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
    $ed -statusline true \
        -statusformatr "^S save   ^Q back to the file list   ^Z undo   ^F find" \
        "$target"
  else
    $ed "$target"
  fi
}


# --- the right strip: shell, editor, chat, top to bottom ---------------------
# The order is data, so a pane that is toggled off and back on lands where it
# belongs instead of at the bottom.
typeset -gA _OFFICE_STRIP_ORDER=(SHELL 1 EDITOR 2 CHAT 3)
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
#   dim  the pane is open, there is nothing to tell you
#   lit  the pane is closed, this is the one you cannot find
_OFFICE_BAR_OPEN='#[fg=#4e505a]'
_OFFICE_BAR_SHUT='#[fg=#9a9ca6]'
_OFFICE_BAR_DO='#[fg=#6a6c77]'
_OFFICE_BAR_SEP='#[fg=#3a3c44]'
_office_bar() {                        # <session>
  local open out sep="" pair kind name key tone
  open=" $(tmux list-panes -t "=$1" -F '#{@office_kind}' 2>/dev/null | tr '\n' ' ')"
  out="${_OFFICE_BAR_DO}+ new ⌃⇧n#[default]   ${_OFFICE_BAR_SEP}│#[default]  "
  for pair in "CLAUDE:sessions:⌃⇧a" "SHELL:shell:⌃⇧s" "EDITOR:editor:⌃⇧e" "CHAT:chat:⌃⇧c"; do
    kind=${pair%%:*}; name=${${pair#*:}%%:*}; key=${pair##*:}
    [[ $open == *" $kind "* ]] && tone=$_OFFICE_BAR_OPEN || tone=$_OFFICE_BAR_SHUT
    out+="${sep}${tone}${name} ${key}#[default]"
    sep="${_OFFICE_BAR_SEP} · #[default]"
  done
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
  return 0
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

# label a pane. An agent overwrites #{pane_title} with whatever it is doing,
# so the ROLE lives in a user option the app cannot touch, and the border shows
# both: "CLAUDE . rename the auth module".
#
# @office_kind is the STABLE identity (CHAT, SHELL, EDITOR, CLAUDE) that
# the toggles match on — the visible label carries a repo and a branch and moves.
# The key each pane's border advertises, which is the one you actually want on
# that pane and differs by kind:
#
#   a glance pane  its own toggle. The same key parks it and brings it back,
#                  so parking is the natural verb: you will want it again.
#   a session      ⌃⇧w, close. There is no per-session restore, because there
#                  is no fixed slot to restore into, so closing is the honest
#                  verb. (⌃⇧x still parks one, and ⌃⇧a parks the whole column.)
typeset -gA _OFFICE_KEYS=(SHELL '⌃⇧s' EDITOR '⌃⇧e' CHAT '⌃⇧c' CLAUDE '⌃⇧w')

_office_label() {                      # <pane> <label> [kind]
  # '#' is stripped: the label is rendered through tmux's format engine, where
  # #(...) runs a shell command. A branch name or an `office task` description
  # containing one would otherwise be executed every time the border redraws.
  tmux set -p -t "$1" @office_label "${2//\#/}" 2>/dev/null
  tmux set -p -t "$1" @office_kind "${3:-$2}" 2>/dev/null
  tmux set -p -t "$1" @office_key "${_OFFICE_KEYS[${3:-$2}]}" 2>/dev/null
}

# say something to the operator. A keybinding runs with no terminal attached, so
# a bare `print` becomes stray run-shell output — and tmux shows THAT by forcing
# the active pane into view-mode, where every Ctrl-Shift chord stops working.
# The status line is the only safe place to talk from.
_office_say() {
  tmux display-message " office: $1" 2>/dev/null || print -u2 "office: $1"
}

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
  local kind; kind=$(tmux display -p -t "$1" '#{@office_kind}' 2>/dev/null)
  [[ -n $kind ]] || kind=pane
  _office_stash_ensure
  # two parked CLAUDE desks would otherwise both be a window called "claude", and
  # only ever one of them could be found again. The pane id makes it unique, and
  # _office_unhide matches on the "<kind>-" prefix.
  local name="${(L)kind}-${1#\%}"
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
  w=$(tmux list-windows -t "=$_OFFICE_STASH" -F '#{window_id} #{window_name}' 2>/dev/null \
      | awk -v n="${(L)2}" '$2==n || index($2, n "-")==1 {print $1; exit}')
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

# The cockpit. ONE window. The LEFT column is nothing but agent sessions —
# three of them, open and ready. The RIGHT strip holds everything you glance at,
# and every one of those four is a toggle:
#
#   +-------------------------------+-----------+
#   |  CLAUDE                       | SHELL     |  ^Ss
#   +-------------------------------+-----------+
#   |  CLAUDE 2                     | EDITOR    |  ^Se
#   |                               +-----------+
#   |                               | CHAT      |  ^Sc  (opens on demand)
#   +-------------------------------+-----------+
#   |                               | EDITOR    |  ^Se
#   +-------------------------------+-----------+
#
# CHAT (^Sc) is the one pane that starts closed: point OFFICE_CHAT_CMD at your
# own agent's chat command first, or it is just another shell.
#
# ^Sn adds a session to the left column, ^Sw closes whatever pane you are on.
_OFFICE_DEFAULT_DESKS=${OFFICE_DEFAULT_DESKS:-1}
_office_open() {                       # <repo-path>
  local dir=$1 s
  s=$(_office_sessname "$dir")
  if ! tmux has-session -t "=$s" 2>/dev/null; then
    local main editor strip n prev
    main=$(tmux new-session -d -s "$s" -c "$dir" -n office -P -F '#{pane_id}' "$OFFICE_SESSION_CMD; exec zsh")
    _office_label "$main" "$OFFICE_SESSION_LABEL" CLAUDE
    # the right strip first, at OFFICE_STRIP_WIDTH: these are glance surfaces, and
    # width once here is what leaves the sessions a full-width column.
    strip=$(tmux split-window -h -l ${OFFICE_STRIP_WIDTH}% -t "$main" -c "$dir" -P -F '#{pane_id}')
    _office_label "$strip" "$(_office_strip_title "$dir")" SHELL
    # The editor comes up too: everyone needs a file open sooner or later.
    # CHAT does NOT, because a chat pane is only worth the space once you have
    # pointed OFFICE_CHAT_CMD at your own agent. Open it with Ctrl-Shift-c.
    editor=$(tmux split-window -v -t "$strip" -c "$dir" -P -F '#{pane_id}' 'zsh -ic "while _office_pick_file; do :; done; exec zsh"')
    _office_label "$editor" "EDITOR" EDITOR
    # the rest of the sessions, stacked down the left. Split the one just made,
    # not the tallest — otherwise desk 3 lands between 1 and 2 and the labels lie.
    local prev=$main
    # C-style, not {2..$N}: zsh counts a brace range DOWNWARDS when the start
    # is past the end, so a single-desk default would silently open three.
    for (( n = 2; n <= _OFFICE_DEFAULT_DESKS; n++ )); do
      prev=$(tmux split-window -v -t "$prev" -c "$dir" -P -F '#{pane_id}' "$OFFICE_SESSION_CMD; exec zsh")
      _office_label "$prev" "$OFFICE_SESSION_LABEL $n" CLAUDE
    done
    _office_even_desks "$s"
    _office_number "$s"
    tmux select-pane -t "$main"
  fi
  cd "$dir"
  _office_number "$s"                  # also writes the key strip
  _office_reap                         # walking in takes the bins out
  _office_always_on_up                 # restore whatever `office off` stopped
  _office_attach "$s"
}

_office_new() {                        # [worktree-name] -> extra session
  local root wt dir label
  root=$(_office_root "$PWD"); wt="$root/$OFFICE_WORKTREE_DIR"
  if [[ -z $1 ]]; then
    dir=$( { print -r -- "$root"; [[ -d $wt ]] && fd --type d --max-depth 1 . "$wt" 2>/dev/null; } \
           | sed 's|/$||' | fzf --prompt='session in> ' --height=40% --reverse) || return
  elif [[ -d $wt/$1 ]]; then dir="$wt/$1"
  elif [[ -d $1 ]];    then dir=$(cd "$1" && pwd)
  else print -u2 "office: no worktree or directory '$1'"; return 1
  fi
  label=$(basename "$dir")
  [[ $dir == "$root" ]] && label="$OFFICE_SESSION_LABEL" || label="$OFFICE_SESSION_LABEL · $label"

  local s; s=$(_office_sessname "$root")
  tmux has-session -t "=$s" 2>/dev/null \
    || { _office_say "no office open — run 'office on' first"; return 0 }

  # split the tallest desk in the left column, so agents stack down the left and
  # the right strip keeps its width
  local newp
  newp=$(tmux split-window -v -t "$(_office_desk_pane "$s")" -c "$dir" -P -F '#{pane_id}' "$OFFICE_SESSION_CMD; exec zsh")
  _office_label "$newp" "$label" CLAUDE
  _office_even_desks "$s"
  # not inside tmux and not on a terminal (a run-shell keybinding) — nothing to attach to
  [[ -n $TMUX || ! -t 1 ]] || _office_attach "$s"
}

# add a pane running <command>. A ranked kind (CHAT/SHELL/EDITOR) lands in the
# right strip, in its place; anything else is a desk in the left column, which
# is capped and re-evened.
_office_add_pane() {                   # <label> <command> [dir] [kind]
  local s newp dir=${3:-$PWD} kind=${4:-${1}}
  local -a slot
  s=$(_office_sessname "$(_office_root "$PWD")")
  tmux has-session -t "=$s" 2>/dev/null \
    || { _office_say "no office open — run 'office on' first"; return 0 }
  if [[ $(_office_rank "$kind") == 9 ]] && (( $(_office_desk_count "$s") >= _OFFICE_MAX_DESKS )); then
    _office_say "left column is full ($_OFFICE_MAX_DESKS sessions) — close one with Ctrl-Shift-w"
    return 0
  fi
  slot=($(_office_place "$s" "$kind"))
  newp=$(tmux split-window ${slot[2,-1]} -t "${slot[1]}" -c "$dir" -P -F '#{pane_id}' "$2") || return 1
  _office_label "$newp" "$1" "$kind"
  _office_layout_ok "$s" || _office_relayout "$s"
  _office_even_column "$s" left; _office_even_column "$s" right
  _office_number "$s"
  # not inside tmux and not on a terminal (a run-shell keybinding) — nothing to attach to
  [[ -n $TMUX || ! -t 1 ]] || _office_attach "$s"
}

# ONE verb for the three panes that come and go: on screen -> stash it;
# stashed -> put it back; never existed -> make it.
_office_toggle() {                     # <kind> <label> <command>
  local s p root; root=$(_office_root "$PWD"); s=$(_office_sessname "$root")
  tmux has-session -t "=$s" 2>/dev/null \
    || { _office_say "no office open — run 'office on' first"; return 0 }
  p=$(_office_pane_of_kind "$s" "$1")
  [[ -n $p ]] && { _office_hide "$p"; return }
  _office_unhide "$s" "$1" && return
  _office_add_pane "$2" "$3" "$root" "$1"
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

# --- an optional always-on stack ---------------------------------------------
# If your setup has background services that should come up when you walk in and
# go down when you go home, name them here and `office on`/`office off` become
# the switch. Three variables, all empty by default, all plain shell:
#   OFFICE_ALWAYS_ON_CHECK   exits 0 when the stack is up
#   OFFICE_ALWAYS_ON_START   brings it up
#   OFFICE_ALWAYS_ON_STOP    takes it down
: ${OFFICE_ALWAYS_ON_CHECK:=false}
: ${OFFICE_ALWAYS_ON_STOP:=}
: ${OFFICE_ALWAYS_ON_START:=}
_office_always_on() { eval "$OFFICE_ALWAYS_ON_CHECK"; }

# walking in restores whatever going home stopped — `office on` is the exact
# undo of `office off`. Skip it with `office solo` (tabs only, nothing started).
_office_always_on_up() {
  [[ -n $OFFICE_SOLO || -z $OFFICE_ALWAYS_ON_START ]] && return 0
  command -v ${${(z)OFFICE_ALWAYS_ON_START}[1]} >/dev/null || return 0
  _office_always_on && return 0
  print -P "%F{green}==> $OFFICE_ALWAYS_ON_START%f"
  eval "$OFFICE_ALWAYS_ON_START"
}

_office_help() {
  local g="%F{green}" d="%F{240}" r="%f"
  print -P "${g}office${r} — your whole workday, in one command.${d}  (short alias: o)${r}\n"

  print -P "${g}YOUR DAY${r} ${d}— these three are 95%% of it${r}"
  print -P "  ${g}office on${r}      Start working. Opens your office, and starts whatever"
  print -P "                 ${d}else you told it to start (OFFICE_ALWAYS_ON_START).${r}"
  print -P "                 ${d}Use it every morning, and to come back from a break.${r}"
  print -P "  ${g}office break${r}   Stepping away. Nothing stops — agents keep running,"
  print -P "                 ${d}the Mac stays busy. Lunch, a meeting, closing the laptop lid.${r}"
  print -P "  ${g}office off${r}     Done for the day. Quits every office and every agent in"
  print -P "                 ${d}them${OFFICE_ALWAYS_ON_STOP:+, and runs '$OFFICE_ALWAYS_ON_STOP'}. Asks first.${r}\n"

  print -P "${g}WHAT YOU GET${r} ${d}— ONE window. Everything visible at once.${r}"
  print -P "    ${d}┌─────────────────────────────┬──────────────┐${r}"
  print -P "    ${d}│${r} ${g}CLAUDE${r}                      ${d}│${r} ${g}SHELL${r}        ${d}│${r} ${g}⌃⇧s${r}"
  print -P "    ${d}├─────────────────────────────┤${r}──────────────${d}┤${r}"
  print -P "    ${d}│${r} ${g}CLAUDE 2${r}                    ${d}│${r} ${g}EDITOR${r}       ${d}│${r} ${g}⌃⇧e${r}"
  print -P "    ${d}│${r}                             ${d}├──────────────┤${r}"
  print -P "    ${d}│${r}                             ${d}│${r} ${g}EDITOR${r}       ${d}│${r} ${g}⌃⇧e${r}"
  print -P "    ${d}├─────────────────────────────┤${r}──────────────${d}┤${r}"
  print -P "    ${d}│${r} ${g}CLAUDE 3${r}                    ${d}│${r} ${g}$OFFICE_CHAT_LABEL${r}   ${d}│${r} ${g}⌃⇧c${r}"
  print -P "    ${d}└─────────────────────────────┴──────────────┘${r}"
  print -P "  ${d}LEFT is nothing but agent sessions, open from the${r}"
  print -P "  ${d}start. RIGHT is everything you only glance at, top to bottom in the${r}"
  print -P "  ${d}order you reach for them, and each of those four is a toggle.${r}"
  print -P "  ${d}CHAT starts closed: set OFFICE_CHAT_CMD to your agent's chat command${r}"
  print -P "  ${d}first, or it is just another shell. Then Ctrl-Shift-c opens it.\n${r}"

  print -P "${g}THE KEYS${r} ${d}— Ctrl-Shift does everything. No prefix, no chords to learn.${r}"
  print -P "  ${g}Ctrl-Shift-←↑↓→${r}    move between panes"
  print -P "  ${g}Ctrl-Shift-n${r}       NEW session               ${d}left column, max 4${r}"
  print -P "  ${g}Ctrl-Shift-c${r}       toggle the CHAT pane"
  print -P "  ${g}Ctrl-Shift-s${r}       toggle the SHELL pane"
  print -P "  ${g}Ctrl-Shift-e${r}       toggle the EDITOR pane"
  print -P "  ${g}Ctrl-Shift-a${r}       park every session at once, or bring them all back"
  print -P "  ${g}Ctrl-Shift-w${r}       CLOSE this pane           ${d}gone, and the RAM back${r}"
  print -P "  ${g}Ctrl-Shift-x${r}       park this pane            ${d}it keeps running${r}"
  print -P "  ${d}Each border shows the key you usually want there: a glance pane shows${r}"
  print -P "  ${d}its toggle, a session shows ⌃⇧w, because a session has no slot of its${r}"
  print -P "  ${d}own to be restored into. Both keys work on any pane.${r}"
  print -P "  ${g}Ctrl-Shift-z${r}       zoom this pane fullscreen / back"
  print -P "  ${d}w closes, x parks. A parked pane comes back with its own toggle, or${r}"
  print -P "  ${d}with 'office show'. Park is not free — it still holds its memory.${r}"
  print -P "  ${d}Ctrl-Shift on the LETTERS needs the 'office' iTerm profile — that is${r}"
  print -P "  ${d}where the chord is translated. Everything below works without it.\n${r}"

  print -P "${g}THE SAME THINGS, THE TWO-KEY WAY${r} ${d}— prefix is Ctrl-Space, then a letter${r}"
  print -P "  ${g}s e c${r}       shell · editor · chat ${d}(same toggles)${r}"
  print -P "  ${g}n${r}           a new session"
  print -P "  ${g}Z${r}           collapse this pane   ${g}z${r}  zoom it"
  print -P "  ${g}h j k l${r}     move left · down · up · right"
  print -P "  ${g}H J K L${r}     resize this pane by 5, same directions"
  print -P "  ${g}m${r}           mouse reporting on/off ${d}(off = a plain I-beam pointer)${r}"
  print -P "  ${g}x${r}           close this pane      ${g}X${r}  close the whole office"
  print -P "  ${g}|${r} ${g}-${r}         split right / split down, raw"
  print -P "  ${g}C${r}           a new window         ${g}S${r}  jump to another office"
  print -P "  ${g}Enter${r}       scrollback / copy mode ${d}— v selects, y copies, q leaves${r}"
  print -P "  ${g}r${r}           reload the tmux config"
  print -P "  ${d}Or just click a pane with the mouse.\n${r}"

  print -P "${g}RUNNING SEVERAL AGENTS${r} ${d}— the whole point of this setup${r}"
  print -P "  ${g}office new${r}     One more session, in its OWN git worktree, as a new pane."
  print -P "                 ${d}Run it 2-4x — the left column splits evenly. Each${r}"
  print -P "                 ${d}agent edits a separate checkout, so they never collide.${r}"
  print -P "  ${g}office new X${r}   Same, straight into worktree X."
  print -P "  ${g}office task X${r}  A new session already working on X."
  print -P "  ${g}office desk${r}    One more session in THIS repo, straight into the left column."
  print -P "                 ${d}Ctrl-Space a does the same. Four desks is the cap.${r}"
  print -P "  ${g}office edit${r}    Toggle the EDITOR pane — fuzzy-pick a file, edit it in place."
  print -P "                 ${d}Ctrl-S saves · Ctrl-Z undo · mouse works.${r}"
  print -P "                 ${d}Ctrl-Q closes the FILE and returns you to the list;${r}"
  print -P "                 ${d}Esc at the list leaves the editor. Ctrl-Shift-e hides the pane.${r}"
  print -P "  ${g}office chat${r}    Toggle the $OFFICE_CHAT_LABEL pane. ${d}Ctrl-Space c inline.${r}"
  print -P "  ${g}office shell${r}   Toggle the SHELL pane. ${d}Ctrl-Space s inline.${r}"
  print -P "                 ${d}Toggled-off panes keep running — nothing is killed.${r}\n"

  print -P "${g}KEEPING IT LEAN${r} ${d}— nothing ever dies on its own, so check now and then${r}"
  print -P "  ${g}office doctor${r}  What is running and what it costs in RAM. Read-only,"
  print -P "                 ${d}nothing is touched. Every agent pane is 400-700MB.${r}"
  print -P "  ${g}office clean${r}   Added too many? This is the way out. Pick panes to close:"
  print -P "                 ${d}Tab marks, Enter closes them, Esc closes nothing. Heaviest${r}"
  print -P "                 ${d}first, and collapsed panes are in the list too — they still${r}"
  print -P "                 ${d}cost RAM. One at a time: Ctrl-Shift-w on the pane itself.${r}"
  print -P "  ${g}office list${r}    Same as doctor."
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
  print -P "  ${g}office edit${r}    A dedicated EDITOR pane. ${d}Ctrl-Space e does it inline.${r}"
  print -P "  ${g}n${r}              Neovim instead, when you want the full IDE.\n"

  print -P "${g}IF YOU FORGET ONE THING, REMEMBER THIS${r}"
  print -P "  Closing the window never kills anything. ${g}office on${r} always brings"
  print -P "  you back exactly where you were, panes and all. Only ${g}office off${r} ends things."
}

# ------------------------------------------------------------------ office ---
# office <on|break|off|repo|pick|new|solo|doctor|clean> — your whole workspace, one word.
office() {
  local cmd=${1:-help} dir
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
      _office_add_pane "$OFFICE_SESSION_LABEL" "$OFFICE_SESSION_CMD; exec zsh" "$(_office_root "$PWD")" CLAUDE ;;
    task|do|go)
      shift
      (( $# )) || { print -u2 "usage: office task <what you want done>"; return 1 }
      _office_add_pane "$OFFICE_SESSION_LABEL · $*" "$OFFICE_SESSION_CMD ${(q)*}; exec zsh" "$(_office_root "$PWD")" CLAUDE ;;
    # the three right-strip panes are TOGGLES: same word closes what it opened.
    chat|talk)
      _office_toggle CHAT   "$OFFICE_CHAT_LABEL" "$OFFICE_CHAT_CMD" ;;
    shell|sh|term)
      _office_toggle SHELL  "$(_office_strip_title "$(_office_root "$PWD")")" 'exec zsh' ;;
    edit|editor|files)
      # loop the picker: quitting a file (Ctrl-Q) drops you back at the file
      # list, not at a shell. Esc at the list is how you actually leave.
      _office_toggle EDITOR "EDITOR" 'zsh -ic "while _office_pick_file; do :; done; exec zsh"' ;;
    sessions|desks)
      # the whole left column, in one key. Park them all, or bring them all back.
      local s p n=0
      s=$(_office_sessname "$(_office_root "$PWD")")
      for p in ${(f)"$(tmux list-panes -t "=$s" -F '#{pane_id}|#{@office_kind}' 2>/dev/null | awk -F'|' '$2=="CLAUDE"{print $1}')"}; do
        [[ -n $p ]] || continue
        _office_hide "$p"; (( n++ ))
      done
      (( n )) && { _office_number "$s"; return }
      # Restoring is bounded by the cap, not by what happens to be in the stash:
      # sessions parked one at a time weeks ago should not all come flooding
      # back because you pressed the group toggle.
      while (( $(_office_desk_count "$s") < _OFFICE_MAX_DESKS )); do
        _office_unhide "$s" CLAUDE || break
      done
      _office_number "$s" ;;
    renumber)
      _office_number "$(_office_sessname "$(_office_root "$PWD")")" ;;
    layout|fix|repair)
      _office_relayout "$(_office_sessname "$(_office_root "$PWD")")"; print "layout rebuilt." ;;
    hide|collapse)
      _office_hide "${2:-$(tmux display -p '#{pane_id}')}" ;;
    show|restore|back)
      local s k; s=$(_office_sessname "$(_office_root "$PWD")")
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
      (( $#always )) && print "  run '$OFFICE_ALWAYS_ON_STOP' (stops the always-on stack, Mac can sleep)"
      if [[ $2 != (-y|--yes) ]]; then
        print -n "go home? [y/N] "; read -q _ans 2>/dev/null; print
        [[ $_ans == y ]] || { unset _ans; print "still here."; return }
        unset _ans
      fi
      (( $#always )) && { print -P "%F{green}==> $OFFICE_ALWAYS_ON_STOP%f"; eval "$OFFICE_ALWAYS_ON_STOP" }
      tmux kill-server 2>/dev/null
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
        && print -P "always-on: %F{green}up%f (stop with '$OFFICE_ALWAYS_ON_STOP')" \
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
