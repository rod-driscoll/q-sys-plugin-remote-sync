--[[
  20250711 v1.0 Rod Driscoll<rod@theavitgroup.com.au>
]]
BuildVersion = "1.0.1.1" -- updated by the compiler

PluginInfo = {
  Name = "Q-SYS~Remote component sync",
  Version = BuildVersion,
  Id = "Q-SYS Remote component sync",
  Author = "Rod Driscoll<rod@theavitgroup.com.au>",
  Description = "Synchronise components with a remote core.",
  Manufacturer = "Q-SYS",
  ShowDebug = true,
}
PrettyName = PluginInfo.Id..' '.. PluginInfo.Version
PageNames = {"Setup","System","Devices"} --List the pages within the plugin
DefaultColor = { 102, 102, 102 }