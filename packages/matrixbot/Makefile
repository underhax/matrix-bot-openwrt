include $(TOPDIR)/rules.mk

PKG_NAME:=matrixbot
PKG_VERSION:=0.0.1
PKG_RELEASE:=1

PKG_MAINTAINER:=underhax
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/matrixbot
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Matrix Bot for OpenWrt
  DEPENDS:=+lua +libubox-lua +libubus-lua +libiwinfo-lua +luci-lib-nixio +luasec +libuci-lua +lua-cjson
  PKGARCH:=all
endef

define Package/matrixbot/description
  A lightweight, native Lua 5.1 Matrix bot for remote router management.
endef

define Build/Compile
endef

define Package/matrixbot/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ -x /etc/init.d/matrixbot ]; then
		if /etc/init.d/matrixbot enabled 2>/dev/null; then
			touch /tmp/matrixbot_upgrade_enabled
		fi
		if /etc/init.d/matrixbot running 2>/dev/null; then
			touch /tmp/matrixbot_upgrade_running
		fi
		/etc/init.d/matrixbot stop 2>/dev/null || true
		timeout=10
		while /etc/init.d/matrixbot running 2>/dev/null && [ $$timeout -gt 0 ]; do
			sleep 1
			timeout=$$((timeout - 1))
		done
	fi
}
exit 0
endef

define Package/matrixbot/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/matrixbot
	$(CP) ./src/usr/lib/lua/matrixbot/* $(1)/usr/lib/lua/matrixbot/

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./src/usr/bin/matrix_send $(1)/usr/bin/matrix_send

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./src/etc/init.d/matrixbot $(1)/etc/init.d/matrixbot

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./src/etc/config/matrixbot $(1)/etc/config/matrixbot
endef

define Package/matrixbot/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ -f /tmp/matrixbot_upgrade_enabled ]; then
		rm -f /tmp/matrixbot_upgrade_enabled
		/etc/init.d/matrixbot enable
	fi
	if [ -f /tmp/matrixbot_upgrade_running ]; then
		rm -f /tmp/matrixbot_upgrade_running
		/etc/init.d/matrixbot start
	fi
}
exit 0
endef

define Package/matrixbot/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ "$$1" = "upgrade" ] && exit 0
	/etc/init.d/matrixbot stop 2>/dev/null || true
	/etc/init.d/matrixbot disable 2>/dev/null || true
}
exit 0
endef

$(eval $(call BuildPackage,matrixbot))
