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
    "lib/gtk-3.0/immodules.cache" \
    "share/glib-2.0/schemas/gschemas.compiled"
do
    case $list in
    *"$path"*) : ;;
    *)
        echo "the set is missing $path" >&2
        exit 1
        ;;
    esac
done

echo "gtk3-$arch: verify and contents ok"
