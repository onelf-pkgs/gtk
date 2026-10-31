#!/bin/sh
# Builds the GTK 3 dependency set for this machine's architecture into
# dist/:
#
#   gtk3-<arch>.onelf, gtk3-<arch>.onelf.blake3
#
# The set is a tree as `onelf sysroot pack-set` takes it: lib/ with GTK3,
# gdk-pixbuf, their modules and every library they need apart from
# glibc, and share/ with the icons, schemas and compiled caches the
# runtime wires at launch. Each .onelf is that tree packed, with its
# BLAKE3 in a .blake3 beside it.
#
# Usage: build.sh
#
# Runs as root in a Void Linux (glibc) container with this directory as
# the working directory and onelf on PATH.
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)
case $arch in
x86_64 | aarch64) ;;
*)
    echo "unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

# Nothing is compiled: the set is the closure of Void's packages, so
# only the tools the assembly and the caches need are installed.
xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y \
    binutils findutils \
    gtk+3 gdk-pixbuf librsvg dconf gsettings-desktop-schemas \
    adwaita-icon-theme hicolor-icon-theme shared-mime-info > /dev/null

version=$(sed -n 's/^version = "\(.*\)"/\1/p' package.toml)
repo_version=$(xbps-query gtk+3 | awk '$1 == "pkgver:" { sub(/^gtk\+3-/, "", $2); sub(/_[0-9]*$/, "", $2); print $2 }')
if [ "$repo_version" != "$version" ]; then
    echo "package.toml versions gtk $version, Void's repository has $repo_version" >&2
    exit 1
fi

work=$PWD/build/work
tree=$work/tree

rm -rf "$work"
mkdir -p "$tree/lib" "$tree/share"

# seed <package>: copy the files <package> owns into the tree, /usr
# flattened to the tree root. What a set never carries stays out: the
# packages' binaries, locales, docs and host-side wiring, and the
# introspection data, of which a partial copy would be worse than none.
# Soname links into /usr/lib are recreated as links within the tree.
seed() {
    xbps-query -f "$1" | while IFS= read -r entry; do
        case $entry in
        /*) : ;;
        *) continue ;;
        esac
        link=${entry%% ->*}
        case $entry in
        *" -> "*) target=${entry#* -> } ;;
        *) target= ;;
        esac
        case $link in
        /usr/lib/girepository-1.0/* | /usr/lib/systemd/*) continue ;;
        /usr/lib/*) dest=lib/${link#/usr/lib/} ;;
        /usr/share/icons/* | /usr/share/glib-2.0/* | /usr/share/gtk-3.0/* | /usr/share/themes/*)
            dest=share/${link#/usr/share/}
            ;;
        *) continue ;;
        esac
        mkdir -p "$(dirname "$tree/$dest")"
        case $target in
        "") cp -L "$link" "$tree/$dest" ;;
        /*)
            if [ "${target%/*}" = "${link%/*}" ]; then
                ln -s "${target##*/}" "$tree/$dest"
            else
                echo "seed: cannot relocate symlink $entry" >&2
                exit 1
            fi
            ;;
        *) ln -s "$target" "$tree/$dest" ;;
        esac
    done
}

for package in \
    gtk+3 gdk-pixbuf librsvg dconf gsettings-desktop-schemas \
    adwaita-icon-theme hicolor-icon-theme
do
    seed "$package"
done

# glibc stays with the package that uses the set; everything else a
# library in the tree needs is copied in.
is_glibc() {
    case $1 in
    ld-linux*.so.* | libc.so.* | libm.so.* | libmvec.so.* | libpthread.so.* | \
        libdl.so.* | librt.so.* | libresolv.so.* | libutil.so.* | libanl.so.*)
        return 0
        ;;
    esac
    return 1
}

set -- /usr/lib/ld-linux-*.so.*
loader=$1

# close <tree>: copy into <tree>/lib every library its objects need.
close() {
    while :; do
        added=0
        find "$1/lib" -name '*.so*' -type f > "$work/objects"
        while read -r object; do
            "$loader" --library-path "$1/lib:/usr/lib" --list "$object" > "$work/list"
            awk '$2 == "=>" && $3 ~ /^\// { print $1, $3 }' "$work/list" > "$work/needs"
            while read -r soname path; do
                if is_glibc "$soname" || [ -e "$1/lib/$soname" ]; then
                    continue
                fi
                cp -L "$path" "$1/lib/$soname"
                added=1
            done < "$work/needs"
        done < "$work/objects"
        [ "$added" -eq 1 ] || break
    done
}

close "$tree"

find "$tree/lib" -name '*.so*' -type f -exec strip --strip-unneeded {} +

# Each cache sits where GTK keeps it, in its version directory, and names
# its modules relative to itself, which the runtime absolutises at
# launch. The query tools canonicalise whatever they are given, so the
# directory is cut again. The schema sources stay out: what an
# application reads is the compiled file.
pixbuf_dir=$tree/lib/gdk-pixbuf-2.0/$(cd "$tree/lib/gdk-pixbuf-2.0" && set -- * && [ $# -eq 1 ] && echo "$1")
gtk_dir=$tree/lib/gtk-3.0/$(cd "$tree/lib/gtk-3.0" && set -- */ && [ $# -eq 1 ] && echo "${1%/}")
(
    cd "$pixbuf_dir"
    LD_LIBRARY_PATH="$tree/lib" gdk-pixbuf-query-loaders loaders/*.so > loaders.cache
    sed -i "s|$pixbuf_dir/||g" loaders.cache
)
(
    cd "$gtk_dir"
    LD_LIBRARY_PATH="$tree/lib" gtk-query-immodules-3.0 immodules/*.so > immodules.cache
    sed -i "s|$gtk_dir/||g" immodules.cache
)
# gdk-pixbuf tells an icon's format by its MIME type, so without the
# database a host lacking one draws no icons. Only the compiled files at
# its top are read for that; the per-type directories hold descriptions.
mkdir -p "$tree/share/mime"
find /usr/share/mime -maxdepth 1 -type f -exec cp {} "$tree/share/mime/" \;
(
    cd "$tree"
    glib-compile-schemas share/glib-2.0/schemas
    rm share/glib-2.0/schemas/*.gschema.xml
    gio-querymodules lib/gio/modules
)

rm -rf dist
mkdir -p dist
out=dist/gtk3-$arch.onelf
onelf sysroot pack-set "$tree" -o "$out" --name gtk3 | tee "$work/pack.log"
hash=$(grep -o '[0-9a-f]\{64\}' "$work/pack.log" | tail -n 1)
if [ -z "$hash" ]; then
    echo "pack-set printed no hash for $out" >&2
    exit 1
fi
echo "$hash" > "$out.blake3"

ls -l dist
