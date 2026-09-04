#!/usr/bin/env python3
"""aify etkilesimli arayuzunu sahte bir terminalde (pty) surer.

Kullanim:  ui-drive.py <aify-yolu> <aify-home> <tus...>
Tuslar:    ham bayt dizileri (\\x1b[B gibi) ya da SLEEP<saniye>
Cikti:     terminale yazilan her sey (test icinde grep'lenir)
"""
import os, pty, select, sys, time

def main():
    aify, home, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
    env = dict(os.environ,
               AIFY_HOME=home, TERM="xterm-256color", LANG="en_US.UTF-8",
               COLUMNS="72", LINES="40")
    env.pop("NO_COLOR", None)
    pid, fd = pty.fork()
    if pid == 0:
        os.execve("/bin/bash", ["bash", aify], env)

    out = bytearray()

    def drain(timeout=0.25):
        while select.select([fd], [], [], timeout)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            out.extend(chunk)

    time.sleep(1.0)
    drain()
    for key in keys:
        if key.startswith("SLEEP"):
            time.sleep(float(key[5:]))
            drain()
            continue
        os.write(fd, key.encode().decode("unicode_escape").encode())
        time.sleep(0.45)
        drain()
    time.sleep(0.4)
    drain(0.4)
    try:
        os.close(fd)
    except OSError:
        pass
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass
    sys.stdout.write(out.decode("utf-8", "replace"))

if __name__ == "__main__":
    main()
