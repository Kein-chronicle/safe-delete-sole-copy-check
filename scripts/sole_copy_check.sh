#!/usr/bin/env bash
# sole_copy_check: is this git project safe to delete because every byte also exists on its remote?
# usage: sole_copy_check.sh [--allow-ignored] <dir>
#   exit 0 = safe | 1 = SOLE COPY: do not delete | 2 = cannot tell (never treat as safe)
# "safe" means: the folder is a repo root, origin is reachable and agrees with the local remote-tracking refs, no commit (on any branch, tag,
# stash or detached HEAD) is missing from the remote, no tag is missing, no untracked files, and no ignored files unless --allow-ignored.
# Not covered: files outside git, LFS storage (reported as CANNOT TELL), and the remote's own durability.
set -u
allow_ignored=0
[ "${1:-}" = "--allow-ignored" ] && { allow_ignored=1; shift; }
d="${1:-}"; [ -d "$d" ] || { echo "no such dir"; exit 2; }
git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || { echo "SOLE COPY: not a git repository"; exit 1; }
top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)"; here="$(cd "$d" && pwd -P)"; top="$(cd "$top" && pwd -P)"
[ "$top" = "$here" ] || { echo "SOLE COPY: not the root of a git repository (it sits inside another repo, whose state says nothing about this folder)"; exit 1; }
sole=0; unsure=0
say_sole() { echo "SOLE COPY: $1"; sole=1; }
say_unsure() { echo "CANNOT TELL: $1"; unsure=1; }
git -C "$d" remote get-url origin >/dev/null 2>&1 || { say_sole "no 'origin' remote"; exit 1; }

# A reachable local origin is not necessarily an independent backup.
origin_url="$(git -C "$d" remote get-url origin)" || exit 2
python3 - "$here" "$origin_url" <<'PY_REMOTE'
import os, pathlib, subprocess, sys, urllib.parse
root = pathlib.Path(sys.argv[1]).resolve(); url = sys.argv[2]
if url.startswith('file:'):
    parsed = urllib.parse.urlsplit(url)
    if parsed.netloc not in ('', 'localhost'): sys.exit(2)
    local = urllib.parse.unquote(parsed.path)
elif '://' in url or (':' in url and not url.startswith(('/', './', '../'))):
    sys.exit(0)  # network origin; durability remains outside this check
else: local = url
remote = pathlib.Path(local)
if not remote.is_absolute(): remote = root / remote
remote = remote.resolve()
if remote == root or root in remote.parents: sys.exit(2)
# Shared object stores may still depend on the tree about to be removed.
r = subprocess.run(['git', '-C', str(remote), 'rev-parse', '--git-path', 'objects'], capture_output=True, text=True)
if r.returncode == 0:
    objects = pathlib.Path(r.stdout.strip())
    if not objects.is_absolute(): objects = remote / objects
    objects = objects.resolve()
    if objects == root or root in objects.parents: sys.exit(2)
r = subprocess.run(['git', '-C', str(remote), 'rev-parse', '--git-path', 'objects/info/alternates'], capture_output=True, text=True)
if r.returncode == 0:
    alternate = pathlib.Path(r.stdout.strip())
    if not alternate.is_absolute(): alternate = remote / alternate
    if alternate.exists(): sys.exit(2)
PY_REMOTE
[ $? = 0 ] || { say_unsure "local origin is inside this tree or its independent object storage cannot be confirmed"; exit 2; }

# 1. talk to the remote: the cached remote-tracking refs are only evidence if they match what the remote says now
live="$(git -C "$d" ls-remote --heads origin 2>/dev/null)" || live=""
if [ -z "$live" ]; then say_unsure "origin is unreachable or has no branches (cannot confirm anything is stored there)"
else
  while read -r ref sha; do
    br="${ref#refs/remotes/origin/}"; [ "$br" = "HEAD" ] && continue          # refs/remotes/origin/HEAD is a pointer, not a branch
    liveSha="$(echo "$live" | awk -v r="refs/heads/$br" '$2==r {print $1}')"
    if [ -z "$liveSha" ]; then say_unsure "remote branch '$br' no longer exists on origin (local cache is stale: run git fetch)"
    elif [ "$liveSha" != "$sha" ]; then say_unsure "remote branch '$br' moved on origin (local cache is stale: run git fetch)"; fi
  done < <(git -C "$d" for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin)
fi

# 2. every commit reachable from any local ref (branches, tags, stash, detached HEAD) must be on a remote
n="$(git -C "$d" rev-list --all --not --remotes=origin 2>/dev/null; echo "rc=$?")"; rc_n="${n##*rc=}"; n="$(echo "$n" | grep -vc '^rc=' )"
[ "$rc_n" != "0" ] && say_unsure "git could not walk the history (corrupt refs or objects): cannot tell what exists only here"
[ "$rc_n" = "0" ] && [ "$n" != "0" ] && say_sole "$n commit(s) exist on no remote (unpushed branch, detached HEAD, stash or tag-only commits)"
r="$(git -C "$d" rev-list --reflog --not --remotes=origin 2>/dev/null | wc -l | tr -d ' ')"
[ "$r" != "0" ] && [ "$n" = "0" ] && say_unsure "$r commit(s) are reachable only from the reflog (abandoned work, a detached-HEAD session or old amended commits): inspect with git reflog before deleting"
if git -C "$d" rev-parse --verify -q HEAD >/dev/null 2>&1 && ! git -C "$d" symbolic-ref -q HEAD >/dev/null 2>&1; then say_sole "HEAD is detached"; fi
[ -n "$(git -C "$d" stash list 2>/dev/null)" ] && say_sole "stash entries exist"

# 3. tags
if [ -n "$live" ]; then
  rt="$(git -C "$d" ls-remote --tags origin 2>/dev/null)"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    local_sha="$(git -C "$d" rev-parse "refs/tags/$t^{}" 2>/dev/null)"
    echo "$rt" | awk -v r="refs/tags/$t^{}" -v r2="refs/tags/$t" '$2==r || $2==r2 {print $1}' | grep -qxF "$local_sha" || say_sole "tag '$t' is not on origin (missing, or pointing at a different commit)"
  done < <(git -C "$d" tag)
fi

# 4. working tree: untracked always; ignored unless the caller accepts them as regenerable
st="$(git -C "$d" -c status.showUntrackedFiles=all status --porcelain --ignored 2>/dev/null)"; rc_st=$?
if [ $rc_st != 0 ]; then say_unsure "git status failed (corrupt index or repository): cannot see uncommitted work"
else
  [ -n "$(echo "$st" | grep -v '^!!')" ] && say_sole "uncommitted or untracked files (untracked files in a remote-backed repo are the easiest to miss)"
fi
ign="$(echo "$st" | grep -c '^!!' || true)"
hidden="$(git -C "$d" ls-files -v 2>/dev/null | grep -c '^[a-zS] ' || true)"
[ "$hidden" != "0" ] && say_sole "$hidden file(s) are marked assume-unchanged or skip-worktree: local edits to them are invisible to git status"
if git -C "$d" ls-files 2>/dev/null | head -2000 | xargs -I{} git -C "$d" check-attr filter -- "{}" 2>/dev/null | grep -q "filter: lfs"; then say_unsure "Git LFS files present: their contents live in LFS storage, which this check cannot see"; fi
if [ "$ign" != "0" ] && [ $allow_ignored = 0 ]; then say_sole "$ign ignored path(s) (.env, local config, build output...). Not in git, not on the remote. Re-run with --allow-ignored once you have checked they are regenerable"; fi

# 5. things this check cannot see into
[ -n "$(git -C "$d" submodule status 2>/dev/null)" ] && say_unsure "submodules present: check each one separately"
[ "$(git -C "$d" worktree list 2>/dev/null | wc -l | tr -d ' ')" -gt 1 ] && say_unsure "other worktrees exist: check each one separately"

[ $sole = 1 ] && exit 1
[ $unsure = 1 ] && exit 2
echo "safe: origin reachable and in sync, no unpushed commit/tag/stash, no untracked$([ $allow_ignored = 1 ] && echo ' (ignored files were allowed)' || echo ' or ignored') files"
exit 0
