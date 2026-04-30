# zsh-wt — git-worktree helpers for zsh / oh-my-zsh
#
#   wt <name...>       create a worktree under <repo>/.claude/worktrees/<slug>,
#                      cd into it, launch claude
#   wtj <pattern>      jump to an existing worktree by substring match (focuses
#                      the existing iTerm2 tab if one is open)
#   wt-prune [-fnr]    remove worktrees whose branch is merged into origin/main
#                      or whose upstream is [gone]

# Create a git worktree with a slugified branch name and open Claude Code in it.
wt() {
  if [[ -z "$1" ]]; then
    echo "Usage: wt <ticket-or-branch-name> [description...]" >&2
    return 1
  fi

  local git_root
  # Use the main worktree's root, not the current worktree's, so `wt` from
  # inside a nested worktree still creates siblings under the main repo.
  git_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
  if [[ -z "$git_root" ]]; then
    echo "Not in a git repository" >&2
    return 1
  fi

  local slug
  slug=$(echo "$*" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')

  local worktree_path="$git_root/.claude/worktrees/$slug"

  if git -C "$git_root" show-ref --verify --quiet "refs/heads/$slug"; then
    echo "Branch '$slug' already exists, reusing..." >&2
    [[ ! -d "$worktree_path" ]] && git -C "$git_root" worktree add "$worktree_path" "$slug"
  else
    mkdir -p "$(dirname "$worktree_path")"
    git -C "$git_root" worktree add -b "$slug" "$worktree_path"
  fi

  local repo
  repo=$(basename "$git_root")
  cd "$worktree_path" || return
  _wt_set_tab "$repo" "$slug"
  claude
  _wt_reset_tab
}

# Set iTerm2 tab title and color. Repo determines hue (so all worktrees of
# the same repo share a color family); slug shifts lightness so each worktree
# is a distinguishable tint.
_wt_set_tab() {
  [[ "$TERM_PROGRAM" != "iTerm.app" ]] && return
  local repo=$1 slug=$2 repo_hex slug_hex hue light rgb r g b
  repo_hex=$(printf '%s' "$repo" | shasum | cut -c1-4)
  slug_hex=$(printf '%s' "$slug" | shasum | cut -c1-2)
  hue=$(( 16#$repo_hex % 360 ))
  # Lightness 55..80 — keeps tints readable and visibly distinct.
  light=$(( 55 + 16#$slug_hex % 26 ))
  rgb=$(awk -v h="$hue" -v s=70 -v l="$light" '
    function h2r(p,q,t) {
      if (t<0) t+=1; if (t>1) t-=1
      if (t<1/6) return p+(q-p)*6*t
      if (t<1/2) return q
      if (t<2/3) return p+(q-p)*(2/3-t)*6
      return p
    }
    BEGIN {
      H=h/360; S=s/100; L=l/100
      q = L<0.5 ? L*(1+S) : L+S-L*S
      p = 2*L-q
      printf "%d %d %d", h2r(p,q,H+1/3)*255, h2r(p,q,H)*255, h2r(p,q,H-1/3)*255
    }')
  read r g b <<<"$rgb"
  printf '\e]1;%s\a' "$repo/$slug"
  printf '\e]6;1;bg;red;brightness;%d\a' "$r"
  printf '\e]6;1;bg;green;brightness;%d\a' "$g"
  printf '\e]6;1;bg;blue;brightness;%d\a' "$b"
}

# Focus an existing iTerm2 tab whose session name matches "$1". Returns 0 if
# focused, 1 otherwise. Matches the title set by _wt_set_tab.
_wt_focus_tab() {
  [[ "$TERM_PROGRAM" != "iTerm.app" ]] && return 1
  local result
  result=$(osascript - "$1" <<'OSA' 2>/dev/null
on run argv
  set targetName to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if name of s is targetName then
            tell s to select
            activate
            return "found"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return "notfound"
end run
OSA
)
  [[ "$result" == "found" ]]
}

_wt_reset_tab() {
  [[ "$TERM_PROGRAM" != "iTerm.app" ]] && return
  printf '\e]6;1;bg;*;default\a'
  printf '\e]1;%s\a' "${PWD##*/}"
}

# Jump to an existing worktree by substring match on branch or path.
# `git worktree list` is one fast git call, so this is instant even with dozens of worktrees.
wtj() {
  if [[ -z "$1" ]]; then
    echo "Usage: wtj <pattern>   (substring match, case-insensitive)" >&2
    return 1
  fi

  local pattern="${(L)1}"
  local matches
  matches=$(git worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { path=substr($0,10) }
    /^branch /   { branch=substr($0,8); sub("refs/heads/","",branch); print path"\t"branch }
  ' | awk -v p="$pattern" 'index(tolower($0), p)')

  if [[ -z "$matches" ]]; then
    echo "No worktree matching '$1'" >&2
    return 1
  fi

  local count=$(echo "$matches" | wc -l | tr -d ' ')
  if [[ "$count" -gt 1 ]]; then
    # Prefer an exact branch match if there is one
    local exact
    exact=$(echo "$matches" | awk -F'\t' -v p="$pattern" 'tolower($2)==p')
    if [[ -n "$exact" ]]; then
      local exact_branch=$(echo "$exact" | cut -f2)
      local main_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
      _wt_focus_tab "$(basename "$main_root")/$exact_branch" && return
      cd "$(echo "$exact" | cut -f1)" || return
      _wt_set_tab "$(basename "$main_root")" "$exact_branch"
      return
    fi
    echo "Multiple worktrees match '$1':" >&2
    echo "$matches" | awk -F'\t' '{ printf "  %s  (%s)\n", $2, $1 }' >&2
    return 1
  fi

  local target=$(echo "$matches" | cut -f1)
  local branch=$(echo "$matches" | cut -f2)
  local main_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
  _wt_focus_tab "$(basename "$main_root")/$branch" && return
  cd "$target" || return
  _wt_set_tab "$(basename "$main_root")" "$branch"
}

_wtj() {
  local -a branches
  branches=("${(@f)$(git worktree list --porcelain 2>/dev/null | awk '/^branch /{sub("refs/heads/","",$2); print $2}')}")
  compadd -a branches
}
# znap wraps compdef and defers it; assign to _comps directly so the
# registration sticks for the current shell.
if (( $+_comps )); then
  _comps[wtj]=_wtj
else
  compdef _wtj wtj 2>/dev/null
fi

# Prune worktrees whose branches are merged into main or whose upstream is gone.
# Skips the main worktree and the current worktree. Use -f to skip confirmation,
# -n for dry-run, -r <ref> to override the merge base (default: origin/main).
wt-prune() {
  local force=0 dry=0 base="origin/main"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      -n|--dry-run) dry=1; shift ;;
      -r|--ref) base="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: wt-prune [-f] [-n] [-r <ref>]"
        echo "  Prunes worktrees whose branch is merged into <ref> (default origin/main)"
        echo "  or whose upstream is [gone]. Skips main and current worktree."
        return 0 ;;
      *) echo "wt-prune: unknown arg: $1" >&2; return 1 ;;
    esac
  done

  local main_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
  [[ -z "$main_root" ]] && { echo "Not in a git repo" >&2; return 1; }
  local cur_root=$(git rev-parse --show-toplevel 2>/dev/null)

  git -C "$main_root" fetch --quiet --prune origin 2>/dev/null

  local -a gone_branches merged_branches
  gone_branches=("${(@f)$(git -C "$main_root" for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2=="[gone]"{print $1}')}")
  merged_branches=("${(@f)$(git -C "$main_root" branch --format='%(refname:short)' --merged "$base" 2>/dev/null)}")

  local -a to_prune
  while IFS=$'\t' read -r path branch; do
    [[ -z "$path" || "$path" == "$main_root" || "$path" == "$cur_root" ]] && continue
    [[ -z "$branch" ]] && continue
    if (( ${gone_branches[(I)$branch]} )) || (( ${merged_branches[(I)$branch]} )); then
      to_prune+=("$path	$branch")
    fi
  done < <(git -C "$main_root" worktree list --porcelain | awk '
    /^worktree /{ p=substr($0,10) }
    /^branch /  { b=substr($0,8); sub("refs/heads/","",b); print p"\t"b; p=""; b="" }
  ')

  if [[ ${#to_prune[@]} -eq 0 ]]; then
    echo "No merged or gone worktrees to prune."
    return 0
  fi

  echo "Will prune ${#to_prune[@]} worktree(s):"
  for entry in "${to_prune[@]}"; do
    printf "  %s  (%s)\n" "${entry%%	*}" "${entry##*	}"
  done

  if [[ $dry -eq 1 ]]; then return 0; fi
  if [[ $force -eq 0 ]]; then
    printf "Proceed? [y/N] "
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; return 1; }
  fi

  for entry in "${to_prune[@]}"; do
    local path="${entry%%	*}" branch="${entry##*	}"
    git -C "$main_root" worktree remove "$path" 2>/dev/null \
      || git -C "$main_root" worktree remove --force "$path"
    git -C "$main_root" branch -D "$branch" 2>/dev/null
  done
  git -C "$main_root" worktree prune
  echo "Done."
}
