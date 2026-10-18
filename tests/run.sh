#!/usr/bin/env bash
set -u; here="$(cd "$(dirname "$0")" && pwd)"; s="$here/../scripts"; t="$(mktemp -d)"; bad=0
G="git -c user.email=t@example.com -c user.name=t"
exp() { name="$1"; want="$2"; shift 2; out="$("$@" 2>&1)"; got=$?; [ "$got" = "$want" ] && echo "ok   $name" || { echo "FAIL $name (want $want got $got)"; echo "$out" | sed 's/^/     /'; bad=1; }; }
# remote-backed clean repo
git init -q --bare "$t/remote.git"; git clone -q "$t/remote.git" "$t/proj" 2>/dev/null
( cd "$t/proj" && echo a > a.txt && git add . && $G commit -qm init && git push -q -u origin HEAD 2>/dev/null )
exp "clean remote-backed repo is safe" 0 "$s/sole_copy_check.sh" "$t/proj"
echo b > "$t/proj/untracked.txt"
exp "untracked file => sole copy" 1 "$s/sole_copy_check.sh" "$t/proj"
rm "$t/proj/untracked.txt"
( cd "$t/proj" && echo c >> a.txt && $G commit -qam second )
exp "unpushed commit => sole copy" 1 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && git push -q 2>/dev/null; echo d >> a.txt && git stash -q )
exp "stash => sole copy" 1 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && git stash drop -q && git checkout -q -b local-only )
exp "a local branch with no unique commits holds no data" 0 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && echo z > z.txt && git add z.txt && $G commit -qm local-only-work )
exp "branch without upstream carrying a commit => sole copy" 1 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && git reset -q --hard HEAD~1 && git reflog expire --expire=now --all && git gc -q --prune=now 2>/dev/null )
mkdir "$t/plain"; echo x > "$t/plain/f"
exp "non-git folder => sole copy" 1 "$s/sole_copy_check.sh" "$t/plain"
mkdir "$t/proj/nested"; echo x > "$t/proj/nested/f"
exp "folder nested inside another repo is not itself a repo" 1 "$s/sole_copy_check.sh" "$t/proj/nested"
rm -rf "$t/proj/nested"
exp "missing dir => cannot tell" 2 "$s/sole_copy_check.sh" "$t/nope"
cp -R "$t/plain" "$t/plain_copy"
exp "identical copy verifies" 0 "$s/verify_copy.sh" "$t/plain" "$t/plain_copy"
echo y >> "$t/plain_copy/f"
exp "corrupted copy is caught" 1 "$s/verify_copy.sh" "$t/plain" "$t/plain_copy"
mkdir "$t/empty"; exp "empty source proves nothing" 2 "$s/verify_copy.sh" "$t/empty" "$t/empty"
# --- adversarial cases found in review: every one of these used to print "safe"
exp "baseline is safe again" 0 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && git checkout -q -b tmp && git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null; git branch -D tmp -q )
echo secret > "$t/proj/.env"; ( cd "$t/proj" && echo ".env" > .gitignore && git add .gitignore && $G commit -qm ignore && git push -q 2>/dev/null )
exp "ignored file (.env) is a sole copy" 1 "$s/sole_copy_check.sh" "$t/proj"
exp "--allow-ignored accepts it when you decided" 0 "$s/sole_copy_check.sh" --allow-ignored "$t/proj"
rm "$t/proj/.env"
( cd "$t/proj" && git checkout -q --detach && echo x > d.txt && git add d.txt && $G commit -qm detached && git checkout -q - )
exp "work left only in the reflog (abandoned detached HEAD) cannot be called safe" 2 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && git checkout -q --detach )
exp "currently detached HEAD is a sole copy" 1 "$s/sole_copy_check.sh" "$t/proj"
( cd "$t/proj" && git checkout -q - )
( cd "$t/proj" && git reflog expire --expire=now --all >/dev/null 2>&1 )
git clone -q "$t/remote.git" "$t/proj2" 2>/dev/null; ( cd "$t/proj2" && $G tag v1 && true )
exp "unpushed tag is a sole copy" 1 "$s/sole_copy_check.sh" "$t/proj2"
git clone -q "$t/remote.git" "$t/proj3" 2>/dev/null; ( cd "$t/proj3" && echo n > n.txt && git add n.txt && $G commit -qm n && git push -q 2>/dev/null )
exp "stale cache (remote moved on) cannot be trusted" 2 "$s/sole_copy_check.sh" --allow-ignored "$t/proj"
git clone -q "$t/remote.git" "$t/proj4" 2>/dev/null; mv "$t/remote.git" "$t/remote.gone"
exp "deleted/unreachable remote is 'cannot tell', not safe" 2 "$s/sole_copy_check.sh" "$t/proj4"
mv "$t/remote.gone" "$t/remote.git"
# verify_copy: unreadable file, symlink, empty dir
mkdir "$t/v1" "$t/v2"; echo a > "$t/v1/f"; echo a > "$t/v2/f"; echo b > "$t/v1/locked"; echo b > "$t/v2/locked"
chmod 000 "$t/v1/locked" "$t/v2/locked"
exp "unreadable file on both sides is exit 2, not 'identical'" 2 "$s/verify_copy.sh" "$t/v1" "$t/v2"
chmod 644 "$t/v1/locked" "$t/v2/locked"
ln -s f "$t/v1/ln"; ln -s g "$t/v2/ln"
exp "different symlink targets are caught" 1 "$s/verify_copy.sh" "$t/v1" "$t/v2"
rm "$t/v1/ln" "$t/v2/ln"; mkdir "$t/v1/emptydir"
exp "an empty directory missing from the copy is caught" 1 "$s/verify_copy.sh" "$t/v1" "$t/v2"
# --- regression cases from the second review round
git init -q --bare "$t/r2.git"; git clone -q "$t/r2.git" "$t/seed" 2>/dev/null
( cd "$t/seed" && echo a > a.txt && git add . && $G commit -qm init && git push -q -u origin HEAD 2>/dev/null )
fresh() { rm -rf "$t/$1"; git clone -q "$t/r2.git" "$t/$1" 2>/dev/null; }
fresh c1; exp "a normal clone of a populated remote is SAFE (origin/HEAD is not a vanished branch)" 0 "$s/sole_copy_check.sh" "$t/c1"
fresh c2; echo z > "$t/c2/untracked.txt"; echo garbage > "$t/c2/.git/index"
exp "a corrupt index cannot be read as 'clean'" 2 "$s/sole_copy_check.sh" "$t/c2"
fresh c3; echo z > "$t/c3/untracked.txt"; ( cd "$t/c3" && git config status.showUntrackedFiles no )
exp "status.showUntrackedFiles=no does not hide untracked files" 1 "$s/sole_copy_check.sh" "$t/c3"
fresh c4; echo xxxx > "$t/c4/.git/refs/heads/broken"
exp "a broken ref cannot be read as 'nothing unpushed'" 2 "$s/sole_copy_check.sh" "$t/c4"
fresh c5; ( cd "$t/c5" && echo w > w.txt && git add w.txt && $G commit -qm local-only && git remote add backup "$t/r2.git" && git update-ref refs/remotes/backup/main HEAD && git reset -q --hard HEAD~1 && git branch -f keep refs/remotes/backup/main )
exp "a commit visible only through another remote's cached ref is a sole copy" 1 "$s/sole_copy_check.sh" "$t/c5"
fresh c6; ( cd "$t/c6" && echo 1 >> a.txt && git update-index --skip-worktree a.txt )
exp "an edit hidden by skip-worktree is a sole copy" 1 "$s/sole_copy_check.sh" "$t/c6"
fresh c7; ( cd "$t/c7" && $G tag v1.0 && cd "$t/seed" && $G tag v1x0 && git push -q origin v1x0 2>/dev/null )
( cd "$t/c7" && git fetch -q origin 2>/dev/null; git tag -d v1x0 >/dev/null 2>&1 )
exp "tag v1.0 is not 'on origin' just because v1x0 is (the name is not a regex)" 1 "$s/sole_copy_check.sh" "$t/c7"
fresh c8; ( cd "$t/c8" && echo "*.bin filter=lfs diff=lfs merge=lfs" > .gitattributes && echo x > f.bin && git add . && $G commit -qm lfs && git push -q 2>/dev/null )
exp "Git LFS content cannot be vouched for (cannot tell)" 2 "$s/sole_copy_check.sh" "$t/c8"
fresh self_origin
( cd "$t/self_origin" && git remote set-url origin "$t/self_origin" && git fetch -q origin )
exp "self origin is not an independent copy" 2 "$s/sole_copy_check.sh" "$t/self_origin"
( cd "$t/self_origin" && git remote set-url origin "file://$t/self_origin" )
exp "file URL self origin cannot pass" 2 "$s/sole_copy_check.sh" "$t/self_origin"
ln -s "$t/self_origin" "$t/origin_alias"
( cd "$t/self_origin" && git remote set-url origin "$t/origin_alias" )
exp "symlink self origin cannot pass" 2 "$s/sole_copy_check.sh" "$t/self_origin"
rm -rf "$t"; python3 "$here/test_release_regressions.py" || bad=1
exit $bad
