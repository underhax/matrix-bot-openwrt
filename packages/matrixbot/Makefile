include $(TOPDIR)/rules.mk

PKG_NAME:=matrix-bot-openwrt
PKG_VERSION:=dev
PKG_RELEASE:=1

PKG_MAINTAINER:=underhax
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/matrix-bot-openwrt
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Matrix Bot for OpenWrt
  DEPENDS:=+lua +libubox-lua +libubus-lua +libiwinfo-lua +luci-lib-nixio +luasec +libuci-lua +lua-cjson
  PKGARCH:=all
endef

define Package/matrix-bot-openwrt/description
  A lightweight, native Lua 5.1 Matrix bot for remote router management.
endef

define Build/Compile
endef

define Package/matrix-bot-openwrt/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/matrixbot
	$(CP) ./src/usr/lib/lua/matrixbot/* $(1)/usr/lib/lua/matrixbot/
	
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./src/usr/bin/matrix_send $(1)/usr/bin/matrix_send
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./src/etc/init.d/matrixbot $(1)/etc/init.d/matrixbot
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./src/etc/config/matrixbot $(1)/etc/config/matrixbot
endef

$(eval $(call BuildPackage,matrix-bot-openwrt))
