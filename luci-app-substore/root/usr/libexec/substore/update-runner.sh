#!/bin/sh
# Sub-Store 更新调度器（由 LuCI 控制器后台调用）
# 用法: update-runner.sh backend|frontend
# 依次尝试 代理加速 -> 直连，进度/结果写入 /tmp/substore_update.state 供页面轮询
# 状态行格式:  STATE:kind:message   (STATE = RUNNING | OK | LATEST | FAIL)

KIND="$1"
DIR="/usr/libexec/substore"
STATE="/tmp/substore_update.state"
ERRF="/tmp/substore_update.err"

set_state() {
	_msg=$(printf '%s' "$2" | tr '\n\r' '  ')
	printf '%s:%s:%s\n' "$1" "$KIND" "$_msg" > "$STATE"
}

trim() {
	sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

case "$KIND" in
	backend)  LABEL="后端" ;;
	frontend) LABEL="前端" ;;
	*)
		echo "FAIL:${KIND}:参数无效" > "$STATE"
		exit 1
		;;
esac

METHOD=$(uci -q get substore.config.download_method)
[ -z "$METHOD" ] && METHOD="node"

PROXY=$(uci -q get substore.config.download_proxy | trim)
SOURCES="official"
[ -n "$PROXY" ] && SOURCES="proxy official"

LAST_ERR=""
for SRC in $SOURCES; do
	if [ "$SRC" = "proxy" ]; then SN="代理加速"; else SN="直连"; fi

	set_state RUNNING "正在通过${SN}检测并更新${LABEL}..."
	OUT=$("$DIR/update-$KIND.sh" "$SRC" "$METHOD" 2>"$ERRF" | trim)
	ERR=$(trim < "$ERRF" 2>/dev/null)

	case "$OUT" in
		OK)
			set_state OK "${LABEL}已更新"
			rm -f "$ERRF"
			exit 0
			;;
		ALREADY_LATEST:*)
			set_state LATEST "$(printf '%s' "${OUT#ALREADY_LATEST:}" | trim)"
			rm -f "$ERRF"
			exit 0
			;;
		DOWNLOAD_FAILED:*)
			LAST_ERR="${SN}更新失败：$(printf '%s' "${OUT#DOWNLOAD_FAILED:}" | trim)"
			;;
		*)
			LAST_ERR="${SN}更新失败：${ERR:-${OUT:-脚本执行失败}}"
			;;
	esac

	if [ "$SRC" = "proxy" ]; then
		set_state RUNNING "${LAST_ERR}，正在改用直连..."
		sleep 1
	fi
done

rm -f "$ERRF"
set_state FAIL "$LAST_ERR"
exit 1
