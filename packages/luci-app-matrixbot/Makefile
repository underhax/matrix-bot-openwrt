include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-matrixbot
PKG_VERSION:=dev
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for Matrix Bot
LUCI_DEPENDS:=+matrix-bot-openwrt +luci-compat
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
