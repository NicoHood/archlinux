# Maintainer: NicoHood <archlinux {cat} nicohood {dog} de>
# PGP ID: 97312D5EB9D7AE7D0BD4307351DAE9B7C1AE9161

pkgname=nicohood
_pkgname=archlinux
pkgver=0.0.7
pkgrel=1
pkgdesc="A collection of personal Arch Linux tools."
arch=('any')
url="https://github.com/NicoHood"
license=('GPL3')
depends=('bash' 'arch-install-scripts' 'btrfs-progs' 'dosfstools' 'cryptsetup')
source=("${pkgname}-${pkgver}.tar.xz::https://github.com/NicoHood/${_pkgname}/releases/download/${pkgver}/${_pkgname}-${pkgver}.tar.xz"
        "${pkgname}-${pkgver}.tar.xz.asc::https://github.com/NicoHood/${_pkgname}/releases/download/${pkgver}/${_pkgname}-${pkgver}.tar.xz.asc")
sha512sums=('8f8479b98b5c374c1389f4052598bc342bac656cfb3afccfde0eec4cdc410f6544c83f999968afec91157de633cd4a82a0809507d60ced316c1148069cac3dc3'
            'SKIP')
# NicoHood <archlinux {cat} nicohood {dog} de>
validpgpkeys=('97312D5EB9D7AE7D0BD4307351DAE9B7C1AE9161')

package() {
    make -C "${_pkgname}-${pkgver}" DESTDIR="${pkgdir}" install
}
