# Python 3.6.15 for SCO OpenServer 5

A working build of [Python 3.6.15](https://www.python.org/) (Sept 2021,
final 3.6 release) for **SCO OpenServer 5.0.7**, including TLS via
statically-linked OpenSSL 1.0.2q.

```
$ python3 --version
Python 3.6.15

$ python3 -c 'import ssl; print(ssl.OPENSSL_VERSION)'
OpenSSL 1.0.2q  20 Nov 2018

$ python3 -c 'name="SCO"; print(f"hello, {name}!")'
hello, SCO!
```

Just want to run Python 3.6 on your SCO box? Skip to **[Install](#install)**.

## Why 3.6 specifically?

This is the most modern Python that's tractable on SCO. Newer versions hit
hard walls:

- **Python 3.7+** — PEP 539 rewrote thread-local storage to use C11
  `_Thread_local`, used pervasively across the interpreter. GCC 3.4.6
  (the newest available C99 compiler for SCO) doesn't emit C11 TLS;
  bumping the toolchain is a separate, multi-week project.
- **Python 3.8+** — also depends on C11 features.

Python 3.5 and 3.6 needed POSIX.1-2001 real-time clocks (`clock_gettime`,
`clock_getres`, `clockid_t`) which SCO doesn't provide either, but those
are surmountable via a small shim — included here. So 3.6 lands.

What you get vs Python 3.4:

- **f-strings** (PEP 498) — `f"hello, {name}!"` instead of
  `"hello, {}!".format(name)`
- **Variable annotations** (PEP 526) — `count: int = 0`
- **Underscores in numeric literals** — `1_000_000`
- **Async/await keywords** (3.5+) — syntax-only without threading
- **Dict ordering as a language guarantee** — `dict` preserves insertion order
- New stdlib: `secrets`, `statistics` improvements, `pathlib` improvements
  (`os.fspath`, `Path.read_text`, etc.)
- `typing` module is real and usable

What you don't get vs newer Python 3:

- No walrus `:=` (PEP 572, 3.8+)
- No `match`/`case` (3.10+)
- No structural type hints (3.9+ generics)

## Install

> **Fresh SCO box?** Install [curl with TLS](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
> first — that's the only file that needs to be transferred via `scp`.
> After that, every release on tachytelic/* (including this one) fetches
> over HTTPS from GitHub.

The release tarball is ~35 MB compressed (~117 MB unpacked). Fetch and
extract directly on the SCO box:

```sh
# On the SCO box (assumes curl-with-TLS is on PATH — see curl-sco):
curl -LO https://github.com/tachytelic/Python-3.6.15-for-SCO-OpenServer-5/releases/download/v1.0.1/python-3.6.15-sco.tar.gz
gtar xzf python-3.6.15-sco.tar.gz
# or with stock tools: gunzip -c python-3.6.15-sco.tar.gz | /usr/bin/tar xf -
mv install /usr/local/python-3.6.15
ln -s /usr/local/python-3.6.15/bin/python3 /usr/local/bin/python3
python3 --version       # → Python 3.6.15
```

OpenSSL 1.0.2q is statically linked into `_ssl.so`, so there's no
runtime OpenSSL dependency.

### HTTPS — needs a CA bundle

Out of the box, `urllib.request.urlopen("https://...")` will fail with
`CERTIFICATE_VERIFY_FAILED` because SCO has no system CA bundle. Two
ways to fix:

1. **Install [curl-sco](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
   too** — it ships Mozilla's CA bundle at `/usr/local/etc/ssl/cert.pem`,
   and the symlink Python's OpenSSL expects is just:

   ```sh
   mkdir -p /usr/local/ssl/certs
   ln -s /usr/local/etc/ssl/cert.pem /usr/local/ssl/cert.pem
   ```

2. **Drop a Mozilla CA bundle at `/usr/local/ssl/cert.pem` yourself** —
   Mozilla publishes one at https://curl.se/ca/cacert.pem.

Either way Python's `ssl` module then finds it via OpenSSL's
compile-time default. After the symlink, `urllib.request.urlopen("https://www.python.org/")`
returns 200.

### Non-ASCII output

SCO's locale is unconfigured — `nl_langinfo(CODESET)` returns empty,
which would make CPython refuse to start. The patches fall back to
`"ascii"` in that case, which means `print("café")` will raise
`UnicodeEncodeError` by default. To print non-ASCII, set:

```sh
PYTHONIOENCODING=utf-8 python3
```

`utf-8` strings round-trip fine internally; this is purely a stdout
encoding choice.

## What's included

All smoke tests pass (40/40 with `sqlite3`). Verified working:

| Category | Modules / features |
|---|---|
| Language (3.6) | f-strings, variable annotations, dict ordering, `1_000_000` literals, async/await syntax |
| Core | `os`, `sys`, `json`, `re`, `math`, `time`, `struct`, `datetime`, `collections`, `itertools`, `argparse`, `copy`, `unittest`, `logging`, `random`, `decimal`, `enum`, `pathlib`, `typing` |
| New in 3.6 | `secrets`, `statistics` (full), `os.fspath` |
| I/O | `io`, `pickle`, `csv`, `tempfile`, `shutil`, `mmap` |
| Network | `socket`, `select`, `urllib`, `urllib.request`, `http.client`, `email`, `ssl` HTTPS verified end-to-end |
| Crypto | `hashlib` (incl. `sha3_256`, `blake2b`, `blake2s` new in 3.6), `hmac`, `secrets` |
| Compression | `zlib`, `gzip`, `tarfile`, `zipfile`, `bz2`, `binascii`, `base64` |
| Database | `sqlite3` — full DB-API 2.0, SQLite 3.39.4 statically linked into `_sqlite3.so` |
| Process | `subprocess` |
| Terminal | `readline`, `termios` |
| Other | `uuid`, `array`, `pyexpat`, `xml.etree.ElementTree`, `unicodedata` |

## What's not included

- **Threading**: `_thread`, `threading`, `asyncio` *runtime* (the
  `async`/`await` *syntax* compiles fine, but the `asyncio` event loop
  module needs `_thread`), `concurrent.futures` — SCO's threading model
  isn't compatible with CPython, so this build is `--without-threads`.
- `_curses` — SCO's curses lacks `wchgat` (wide-char curses)
- `ctypes` — needs libffi (not on SCO)
- `_lzma` — needs liblzma
- `spwd` — SCO's `struct spwd` lacks `sp_warn`/`sp_inact`/`sp_expire`/`sp_flag`

`pip` is not bundled (the `ensurepip` step fails because of the urandom
stub during install). You can `wget` `get-pip.py` and run it — works
fine post-install.

## Quick test

```python
$ PYTHONIOENCODING=utf-8 python3
Python 3.6.15 (default, May  3 2026)
[GCC 3.4.6] on sco_sv3
>>> import ssl, urllib.request
>>> r = urllib.request.urlopen("https://www.python.org/", timeout=15)
>>> r.status
200
>>> name = "SCO"; f"hello, {name}!"
'hello, SCO!'
>>> import secrets, hashlib
>>> secrets.token_hex(8)
'a3f2...'
>>> hashlib.sha3_256(b'hello').hexdigest()[:16]
'3338be694f50c5f3'
>>> from typing import List
>>> def total(xs: List[int]) -> int: return sum(xs)
>>> total([1, 2, 3, 4])
10
>>> import sqlite3
>>> con = sqlite3.connect(":memory:")
>>> con.execute("CREATE TABLE t (k TEXT, v REAL)")
>>> con.executemany("INSERT INTO t VALUES (?, ?)", [("a", 1.5), ("b", 2.5)])
>>> con.execute("SELECT SUM(v) FROM t").fetchone()[0]
4.0
```

## Building from source

You probably don't need to do this — the release tarball is what
`build.sh` produces. If you want to rebuild:

This is a **native build, not a cross-build** (cross-compile path is
blocked by SCO's loader hiding key libc symbols from GNU-linked
binaries). You build it on the SCO machine itself.

### Requirements

- **GCC 3.4 or later** somewhere on the SCO box (the SCO-shipped GCC
  2.95.3 is C89-only and won't build Python 3 — this build needs full
  C99 support).
- `/usr/gnu/bin/{gmake,gtar}`, `/usr/bin/patch`
- **Static OpenSSL 1.0.2** at `/usr/local/lib/{libssl,libcrypto}.a` with
  headers at `/usr/local/include/openssl/`. SCO's stock 0.9.7 is too old
  for Python 3.6's `_ssl` module.
- *(optional)* **`libsqlite3.a`** at `/usr/local/lib/` with header at
  `/usr/local/include/sqlite3.h` — needed for the `sqlite3` Python module.
  Build it from the SQLite [amalgamation](https://www.sqlite.org/download.html):
  ```sh
  gcc -O2 -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -c sqlite3.c -o sqlite3.o
  ar rcs /usr/local/lib/libsqlite3.a sqlite3.o
  cp sqlite3.h /usr/local/include/
  ```
  Use the SCO-shipped GCC 2.95.3 (`/usr/gnu/bin/gcc`) for SQLite — GCC 3.4.6
  trips on the syscall table that takes the address of static-inline
  `lstat`. The resulting `.a` links cleanly into Python's `_sqlite3`
  module built with 3.4.6 (pure-C ABI is platform-defined, not
  compiler-specific). Skip this step and the `sqlite3` module will be
  absent from the final install.

### Build

If your C99 GCC is on `PATH` as `gcc`:

```sh
cd python36-sco
./build.sh
```

Otherwise tell the script where it lives:

```sh
GCC=/path/to/your/gcc-3.4 ./build.sh
```

Downloads `Python-3.6.15.tgz` from python.org, applies
`patches/python-3.6.15-sco.patch`, configures with appropriate flags,
builds, runs `make install` to `./py_install/`, strips the binary +
extension modules, and (if root and curl-sco's cacert.pem is present)
symlinks the CA bundle into OpenSSL's expected path. You can then
`gtar czf` and ship.

### What the patches do

`patches/python-3.6.15-sco.patch` is a 6 KB unified diff with six
changes:

1. **`Include/longobject.h`** — add `SIZEOF_PID_T == SIZEOF_SHORT` case.
   SCO's `pid_t` is `short`, which CPython doesn't anticipate.
2. **`Modules/socketmodule.c`** — drop the platform-specific guard
   around the `INET_ADDRSTRLEN` fallback `#define`.
3. **`Modules/_localemodule.c`** — fall back to `"ascii"` when
   `nl_langinfo(CODESET)` returns empty.
4. **`Python/pylifecycle.c`** — same `CODESET → ascii` fallback in
   `get_locale_encoding()` (this code moved here from `pythonrun.c` in
   3.5).
5. **`Python/random.c`** — fall back to a weak time+pid LCG when
   `/dev/urandom` doesn't exist; clear the `FileNotFoundError` raised
   by `_Py_open()` so callers don't see a stale error state. *NOT*
   cryptographically strong — use a different RNG if you actually need
   security.
6. **`Python/pytime.c`** — append a ~50-line shim providing
   `clock_gettime` and `clock_getres` on top of `gettimeofday()`
   (for `CLOCK_REALTIME`) and `times()` (for `CLOCK_MONOTONIC`). Also
   adds no-op stubs for `PyGILState_Ensure`/`Release`/`GetThisThreadState`
   that 3.6 leaks into `--without-threads` builds (regression vs. 3.4).

The build script also makes three post-configure tweaks: disabling
`HAVE_KQUEUE` in `pyconfig.h`, replacing `-std=c99` with `-std=gnu99`
in the Makefile, and injecting the `clockid_t` typedef + `CLOCK_*`
macros + `HAVE_CLOCK_GETTIME` into `pyconfig.h` so the rest of CPython
sees the synthesized clock API as native.

## Repository layout

```
patches/
  python-3.6.15-sco.patch    6 patches, ~6 KB unified diff

build.sh                     Native-build script (run on SCO)
LICENSE                      MIT
README.md                    This file
```

The prebuilt 35 MB tarball isn't committed to the repo (would bloat every
clone). Grab it from the **[Releases](../../releases)** page.

## License

Python is © Python Software Foundation, distributed under the [PSF
License](https://docs.python.org/3.6/license.html). The prebuilt
binary is unmodified upstream Python 3.6.15 with the patches in this
repo applied.

The patches and build script in this repo are released under the MIT
license — see [LICENSE](LICENSE).

## See also

- [Python 3.4.10 for SCO](https://github.com/tachytelic/Python-3.4.10-for-SCO-OpenServer-5)
  — the older sibling, no f-strings or new stdlib but slightly smaller.
- [curl-7.88.1 for SCO](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
  — provides the CA bundle this build needs for HTTPS verification.
- [More SCO OpenServer 5 binaries](https://scoexpert.com/guides/sco-openserver-5-binaries/)
  — bash, rsync, tar, wget, lzop, … plus notes on running these
  systems day to day.
