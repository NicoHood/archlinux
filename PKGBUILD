# Maintainer: NicoHood <archlinux {cat} nicohood {dog} de>
# PGP ID: 97312D5EB9D7AE7D0BD4307351DAE9B7C1AE9161

pkgname=nicohood
_pkgname=archlinux
pkgver=0.0.6
pkgrel=1
pkgdesc="A collection of personal Arch Linux tools."
arch=('any')
url="https://github.com/NicoHood"
license=('GPL3')
depends=('bash' 'arch-install-scripts' 'btrfs-progs' 'dosfstools' 'cryptsetup')
source=("${pkgname}-${pkgver}.tar.xz::https://github.com/NicoHood/${_pkgname}/releases/download/${pkgver}/${_pkgname}-${pkgver}.tar.xz"
        "${pkgname}-${pkgver}.tar.xz.asc::https://github.com/NicoHood/${_pkgname}/releases/download/${pkgver}/${_pkgname}-${pkgver}.tar.xz.asc")
sha512sums=('09a675e7eb4373512afe4ddb4dd4d20d60019387ce75da2ff8e2f2ea8d3e97f7568ff4e600a0fd5d8da95eeb3740f1b4d121086392884651e065ef301944b18f'
            'SKIP')
# NicoHood <archlinux {cat} nicohood {dog} de>
validpgpkeys=('97312D5EB9D7AE7D0BD4307351DAE9B7C1AE9161')

package() {
    make -C "${_pkgname}-${pkgver}" DESTDIR="${pkgdir}" install
}
