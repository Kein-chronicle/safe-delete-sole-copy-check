---
name: safe-archive-rules
description: Rules and checkers for deleting or archiving project folders without losing the only copy of anything - a sole-copy check for git projects (ignored files, unpushed commits and tags, stale remotes), a copy verifier by sha256, and measurement traps (du vs APFS reclaimed space, df on macOS, shell `set -e` + grep). Use before moving or deleting project folders, when a disk is nearly full, or when writing cleanup scripts.
---

# safe-archive-rules

Freeing disk space is where data gets lost. These rules and two scripts answer the two questions that matter before anything is deleted:
**does every byte here exist somewhere else?** and **does the copy really equal the original?**

## Order of operations

1. **Survey first.** Make `du` totals explain the `df` used-space gap; do not proceed with an unexplained gap.
2. **Delete what is regenerable before moving anything** (DerivedData, node_modules, build output, package caches). Starting a big copy on an almost-full disk stalls half-way.
3. Sort what is left by one criterion: *does it exist remotely?* Remote-backed: delete the local copy and note the remote address. Not remote-backed: archive it, verify, then delete. Running services and active projects stay.
4. **Verify, then delete.** Never the other way round. Do a restore test for anything irreplaceable.

## "Sole copy" test for git projects: `scripts/sole_copy_check.sh [--allow-ignored] DIR`

Exit `0` safe, `1` sole copy, `2` cannot tell (never treat 2 as safe). It reports SOLE COPY for: not a repo root, no `origin`, any commit on no remote (any branch, tag,
stash), a detached HEAD, a tag that is not on origin, untracked files, and **ignored files** (`.env`, local config) unless you pass `--allow-ignored` after checking they are regenerable.
It reports CANNOT TELL when origin is unreachable, when the local remote-tracking refs disagree with what origin says now, when work exists only in the reflog,
and when submodules or extra worktrees exist.
It does not see files outside git, LFS objects, or the remote's own durability. The most commonly missed case: **untracked files inside a repo that does have a remote.**

## Copy verification: `scripts/verify_copy.sh SRC DST`

Compares the sha256 of every regular file, the target of every symlink and every empty directory (not permissions, timestamps or extended attributes).
An unreadable file is exit `2`, never "identical"; an empty source proves nothing.

## Guard rails

- Keep one index of what was archived and where; generated overviews are never hand-edited.
- Mechanical drives are slow with many small files: tar them first, then verify the tar.
- Do not edit a shell script while it is running (the shell reads by byte offset).
- Dry-run by default; destructive switches must be explicit.
- Never put "erase all" for a simulator or similar blanket resets in a cleanup bucket: it deletes the devices you use.

## Measurement traps

| Trap | Fact |
|---|---|
| `du` equals reclaimed space | No. APFS block sharing and clones mean deleting a large folder can reclaim much less. Delete one, re-measure with `df`, then continue |
| `df /` on macOS | Reports the sealed system volume. Use `df /System/Volumes/Data` |
| Counting only /Applications and /Library | Misses large hidden asset stores and swap under the Data volume |
| `set -e` with `x=$(grep ...)` | grep exits 1 on "no match" and kills the script with exit 0 and no output. Add `|| true` |
| `"$n<non-ASCII suffix>"` in bash | The suffix is read as part of the variable name; write `"${n}..."` |

```bash
bash tests/run.sh      # builds throwaway git repos for every sole-copy case, and corrupts copies to see verify fail
```

The copy verifier requires Python 3.10+, distinct non-overlapping directory trees, and ordinary files/directories/symlinks. Sockets, pipes and devices are unmeasured (exit 2). Checks are point-in-time; stop writers and do a restore test before any separately authorized deletion.

Local origin paths (including file URLs and symlink aliases) inside the candidate tree are unmeasured, not independent backups. Local origins with Git object alternates also require independent backup verification.
