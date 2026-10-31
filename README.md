# gtk

[GTK 3](https://gtk.org) built for [onelf](https://github.com/QaidVoid/onelf)
packages: the toolkit, image loaders and their data an application names under
`[sysroot.sets.gtk3]`, fetched at launch and shared by every package that pins
it, so ten GTK applications share one download instead of each carrying the
toolkit.

## What the set holds

- GTK 3, GDK and every library they need apart from glibc, closed from
  Void Linux's packages.
- gdk-pixbuf with its loaders and `loaders.cache`, and librsvg with the
  loader that renders the SVG icons Adwaita ships.
- The input-method modules and print backends, with `immodules.cache`.
- The GSettings schemas of GTK and gsettings-desktop-schemas, compiled;
  the dconf GSettings backend, so settings read and write.
- The Adwaita and hicolor icon themes, with their caches.
- The compiled shared-mime-info database, by which gdk-pixbuf tells an
  icon's format, so a host without one still draws icons.

Locales, headers, documentation, introspection data and the host-side
wiring (the packages' binaries, D-Bus service files, thumbnailers) stay
out. `share/` joins `XDG_DATA_DIRS`, and the runtime wires the rest
itself: `GTK_PATH` from `lib/gtk-3.0/`, the loader caches from wherever
they sit, `GIO_MODULE_DIR` from `lib/gio/modules/`.

## Where it comes from

The set is not built from source. It is the closure of Void Linux's
`gtk+3`, `gdk-pixbuf`, `librsvg`, `dconf`, `gsettings-desktop-schemas`,
`adwaita-icon-theme` and `hicolor-icon-theme` packages on Void glibc,
whose official images cover x86_64 and aarch64, shaped into the tree
`onelf sysroot pack-set` takes: libraries under `lib/`, modules where
the runtime looks for them, each cache naming its modules relative to
itself so the runtime can absolutise them at launch. The version in
`package.toml` tracks GNOME's gtk3 releases; the GNOME tarball it names
is only provenance for the version the release is tagged with.

## Releases

Tagged `v<gtk version>-<release>`, where `release` counts rebuilds of
the same GTK. Each release carries, per architecture:

| Asset | Holds |
|-------|-------|
| `gtk3-<arch>.onelf` | the set packed by `onelf sysroot pack-set` |

The release notes list each build's BLAKE3, the hash a package pins to
fetch the set at launch.

## Pinning it

    [sysroot.sets.gtk3]
    url = "https://github.com/onelf-pkgs/gtk/releases/download/v3.24.52-1/gtk3-<arch>.onelf"
    blake3 = "..."

The set is not optional the way the GL build is: a package naming it
carries none of the toolkit, so a set that cannot be obtained ends the
launch. The hash is checked before the set is used, and two packages
pinning the same set share one download and one extraction.

## Why upstream is not followed

The `upstream` key is left out on purpose: GNOME tags 3.x and 4.x in one
repository, and upstream.py's gitlab tag-prefix search cannot separate
the two, so a bump would name the wrong major. The control repository
bumps `version` when GNOME releases a 3.24.x and resets `release` to 1.

## Building

```sh
podman run --rm -v "$PWD:/src" -v "$(command -v onelf):/usr/local/bin/onelf:ro" -w /src \
  ghcr.io/void-linux/void-glibc:latest sh build.sh
```

The build refuses a Void repository older than the `version` in
`package.toml`, so a tag never holds less than it says. aarch64 is
built by CI; a host of another architecture is refused.
