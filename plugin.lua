--[[ #include "info.lua" ]]

function GetColor(props)
  return DefaultColor
end

function GetPrettyName()
  return PrettyName
end

function GetPages(props)
  local pages = {}
  --[[ #include "pages.lua" ]]
  return pages
end

function GetProperties()
	local props = {}
  --[[ #include "properties.lua" ]]
	return props
end

function RectifyProperties(props)
  --[[ #include "rectify_properties.lua" ]]
	return props
end

function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end

function GetPins(props)
  local pins = {}
  --[[ #include "pins.lua" ]]
  return pins
end

function GetControlLayout(props)
  local layout = {}
  local graphics = {}
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

--Start event based logic
if Controls then
  --[[ #include "runtime.lua" ]]
end
