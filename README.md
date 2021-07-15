# jivelite
Community logitech media server control application

This fork adds meson/ninja build files and removes local included library dependancies.

Compile with:

> meson setup build
> ninja -C build

In case you like to run jivelite without installing link the resources correct to the binary -> only suggested for developing jivelite itself

> ln -s `pwd`/share `pwd`/build/share

Install:

> ninja -C build install

Install with relative dir:

> DESTDIR=/tmp/jivelite ninja -C build install
