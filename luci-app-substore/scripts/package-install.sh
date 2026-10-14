#!/bin/sh

set -e

DEST="$1"
SRC="$2"

if [ -z "$DEST" ] || [ -z "$SRC" ]; then
	echo "错误: package-install.sh 需要两个参数 <目标目录> <包源码目录>" >&2
	exit 1
fi

# --- 服务与配置 ---
install -d "$DEST/etc/init.d"
install -m0755 "$SRC/root/etc/init.d/substore" "$DEST/etc/init.d/substore"

install -d "$DEST/etc/config"
install -m0644 "$SRC/root/etc/config/substore" "$DEST/etc/config/substore"

# --- 辅助脚本 ---
install -d "$DEST/usr/libexec/substore"
for f in postinstall.sh update-runner.sh \
	update-backend.sh update-frontend.sh \
	node-fetch-update-backend.sh node-fetch-update-frontend.sh \
	wget-ssl-update-backend.sh wget-ssl-update-frontend.sh; do
	install -m0755 "$SRC/root/usr/libexec/substore/$f" "$DEST/usr/libexec/substore/$f"
done

# --- LuCI (Lua) ---
LUCI="$DEST/usr/lib/lua/luci"
install -d "$LUCI/controller"
install -m0644 "$SRC/luasrc/controller/substore.lua" "$LUCI/controller/substore.lua"

install -d "$LUCI/model/cbi/substore"
for f in status.lua settings.lua; do
	install -m0644 "$SRC/luasrc/model/cbi/substore/$f" "$LUCI/model/cbi/substore/$f"
done

install -d "$LUCI/view/substore"
for f in status.htm log.htm; do
	install -m0644 "$SRC/luasrc/view/substore/$f" "$LUCI/view/substore/$f"
done

# --- 静态资源 ---
install -d "$DEST/www/luci-static/resources/substore"
for f in icon-running.png icon-stopped.png; do
	install -m0644 "$SRC/root/www/luci-static/resources/substore/$f" \
		"$DEST/www/luci-static/resources/substore/$f"
done

# --- Sub-Store 后端 / 前端 ---
sh "$SRC/scripts/download-assets.sh" backend "$DEST/usr/libexec/substore"

install -d "$DEST/www/sub-store"
sh "$SRC/scripts/download-assets.sh" frontend "$DEST/usr/libexec/substore" "$DEST/www/sub-store"
