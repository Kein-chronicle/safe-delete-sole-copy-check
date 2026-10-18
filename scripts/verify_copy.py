#!/usr/bin/env python3
"""Compare distinct directory trees without ambiguous newline-based manifests.
Exit 0 equal, 1 different, 2 unmeasured. No deletion is performed.
"""
import hashlib
import os
from pathlib import Path
import stat
import sys


def manifest(root):
    entries = {}
    def unreadable(exc): raise exc
    for base, dirs, files in os.walk(root, followlinks=False, onerror=unreadable):
        for name in dirs + files:
            if name == '.DS_Store': continue
            path = Path(base)/name
            mode = path.lstat().st_mode
            relative = str(path.relative_to(root))
            if stat.S_ISLNK(mode):
                entries[relative] = ('link', os.readlink(path))
            elif stat.S_ISDIR(mode):
                entries[relative] = ('directory',)
            elif stat.S_ISREG(mode):
                digest = hashlib.sha256()
                with path.open('rb') as f:
                    for block in iter(lambda: f.read(1024*1024), b''): digest.update(block)
                entries[relative] = ('file', digest.hexdigest())
            else:
                raise ValueError('unsupported special file')
    return entries


def main():
    if len(sys.argv) != 3: print('usage: verify_copy.sh SRC DST'); return 2
    try:
        src, dst = [Path(p).resolve(strict=True) for p in sys.argv[1:]]
        if not src.is_dir() or not dst.is_dir() or os.path.samefile(src, dst):
            raise ValueError('two distinct directories required')
        if src in dst.parents or dst in src.parents: raise ValueError('overlapping trees are not independent copies')
        a, b = manifest(src), manifest(dst)
        if not a: raise ValueError('empty source proves nothing')
        if a == b: print(f'identical: {len(a)} entries; sha256 equal'); return 0
        print('DIFFER: file contents, links or directory entries differ'); return 1
    except (OSError, ValueError):
        print('UNMEASURED: unreadable, empty, overlapping or unsupported tree'); return 2

if __name__ == '__main__': sys.exit(main())
