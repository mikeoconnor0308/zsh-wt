# zsh-wt

Git-worktree helpers for zsh. Designed around a workflow of one worktree per
in-flight branch, parked under `<repo>/.claude/worktrees/<slug>`, with iTerm2
tab colors keyed to the repo.

## Commands

- `wt <name...>` — slugify the args, create a worktree at
  `<repo>/.claude/worktrees/<slug>`, `cd` into it, and launch `claude`. If a
  branch with that slug already exists, it's reused.
- `wtj <pattern>` — substring-match an existing worktree's branch or path and
  jump to it. If an iTerm2 tab is already open for that worktree, focuses it
  instead of `cd`-ing in the current shell. Tab-completes branch names.
- `wt-prune [-f] [-n] [-r <ref>]` — fetch, then remove worktrees whose branch
  is merged into `<ref>` (default `origin/main`) or whose upstream is `[gone]`.
  Skips the main worktree and the current worktree.
  - `-n` dry-run, `-f` skip the y/N prompt, `-r` override the merge base.

iTerm2 tab tinting is opt-in by virtue of `TERM_PROGRAM=iTerm.app`; on other
terminals the color/title escapes are no-ops.

## Install

### oh-my-zsh

```sh
git clone https://github.com/mikeoconnor0308/zsh-wt.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/wt
```

Then add `wt` to the `plugins=(...)` array in `~/.zshrc` and `exec zsh`.

### Plain zsh

```sh
git clone https://github.com/mikeoconnor0308/zsh-wt.git ~/.zsh/zsh-wt
echo 'source ~/.zsh/zsh-wt/wt.plugin.zsh' >> ~/.zshrc
```
