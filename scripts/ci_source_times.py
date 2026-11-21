"""Gives every tracked file a modification time made from its content, so a build tree restored from the cache
skips the files that did not change. A checkout stamps every file with the time it wrote it, and Swift rebuilds a
file whose time differs from the one it built, so without this a restored tree rebuilds everything. A changed file
gets another time and builds again; one with the same content gets the time the cached build saw."""

import os
import subprocess

# Times between 2001 and 2010, nanoseconds included, so two contents of one file share a time about once in 2^58.
BASE = 1_000_000_000


def content_time(blob):
    """The time, in nanoseconds since 1970, for a blob's object id."""
    return (BASE + int(blob[:7], 16)) * 1_000_000_000 + int(blob[7:15], 16) % 1_000_000_000


def tracked(listing):
    """Each path and blob in the output of `git ls-files -s -z`."""
    for entry in listing.split(b"\0"):
        if entry:
            meta, path = entry.split(b"\t", 1)
            yield path, meta.split()[1].decode()


def stamp(listing):
    """Stamps each listed file that exists with its content's time and returns how many it stamped."""
    count = 0
    for path, blob in tracked(listing):
        if os.path.lexists(path):
            moment = content_time(blob)
            os.utime(path, ns=(moment, moment), follow_symlinks=False)
            count += 1
    return count


if __name__ == "__main__":
    listing = subprocess.run(["git", "ls-files", "-s", "-z"], capture_output=True, check=True).stdout
    print(f"Stamped {stamp(listing)} files with their content's time.")
