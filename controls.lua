-- Reveal code pin for testing --
table.insert(ctrls, {
  Name         = "code",
  ControlType  = "Text",
  Count        = 1,
  UserPin      = true,
  PinStyle     = "Input"
})

-- Debug controls--
table.insert(ctrls, {
  Name         = "DebugFunction",
  ControlType  = "Button",
  ButtonType   = "Toggle",
  PinStyle     = "Input",
  UserPin      = true,
  Count        = 1
})
table.insert(ctrls, {
  Name         = "DebugTx",
  ControlType  = "Button",
  ButtonType   = "Toggle",
  PinStyle     = "Input",
  UserPin      = true,
  Count        = 1
})
table.insert(ctrls, {
  Name         = "DebugRx",
  ControlType  = "Button",
  ButtonType   = "Toggle",
  PinStyle     = "Input",
  UserPin      = true,
  Count        = 1
})

-- Configuration Controls --
table.insert(ctrls, {
  Name         = "IPAddress",
  ControlType  = "Text",
  Count        = 1,
  DefaultValue = "Enter an IP Address",
  UserPin      = true,
  PinStyle     = "Both"
})
table.insert(ctrls, {
  Name         = "Username",
  ControlType  = "Text",
  Count        = 1,
  DefaultValue = "admin",
  UserPin      = true,
  PinStyle     = "Both"
})
table.insert(ctrls, {
  Name         = "Password",
  ControlType  = "Text",
  Count        = 1,
  DefaultValue = "",
  UserPin      = true,
  PinStyle     = "Both"
})
table.insert(ctrls, {
  Name         = "Port",
  ControlType  = "Knob",
  ControlUnit  = "Integer",
  DefaultValue = 1710,
  Min          = 0,
  Max          = 65535,
  Count        = 1,
  UserPin      = true,
  PinStyle     = "Both"
})

-- Runtime control --
table.insert(ctrls, {
  Name         = "LoadComponents",
  ControlType  = "Button",
  ButtonType   = "Trigger",
  PinStyle     = "Input",
  UserPin      = true,
  Count        = 1
})

table.insert(ctrls, {
  Name         = "StringToSend",
  ControlType  = "Text",
  Count        = 1,
  DefaultValue = "",
  UserPin      = true,
  PinStyle     = "Both"
})

-- Status Controls --
table.insert(ctrls, {
  Name          = "Status",
  ControlType   = "Indicator",
  IndicatorType = Reflect and "StatusGP" or "Status",
  PinStyle      = "Output",
  UserPin       = true,
  Count         = 1
})
table.insert(ctrls, {
  Name          = "Connected",
  ControlType   = "Indicator",
  IndicatorType = "Led",
  Count         = 1,
  UserPin       = true,
  PinStyle      = "Output"
})
table.insert(ctrls, {
  Name          = "LoggedIn",
  ControlType   = "Indicator",
  IndicatorType = "Led",
  Count         = 1,
  UserPin       = true,
  PinStyle      = "Output"
})
table.insert(ctrls, {
  Name          = "LoginRequired",
  ControlType   = "Indicator",
  IndicatorType = "Led",
  Count         = 1,
  UserPin       = true,
  PinStyle      = "Output"
})
table.insert(ctrls, {
  Name         = "Platform",
  ControlType  = "Text",
  PinStyle     = "Output",
  UserPin      = true,
  Count        = 1
})
table.insert(ctrls, {
  Name         = "DesignName",
  ControlType  = "Text",
  PinStyle     = "Output",
  UserPin      = true,
  Count        = 1
})

--  Components --
table.insert(ctrls, {
  Name         = "LocalComponents",
  ControlType  = "Text",
  Style        = "ComboBox",
  PinStyle     = "Both",
  UserPin      = true,
  Count        = props['Component Count'].Value
})
table.insert(ctrls, {
  Name         = "RemoteComponents",
  ControlType  = "Text",
  Style        = "ComboBox",
  PinStyle     = "Both",
  UserPin      = true,
  Count        = props['Component Count'].Value
})
table.insert(ctrls, {
  Name         = "CommonComponents",
  ControlType  = "Text",
  Style        = "ComboBox",
  PinStyle     = "Both",
  UserPin      = true,
  Count        = props['Component Count'].Value
})
table.insert(ctrls, {
  Name         = "LocalControls",
  ControlType  = "Text",
  Style        = "ListBox",
  PinStyle     = "Output",
  UserPin      = true,
  Count        = props['Component Count'].Value
})
table.insert(ctrls, {
  Name         = "RemoteControls",
  ControlType  = "Text",
  Style        = "ListBox",
  PinStyle     = "Output",
  UserPin      = true,
  Count        = props['Component Count'].Value
})
table.insert(ctrls, {
  Name         = "CommonControls",
  ControlType  = "Text",
  Style        = "ListBox",
  PinStyle     = "Output",
  UserPin      = true,
  Count        = props['Component Count'].Value
})