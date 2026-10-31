#!/bin/sh
# Verifies the GTK 3 set build.sh packed. Runs in the same container,
# right after it.
#
# Usage: test.sh
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)

packed=dist/gtk3-$arch.onelf
onelf verify "$packed"

list=$(onelf list "$packed")
for path in \
    "lib/libgtk-3.so.0" \
    "lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" \
    "lib/gtk-3.0/3.0.0/immodules.cache" \
    "share/glib-2.0/schemas/gschemas.compiled" \
    "share/mime/mime.cache"
do
    case $list in
    *"$path"*) : ;;
    *)
        echo "the set is missing $path" >&2
        exit 1
        ;;
    esac
done

# The runtime joins each module path in a cache onto the cache's own
# directory, so every path must be relative and name a module the set
# carries from there.
extract=$(mktemp -d)
trap 'rm -rf "$extract"' EXIT
onelf extract "$packed" -o "$extract" > /dev/null
for cache in "$extract"/lib/gdk-pixbuf-2.0/*/loaders.cache "$extract"/lib/gtk-3.0/*/immodules.cache; do
    modules=$(sed -n 's/^"\([^"]*\.so\)"[[:space:]]*$/\1/p' "$cache")
    if [ -z "$modules" ]; then
        echo "${cache#"$extract"/} names no modules" >&2
        exit 1
    fi
    for module in $modules; do
        if [ ! -f "$(dirname "$cache")/$module" ]; then
            echo "${cache#"$extract"/} names $module, which is not beside it" >&2
            exit 1
        fi
    done
done

echo "gtk3-$arch: verify, contents and caches ok"
