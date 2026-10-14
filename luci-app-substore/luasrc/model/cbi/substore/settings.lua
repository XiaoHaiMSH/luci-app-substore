-- Sub-Store 参数设置页（CBI）

local m, s, o

---------------------------------------------------------------------------
-- 校验函数
---------------------------------------------------------------------------
local function trim(v)
	return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function check_cron_field(val, min, max, name)
	if val == "" or val == "*" then
		return true
	end
	if val:find("[/%-,%*]") then
		return true
	end
	local n = tonumber(val)
	if not n then
		return nil, name .. " 字段包含非法字符"
	end
	if n < min or n > max then
		return nil, string.format("%s 字段范围为 %d-%d，当前值 %d 无效", name, min, max, n)
	end
	return true
end

local CRON_FIELDS = {
	{ "分钟", 0, 59 },
	{ "小时", 0, 23 },
	{ "日",   1, 31 },
	{ "月",   1, 12 },
	{ "星期", 0, 7  }
}

local function check_cron(value)
	local v = trim(value)
	if v == "" then
		return true
	end
	if not v:match("^[0-9%s%*/,%-]+$") then
		return nil, "请输入有效的 cron 表达式"
	end

	local parts = {}
	for p in v:gmatch("%S+") do
		parts[#parts + 1] = p
	end
	if #parts ~= 5 then
		return nil, "请输入有效的 cron 表达式（5个字段），例如：55 23 * * *"
	end

	for i, f in ipairs(CRON_FIELDS) do
		local ok, err = check_cron_field(parts[i], f[2], f[3], f[1])
		if not ok then
			return nil, err
		end
	end
	return true
end

local function check_produce_cron(value)
	local v = trim(value)
	if v == "" then
		return true
	end

	local idx = 0
	for entry in (v .. ";"):gmatch("([^;]*);") do
		entry = trim(entry)
		if entry ~= "" then
			idx = idx + 1
			local parts = {}
			for p in (entry .. ","):gmatch("([^,]*),") do
				parts[#parts + 1] = trim(p)
			end

			-- cron 表达式本身含逗号时（如 1,2 * * * *）无法按逗号切分，
			-- 因此从尾部取 类型/名称，其余部分合并回 cron
			local cron, typ, name
			if #parts >= 3 then
				name = parts[#parts]
				typ  = parts[#parts - 1]
				cron = table.concat(parts, ",", 1, #parts - 2)
			elseif #parts == 2 then
				typ  = parts[2]
				cron = parts[1]
			else
				cron = parts[1]
			end

			local ok, err = check_cron(cron)
			if not ok then
				return nil, string.format("第 %d 项 cron 表达式有误：%s", idx, err)
			end
			if typ and typ ~= "sub" and typ ~= "col" then
				return nil, string.format("第 %d 项类型必须为 sub 或 col，当前为：%s", idx, typ)
			end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- 表单
---------------------------------------------------------------------------
m = Map("substore", translate("Sub-Store"), translate("高级订阅管理器 · 参数设置"))

s = m:section(NamedSection, "config", "substore")
s.anonymous = true
s.addremove = false

s:tab("basic",    translate("基础设置"))
s:tab("network",  translate("网络与更新"))
s:tab("cron",     translate("定时任务"))
s:tab("advanced", translate("高级设置"))
s:tab("recovery", translate("数据恢复"))

-- 基础设置 -----------------------------------------------------------------
o = s:taboption("basic", Flag, "enabled", translate("启用服务"),
	translate("开启后随系统启动，并在保存应用后自动拉起 Sub-Store"))
o.rmempty = false

o = s:taboption("basic", Value, "data_dir", translate("数据目录"),
	translate("Sub-Store 数据文件存放路径"))
o.default     = "/etc/sub-store"
o.placeholder = "/etc/sub-store"

o = s:taboption("basic", Value, "frontend_backend_path", translate("后端路径前缀"),
	translate("作为 API 路径使用，避免使用特殊符号"))
o.default     = "/sub-store-api"
o.placeholder = "sub-store-api"
-- 界面不显示开头的 "/"，写入 UCI 时自动补上
function o.cfgvalue(self, section)
	local v = self.map:get(section, self.option) or self.default
	return (v:gsub("^/+", ""))
end
function o.write(self, section, value)
	value = (tostring(value or ""):gsub("^/+", ""))
	if value == "" then
		self.map:set(section, self.option, self.default)
	else
		self.map:set(section, self.option, "/" .. value)
	end
end

o = s:taboption("basic", Value, "backend_custom_name", translate("自定义实例名称"),
	translate("显示在前端界面上的后端名称"))
o.placeholder = "OpenWrt"

o = s:taboption("basic", Value, "backend_custom_icon", translate("自定义图标 URL"),
	translate("显示在前端界面上的后端图标"))
o.placeholder = "https://example.com/icon.png"

-- 网络与更新 ---------------------------------------------------------------
o = s:taboption("network", Value, "frontend_port", translate("服务端口"),
	translate("前端和后端统一使用此端口"))
o.default  = "3001"
o.datatype = "port"

o = s:taboption("network", Value, "frontend_host", translate("监听地址"),
	translate("::（同时监听 IPv4/IPv6）、0.0.0.0（仅 IPv4）、127.0.0.1（仅本机）"))
o.default     = "::"
o.placeholder = "::"
o.datatype    = "ipaddr"

o = s:taboption("network", Value, "backend_default_proxy", translate("默认代理"),
	translate("抓取订阅时使用的代理，支持 socks5://、http://、https://"))
o.placeholder = "http://127.0.0.1:7890"
function o.validate(self, value)
	value = trim(value)
	if value == "" or value:match("^https?://.+") or value:match("^socks5://.+") then
		return value
	end
	return nil, translate("输入有效的代理")
end

o = s:taboption("network", ListValue, "download_method", translate("更新方式"),
	translate("点击“更新前端/后端”时使用的下载方式"))
o:value("node", "node-fetch")
o:value("wget", "wget-ssl")
o.default  = "node"
o.rmempty  = false

o = s:taboption("network", Value, "download_proxy", translate("更新加速"),
	translate("更新前端/后端时，用于加速下载资源的反代地址前缀。留空则直连 GitHub"))
o.placeholder = "https://ghfast.top/"
function o.validate(self, value)
	value = trim(value)
	if value == "" or value:match("^https?://.+") then
		return value
	end
	return nil, translate("请输入有效的加速代理")
end

o = s:taboption("network", Value, "github_token", translate("GitHub 令牌"),
	translate("查询版本号时携带此令牌请求 GitHub API，留空则匿名请求"))
o.password = true

-- 定时任务 -----------------------------------------------------------------
o = s:taboption("cron", Value, "backend_sync_cron", translate("订阅同步定时"),
	translate("定时将订阅推送到 Gist"))
o.placeholder = "55 23 * * *"
function o.validate(self, value)
	local ok, err = check_cron(value)
	if not ok then return nil, err end
	return trim(value)
end

o = s:taboption("cron", Value, "backend_upload_cron", translate("数据备份定时"),
	translate("定时将 Sub-Store 全部数据备份到 Gist"))
o.placeholder = "0 2 * * *"
function o.validate(self, value)
	local ok, err = check_cron(value)
	if not ok then return nil, err end
	return trim(value)
end

o = s:taboption("cron", Value, "backend_download_cron", translate("数据恢复定时"),
	translate("定时从 Gist 恢复 Sub-Store 数据"))
o.placeholder = "55 22 * * *"
function o.validate(self, value)
	local ok, err = check_cron(value)
	if not ok then return nil, err end
	return trim(value)
end

o = s:taboption("cron", Value, "produce_cron", translate("订阅预处理定时"),
	translate("格式：cron表达式,类型,名称；多个用分号连接，类型为 sub 或 col，例如：0 */2 * * *,sub,订阅名称"))
o.placeholder = "0 */2 * * *,sub,订阅名称"
function o.validate(self, value)
	local ok, err = check_produce_cron(value)
	if not ok then return nil, err end
	return trim(value)
end

-- 高级设置 -----------------------------------------------------------------
o = s:taboption("advanced", Value, "x_powered_by", translate("X-Powered-By 响应头"),
	translate("自定义 HTTP 响应头中的 X-Powered-By 字段"))
o.placeholder = "Express"

o = s:taboption("advanced", Value, "cors_allowed_origins", translate("CORS 允许来源"),
	translate("允许访问后端 API 的浏览器来源，多个用逗号分隔，* 表示允许所有"))
o.default     = "*"
o.placeholder = "*"

o = s:taboption("advanced", Value, "max_header_size", translate("最大 Header 大小（字节）"),
	translate("遇到 Headers Overflow Error 时可适当调大"))
o.default  = "32768"
o.datatype = "uinteger"

o = s:taboption("advanced", Value, "body_json_limit", translate("JSON Body 大小限制"),
	translate("例如 1mb、10mb"))
o.default     = "1mb"
o.placeholder = "1mb"

o = s:taboption("advanced", Value, "push_service", translate("推送服务 URL"),
	translate("支持 Bark、Telegram、PushPlus 等，用 [推送标题] 和 [推送内容] 作为占位符"))
o.placeholder = "https://api.day.app/YOUR_KEY/[推送标题]/[推送内容]"

-- 数据恢复 -----------------------------------------------------------------
o = s:taboption("recovery", Value, "data_url", translate("远程数据 URL"),
	translate("启动时从此地址拉取并恢复数据，支持 Gist Raw 链接"))
o.placeholder = "https://gist.githubusercontent.com/user/id/raw/Sub-Store#noCache"

o = s:taboption("recovery", Value, "data_url_post", translate("拉取后执行"),
	translate("拉取数据后执行的 JS 表达式，例如设置 Gist Token"))
o.placeholder = "content.settings.gistToken='your_token_here'"

return m
