#!/usr/bin/env bash
cd "$(dirname "$0")/.."
run() { printf '$ %s\n' "$*"; "$@"; printf '[exit %s]\n\n' "$?"; }
tmp=.demo-tmp; rm -rf "$tmp"; mkdir "$tmp"; trap 'rm -rf "$tmp"' EXIT
G="git -c user.email=demo@example.com -c user.name=demo"
git init -q --bare "$tmp/remote.git"; git clone -q "$tmp/remote.git" "$tmp/proj" 2>/dev/null
( cd "$tmp/proj" && echo a > a.txt && git add . && $G commit -qm init && git push -q -u origin HEAD 2>/dev/null )
echo "# Before deleting a folder: is anything here the only copy?"
run scripts/sole_copy_check.sh "$tmp/proj"
echo b > "$tmp/proj/notes.txt"
echo "# An untracked file exists nowhere else:"
run scripts/sole_copy_check.sh "$tmp/proj"
mkdir "$tmp/plain"; echo x > "$tmp/plain/file"
echo "# A folder that is not a git repo at all:"
run scripts/sole_copy_check.sh "$tmp/plain"
echo "# Before deleting the original of a copy: do the two match byte for byte?"
cp -R "$tmp/plain" "$tmp/plain_copy"
run scripts/verify_copy.sh "$tmp/plain" "$tmp/plain_copy"
echo y > "$tmp/plain_copy/file"
run scripts/verify_copy.sh "$tmp/plain" "$tmp/plain_copy"
