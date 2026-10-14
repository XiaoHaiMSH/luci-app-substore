-- Sub-Store 运行状态页：仅承载状态面板模板

local m, s

m = SimpleForm("substore_status", translate("Sub-Store"), translate("高级订阅管理器"))
m.reset  = false
m.submit = false

s = m:section(SimpleSection)
s.template = "substore/status"

return m
