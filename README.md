# safe-delete-sole-copy-check

**Before you delete a project folder: is any of it the only copy? Checks the live remote, unpushed commits and tags, untracked and ignored files, and verifies copies by hash.**

[![test](https://github.com/Kein-chronicle/safe-delete-sole-copy-check/actions/workflows/test.yml/badge.svg)](https://github.com/Kein-chronicle/safe-delete-sole-copy-check/actions/workflows/test.yml) ![license](https://img.shields.io/badge/license-MIT-blue.svg) ![dependencies](https://img.shields.io/badge/dependencies-none-brightgreen.svg)

## Why

Freeing disk space is where data gets lost. `sole_copy_check.sh` answers "does every byte here exist somewhere else?" and fails closed: anything it cannot confirm is not "safe". `verify_copy.sh` proves a copy matches before the original goes.

## Install

**As a Claude Code skill** (Claude uses it when the task matches the skill description):

```sh
git clone https://github.com/Kein-chronicle/safe-delete-sole-copy-check.git ~/.claude/skills/safe-archive-rules
```

For a single project, clone into `<project>/.claude/skills/safe-archive-rules` instead, then start a new Claude Code session.

**As plain scripts:**

```sh
git clone https://github.com/Kein-chronicle/safe-delete-sole-copy-check.git
cd safe-delete-sole-copy-check
```

**Requires:** Python 3.10+ and bash.

## Quick start

Check a repo, then a copy:

```console
$ bash examples/demo.sh
# Before deleting a folder: is anything here the only copy?
$ scripts/sole_copy_check.sh .demo-tmp/proj
safe: origin reachable and in sync, no unpushed commit/tag/stash, no untracked or ignored files
[exit 0]

# An untracked file exists nowhere else:
$ scripts/sole_copy_check.sh .demo-tmp/proj
SOLE COPY: uncommitted or untracked files (untracked files in a remote-backed repo are the easiest to miss)
[exit 1]

# A folder that is not a git repo at all:
$ scripts/sole_copy_check.sh .demo-tmp/plain
SOLE COPY: not a git repository
[exit 1]

# Before deleting the original of a copy: do the two match byte for byte?
$ scripts/verify_copy.sh .demo-tmp/plain .demo-tmp/plain_copy
identical: 1 entries; sha256 equal
[exit 0]

$ scripts/verify_copy.sh .demo-tmp/plain .demo-tmp/plain_copy
DIFFER: file contents, links or directory entries differ
[exit 1]
```

The output above is real: it is produced by the files in `examples/`.

## Use it on your own files

```sh
scripts/sole_copy_check.sh ~/Projects/old-project   # 0 safe, 1 sole copy, 2 cannot tell
scripts/verify_copy.sh ~/Projects/old-project /Volumes/Backup/old-project
```

Sample inputs for every file format are in `examples/` and `tests/`; the details are in [SKILL.md](SKILL.md).

## What it checks

- `sole_copy_check.sh [--allow-ignored] DIR`: exit `0` safe, `1` sole copy, `2` cannot tell (never treat as safe).
- SOLE COPY: not a repo root, no `origin`, commits on no remote (any branch, tag, stash), detached HEAD, tags not on origin, untracked files, and ignored files such as `.env` unless you pass `--allow-ignored`.
- CANNOT TELL: origin unreachable, local remote-tracking refs disagree with the live remote, work reachable only from the reflog, submodules or extra worktrees.
- `verify_copy.sh SRC DST` compares sha256 of every file, every symlink target and every empty directory. An unreadable file is exit `2`; an empty source proves nothing.

## Limits

- Git-aware only: files outside git, LFS objects and the remote's own durability are not checked. Use `verify_copy.sh` against a second copy for those.
- Does not compare permissions, timestamps or extended attributes.
- The check contacts `origin` (`git ls-remote`); offline it answers 2.

## Related projects

These solve neighbouring problems; use them when they fit better.

- **rsync --checksum, git bundle**: copy and bundle tools; this decides whether it is safe to delete

## More from the same collection

Small, tested tools that grew out of running AI agents and game/app pipelines for months:

- [**exif-orientation-guard**](https://github.com/Kein-chronicle/exif-orientation-guard): Find and fix images whose stored size differs from their displayed size because of an EXIF orientation tag.
- [**macos-tcc-automation-permissions**](https://github.com/Kein-chronicle/macos-tcc-automation-permissions): Make unattended macOS automation survive permission resets: AppleScript -1743/-1728, launchd jobs, screen recording, and real vs synthetic clicks.
- [**ios-simulator-ui-test-hygiene**](https://github.com/Kein-chronicle/ios-simulator-ui-test-hygiene): Keep iOS simulator UI tests and crash-fuzz runs from dying on a laptop: the 16 GB memory wall and the crash-report dialog that never goes away.

## Development

```sh
bash tests/run.sh
```

The tests include inputs that are supposed to be rejected, so a green run also shows the checks can fail. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).

If this saved you a debugging session, a star helps other people find it. Bug reports and failing test cases are even better.

<sub>Keywords: git, backup, cleanup, safety, shell, devops, disk-space, claude-skills</sub>
