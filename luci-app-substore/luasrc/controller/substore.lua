-- Sub-Store LuCI controller (Lua / luci-compat)
-- Licensed under GPL-3.0

module("luci.controller.substore", package.seeall)

local fs     = require "nixio.fs"
local http   = require "luci.http"
local sys    = require "luci.sys"
local jsonc  = require "luci.jsonc"
local ucimod = require "luci.model.uci"

local STATE_FILE  = "/tmp/substore_update.state"
local RUNNER      = "/usr/libexec/substore/update-runner.sh"
local VERSION_DIR = "/usr/libexec/substore/"

local function trim(s)
	s = tostring(s or "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function uci_get(option, default)
	local v = ucimod.cursor():get("substore", "config", option)
	if v == nil or v == "" then
		return default
	end
	return v
end

local function read_version(name)
	local v = trim(fs.readfile(VERSION_DIR .. name) or "")
	if v == "" then
		return nil
	end
	return v
end

-- 通过 procd 查询服务实例状态，返回 running, pid
local function service_info()
	local out = sys.exec("ubus call service list '{\"name\":\"substore\"}' 2>/dev/null")
	local data = jsonc.parse(out or "") or {}
	local inst = data.substore and data.substore.instances
	if type(inst) == "table" then
		for k, i in pairs(inst) do
			if i.running then
				return true, tonumber(i.pid)
			end
		end
	end
	return false, nil
end

-- 读取进程内存(RSS, 字节)与运行时长(秒)
local function proc_stats(pid)
	if not pid then
		return nil, nil
	end

	local rss, uptime
	local status = fs.readfile("/proc/" .. pid .. "/status")
	if status then
		local kb = status:match("VmRSS:%s*(%d+)")
		if kb then
			rss = tonumber(kb) * 1024
		end
	end

	local stat = fs.readfile("/proc/" .. pid .. "/stat")
	local up = fs.readfile("/proc/uptime")
	if stat and up then
		-- comm 字段可能含空格/括号，从最后一个 ')' 之后开始切分
		local rest = stat:match("^.*%)%s+(.*)$")
		if rest then
			local fields = {}
			for f in rest:gmatch("%S+") do
				fields[#fields + 1] = f
			end
			-- 整体第 22 个字段 starttime，在此处下标为 20（单位：时钟节拍，按 100Hz 计）
			local start  = tonumber(fields[20])
			local sysup  = tonumber(up:match("^(%d+%.?%d*)"))
			if start and sysup then
				uptime = math.max(0, math.floor(sysup - start / 100))
			end
		end
	end

	return rss, uptime
end

-- 状态文件格式：STATE:kind:message （STATE 为 RUNNING/OK/LATEST/FAIL）
local function read_update_state()
	local raw = trim(fs.readfile(STATE_FILE) or "")
	if raw == "" then
		return nil
	end
	local st, kind, msg = raw:match("^(%u+):(%a+):(.*)$")
	if not st then
		return nil
	end
	local stat = fs.stat(STATE_FILE)
	local age = stat and (os.time() - stat.mtime) or 0
	if st == "RUNNING" and age > 600 then
		-- 调度脚本异常退出遗留的僵尸状态
		return nil
	end
	return { state = st, kind = kind, message = trim(msg), age = age }
end

function index()
	if not fs.access("/etc/config/substore") then
		return
	end

	local root = entry({"admin", "services", "substore"}, firstchild(), _("Sub-Store"), 50)
	root.dependent = false

	entry({"admin", "services", "substore", "status"},
		cbi("substore/status"), _("运行状态"), 10).leaf = true
	entry({"admin", "services", "substore", "settings"},
		cbi("substore/settings"), _("参数设置"), 20).leaf = true
	entry({"admin", "services", "substore", "log"},
		template("substore/log"), _("运行日志"), 30).leaf = true

	entry({"admin", "services", "substore", "get_status"}, call("act_status")).leaf = true
	entry({"admin", "services", "substore", "service"},    call("act_service")).leaf = true
	entry({"admin", "services", "substore", "update"},     call("act_update")).leaf = true
	entry({"admin", "services", "substore", "get_log"},    call("act_log")).leaf = true
end

function act_status()
	local running, pid = service_info()
	local rss, uptime = proc_stats(pid)

	http.prepare_content("application/json")
	http.write_json({
		running          = running,
		pid              = pid,
		enabled          = (uci_get("enabled", "0") == "1"),
		port             = uci_get("frontend_port", "3001"),
		api_path         = uci_get("frontend_backend_path", "/sub-store-api"),
		rss              = rss,
		uptime           = uptime,
		backend_version  = read_version("backend.version"),
		frontend_version = read_version("frontend.version"),
		update           = read_update_state()
	})
end

function act_service()
	local action = http.formvalue("action")
	local allowed = { start = true, stop = true, restart = true }

	http.prepare_content("application/json")
	if not allowed[action] then
		http.write_json({ ok = false, message = "无效的操作" })
		return
	end

	local code = sys.call("/etc/init.d/substore " .. action .. " >/dev/null 2>&1")
	http.write_json({ ok = (code == 0), action = action })
end

function act_update()
	local kind = http.formvalue("kind")

	http.prepare_content("application/json")
	if kind ~= "backend" and kind ~= "frontend" then
		http.write_json({ ok = false, message = "无效的更新类型" })
		return
	end

	local st = read_update_state()
	if st and st.state == "RUNNING" then
		http.write_json({ ok = false, message = "已有更新任务正在执行，请稍候" })
		return
	end

	fs.writefile(STATE_FILE, "RUNNING:" .. kind .. ":正在准备更新...\n")
	sys.call(RUNNER .. " " .. kind .. " >/dev/null 2>&1 </dev/null &")
	http.write_json({ ok = true })
end

function act_log()
	local out = sys.exec("logread 2>/dev/null | grep -iE 'sub-?store' | tail -n 300")
	http.prepare_content("text/plain; charset=utf-8")
	if trim(out) == "" then
		http.write("暂无日志")
	else
		http.write(out)
	end
end
