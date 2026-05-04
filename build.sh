#!/bin/sh
# Build Python 3.6.15 natively on SCO OpenServer 5.0.7.
#
# Run this script ON the SCO machine, in a writable directory.
#
# Required:
#   GCC 3.4 or later (the SCO native 2.95.3 is C89-only and won't build
#       Python 3 — full C99 support is needed). Set CC and put it on PATH
#       before running this script, or override via the GCC env var.
#   /usr/gnu/bin/{gmake,gtar}, /usr/bin/patch, /bin/{sed,gunzip}
#   wget or curl, OR drop Python-3.6.15.tgz next to this script
#   Static OpenSSL 1.0.2 at /usr/local/lib/{libssl,libcrypto}.a
#       with headers at /usr/local/include/openssl/.  (For TLS support.
#       SCO's stock OpenSSL 0.9.7 is too old — Python 3.6 needs 1.0.x.)
#
# Output: ./py_install/ — a relocatable Python install.

set -e

SCRIPT_DIR=`cd \`dirname "$0"\` && pwd`
VERSION=3.6.15
TARBALL=Python-${VERSION}.tgz
SRCDIR=Python-${VERSION}

# If you already have a C99 gcc on PATH, set CC=gcc and skip the next block.
# Otherwise tell the script where it lives via GCC env var:
#   GCC=/path/to/your/gcc-3.4 ./build.sh
if [ -n "$GCC" ]; then
    CC="$GCC"
fi
CC="${CC:-gcc}"
export CC

PATH=/usr/gnu/bin:/usr/ccs/bin:/usr/bin:/bin
export PATH

# Sanity check: refuse to start if the chosen gcc is too old.
gcc_ver=`$CC -dumpversion 2>/dev/null`
case "$gcc_ver" in
    2.*)
        echo "ERROR: $CC is GCC $gcc_ver — too old (C89 only)." >&2
        echo "       Python 3.6 needs GCC 3.4+ for full C99 support." >&2
        echo "       Set GCC=/path/to/newer/gcc before running." >&2
        exit 1 ;;
esac
echo "Using $CC (GCC $gcc_ver)"

if [ ! -f "$TARBALL" ]; then
    echo "Fetching $TARBALL..."
    if which wget >/dev/null 2>&1; then
        wget --no-check-certificate "https://www.python.org/ftp/python/${VERSION}/${TARBALL}"
    elif which curl >/dev/null 2>&1; then
        curl -kLO "https://www.python.org/ftp/python/${VERSION}/${TARBALL}"
    else
        echo "ERROR: no wget or curl. Drop $TARBALL next to this script." >&2
        exit 1
    fi
fi

if [ ! -d "$SRCDIR" ]; then
    echo "Unpacking $TARBALL..."
    gtar xzf "$TARBALL"
fi

echo "Applying SCO compatibility patches..."
cd "$SRCDIR"
if [ -f .sco_patched ]; then
    echo "  (already applied — skipping)"
else
    patch -p1 < "$SCRIPT_DIR/patches/python-${VERSION}-sco.patch"
    touch .sco_patched
fi

echo "Configuring..."
CFLAGS="-O2 -std=gnu99" \
CPPFLAGS="-I/usr/local/include -I/usr/local/ssl/include" \
LDFLAGS="-L/usr/local/lib -L/usr/local/ssl/lib" \
./configure --prefix="$SCRIPT_DIR/py_install" --without-pymalloc --without-threads

# Three post-configure tweaks:
# 1. Disable HAVE_KQUEUE — SCO has <sys/event.h> from some package but the
#    kqueue API is incomplete; without this, Modules/selectmodule.c won't
#    compile and the select extension is silently dropped.
# 2. Replace -std=c99 with -std=gnu99 — strict C99 mode hides POSIX
#    declarations like struct sigaction on SCO's headers.
# 3. Inject SCO clock shim into pyconfig.h — Python 3.6 uses
#    clock_gettime/clock_getres/clockid_t which SCO doesn't provide.
#    Pair this with the implementation appended to Python/pytime.c
#    by the patch above.
echo "Post-configure tweaks..."
sed "s|^#define HAVE_KQUEUE 1\$|/* #undef HAVE_KQUEUE */|" pyconfig.h > pyconfig.h.new
mv pyconfig.h.new pyconfig.h
sed "s|-std=c99|-std=gnu99|g" Makefile > Makefile.new
mv Makefile.new Makefile

# Inject SCO time shim before the Py_PYCONFIG_H end guard.
END_LINE=`grep -n '^#endif /\*Py_PYCONFIG_H\*/' pyconfig.h | head -1 | cut -d: -f1`
if [ -n "$END_LINE" ]; then
    BEFORE_END=`expr $END_LINE - 1`
    head -$BEFORE_END pyconfig.h > pyconfig.h.new
    cat >> pyconfig.h.new <<EOF

/* SCO clock shim (impl: Python/pytime.c, appended by the SCO patch). */
#ifdef SCO5
#ifndef _SCO_TIME_SHIM_DEFINED
#define _SCO_TIME_SHIM_DEFINED
struct timespec;
typedef int clockid_t;
#define CLOCK_REALTIME  0
#define CLOCK_MONOTONIC 1
extern int clock_gettime(clockid_t, struct timespec *);
extern int clock_getres(clockid_t, struct timespec *);
#define HAVE_CLOCK_GETTIME 1
#define HAVE_CLOCK_GETRES 1
#endif
#endif

#endif /*Py_PYCONFIG_H*/
EOF
    mv pyconfig.h.new pyconfig.h
fi

echo "Compiling (long — go make tea)..."
gmake

echo "Installing to $SCRIPT_DIR/py_install/..."
gmake -s install || true   # ensurepip step may fail (urandom-related); install itself is OK

echo "Stripping binaries..."
strip "$SCRIPT_DIR/py_install/bin/python3.6" 2>/dev/null || true
find "$SCRIPT_DIR/py_install" -name "*.so" -exec strip {} \; 2>/dev/null

# Wire up an HTTPS-capable CA bundle.
# OpenSSL's compile-time default cafile is /usr/local/ssl/cert.pem (where
# Python's `ssl` module looks). If you've already installed the curl-sco
# package, Mozilla's bundle lives at /usr/local/etc/ssl/cert.pem — we just
# symlink it into the OpenSSL-default location so HTTPS works out of the box.
# Skip silently if the user already has something at /usr/local/ssl/cert.pem.
if [ ! -e /usr/local/ssl/cert.pem ] && [ -f /usr/local/etc/ssl/cert.pem ]; then
    if mkdir -p /usr/local/ssl/certs 2>/dev/null && \
       ln -s /usr/local/etc/ssl/cert.pem /usr/local/ssl/cert.pem 2>/dev/null; then
        echo "Linked CA bundle: /usr/local/ssl/cert.pem -> /usr/local/etc/ssl/cert.pem"
    fi
fi
if [ ! -e /usr/local/ssl/cert.pem ]; then
    echo
    echo "WARNING: no CA bundle at /usr/local/ssl/cert.pem"
    echo "  HTTPS verification will fail until you provide one. Either:"
    echo "    1. Install the curl-sco package (provides /usr/local/etc/ssl/cert.pem),"
    echo "       then re-run this script — it'll add the symlink."
    echo "    2. Drop a Mozilla CA bundle at /usr/local/ssl/cert.pem yourself."
    echo "    3. Set SSL_CERT_FILE in your environment per-invocation."
fi

ls -l "$SCRIPT_DIR/py_install/bin/python3"
echo
echo "Built: $SCRIPT_DIR/py_install/"
echo "Test it: $SCRIPT_DIR/py_install/bin/python3 --version"
echo
echo "To package: gtar czf python-${VERSION}-sco.tar.gz py_install"
