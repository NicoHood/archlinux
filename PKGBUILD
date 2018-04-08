# Maintainer: NicoHood <archlinux {cat} nicohood {dog} de>
# PGP ID: 97312D5EB9D7AE7D0BD4307351DAE9B7C1AE9161

pkgname=nicohood
_pkgname=archlinux
pkgver=0.0.2
pkgrel=1
pkgdesc="A collection of personal Arch Linux tools."
arch=('any')
url="https://github.com/NicoHood"
license=('GPL3')
depends=('bash' 'arch-install-scripts' 'btrfs-progs' 'dosfstools' 'cryptsetup')
source=("${pkgname}-${pkgver}.tar.xz::https://github.com/NicoHood/${_pkgname}/releases/download/${pkgver}/${_pkgname}-${pkgver}.tar.xz"
        "${pkgname}-${pkgver}.tar.xz.asc::https://github.com/NicoHood/${_pkgname}/releases/download/${pkgver}/${_pkgname}-${pkgver}.tar.xz.asc")
sha512sums=('8b79d1cbbde81299d13c50015db6afa1ac49deb7b4c2406fafc607aba629873da95e57428717852e96d1ab23e14e4215954d164c53005c870c02db09823b5dd6'
            'SKIP')
# NicoHood <archlinux {cat} nicohood {dog} de>
validpgpkeys=('97312D5EB9D7AE7D0BD4307351DAE9B7C1AE9161')

package() {
    make -C "${_pkgname}-${pkgver}" DESTDIR="${pkgdir}" install
}
