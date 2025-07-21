local CurrentPage = PageNames[props["page_index"].Value]

local colors = {  
  Background  = {232,232,232},
  Transparent = {255,255,255,0},
  Text        = {24,24,24},
  Header      = {0,0,0},
  Button      = {48,32,40},
  Red         = {217,32,32},
  DarkRed     = {80,16,16},
  Green       = {32,217,32},
  OKGreen     = {48,144,48},
  Blue        = {32,32,233},
  Black       = {0,0,0},
  White       = {255,255,255},
  Gray        = {96,96,96},
  LightGray   = {194,194,194}
}

layout["code"]={PrettyName="code",Style="None"}

if(CurrentPage == 'Setup') then
  table.insert(graphics,{Type="GroupBox",Text="Connect",Fill=colors.Background,StrokeWidth=1,CornerRadius=4,HTextAlign="Left",Position={5,5},Size={400,120}})
  --table.insert(graphics,{Type="Image",Image=logo,Position={230,45},Size={170,34}})

  -- User defines connection properties
  table.insert(graphics,{Type="Text",Text="IP Address"    ,Position={ 15,35},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["IPAddress"] = {PrettyName="Settings~IP Address" ,Position={120,35},Size={100,16},Style="Text",Color=colors.White,FontSize=12}

  table.insert(graphics,{Type="Text",Text="Username"      ,Position={ 15,55},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["Username"] = {PrettyName="Settings~Username"    ,Position={120,55},Size={100,16},Style="Text",Color=colors.White,FontSize=12}
  
  table.insert(graphics,{Type="Text",Text="Password"      ,Position={ 15,75},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["Password"] = {PrettyName="Settings~Password"    ,Position={120,75},Size={100,16},Style="Text",Color=colors.White,FontSize=12}

  table.insert(graphics,{Type="Knob",Text="Port"          ,Position={ 15,95},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["Port"] = {PrettyName="Settings~Port"            ,Position={120,95},Size={100,16},Style="Text",Color=colors.White,FontSize=12}

  table.insert(graphics,{Type="Text",Text="Connected"           ,Position={224,35},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["Connected"] = {PrettyName="Settings~Connected"        ,Position={324,35},Size={16,16},Style="Led",Color=colors.Green}

  table.insert(graphics,{Type="Text",Text="Login required"      ,Position={224,55},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["LoginRequired"] = {PrettyName="Settings~LoginRequired",Position={324,55},Size={16,16},Style="Led",Color=colors.Blue}

  table.insert(graphics,{Type="Text",Text="LoggedIn"            ,Position={224,75},Size={100,16},FontSize=14,HTextAlign="Right"})
  layout["LoggedIn"] = {PrettyName="Settings~LoggedIn"          ,Position={324,75},Size={16,16},Style="Led",Color=colors.Blue}

  -- Status fields updated upon connect
  table.insert(graphics,{Type="GroupBox",Text="Status",Fill=colors.Background,StrokeWidth=1,CornerRadius=4,HTextAlign="Left",Position={5,135},Size={400,85}})
  layout["Status"] = {PrettyName="Status~Connection Status", Position={40,165}, Size={330,32}, Padding=4 }
  table.insert(graphics,{Type="Text",Text=GetPrettyName(),Position={15,200},Size={380,14},FontSize=10,HTextAlign="Right", Color=colors.Gray})

elseif(CurrentPage == 'System') then 
  --table.insert(graphics,{Type="Text",Text="Load components"         ,Position={ 10,  5},Size={135, 16},FontSize=14,HTextAlign="Left"})
  --layout["LoadComponents"] = {PrettyName="Settings~LoadComponents"  ,Position={146,  5},Size={ 36, 16},FontSize=12,Style="Button"}
  table.insert(graphics,{Type="Text",Text="Debug Function"          ,Position={ 10, 21},Size={135, 16},FontSize=14,HTextAlign="Left"})
  layout["DebugFunction"] = {PrettyName="Settings~DebugFunction"    ,Position={146, 21},Size={ 36, 16},FontSize=12,Style="Button"}
  table.insert(graphics,{Type="Text",Text="Debug Tx"                ,Position={ 10, 37},Size={135, 16},FontSize=14,HTextAlign="Left"})
  layout["DebugTx"] = {PrettyName="Settings~DebugTx"                ,Position={146, 37},Size={ 36, 16},FontSize=12,Style="Button"}
  table.insert(graphics,{Type="Text",Text="Debug Rx"                ,Position={ 10, 53},Size={135, 16},FontSize=14,HTextAlign="Left"})
  layout["DebugRx"] = {PrettyName="Settings~DebugRx"                ,Position={146, 53},Size={ 36, 16},FontSize=12,Style="Button"}
 
elseif(CurrentPage == 'Devices') then
  local columns_ = {
    {Title="Local components" , Id="LocalComponents" ,Position={ 10,  5}, Cell={Style="ComboBox"}},
    {Title="Remote components", Id="RemoteComponents",Position={154,  5}, Cell={Style="ComboBox"}},
    {Title="Common components", Id="CommonComponents",Position={298,  5}, Cell={Style="ComboBox"}},
    {Title="Local controls"   , Id="LocalControls"   ,Position={442,  5}, Cell={Style="ComboBox"}},
    {Title="Remote controls"  , Id="RemoteControls"  ,Position={586,  5}, Cell={Style="ComboBox"}},
    {Title="Common controls"  , Id="CommonControls"  ,Position={730,  5}, Cell={Style="ComboBox"}},
    --{Title="Sync"             , Id="SyncComponent"   ,Position={747,  5}, Cell={Style="Button"}},
  }
  local w = { Number  = 36, Text = 144, ComboBox = 144, ListBox = 144, Status  = 128, Button = 51, Led = 16 }
  local h = 28
  local x,y = 0,0
  table.insert(graphics,{Type="GroupBox",Text="Component selection",Position={x,y},Size={4, 4},FontSize=10,HTextAlign="Left",Fill={242,237,174},StrokeWidth=1,CornerRadius=4})
  local groupBoxId_ = #graphics
  x,y = 3, 26 -- anchor
  x=x+w.Number -- titles - start after the number column
  for _,v in ipairs(columns_) do
    local tbl_= {Type="Text",FontSize=11,HTextAlign="Left"}
    tbl_.Text=v.Title
    tbl_.Position={x, y}
    tbl_.Size={w[v.Cell.Style],h}
    table.insert(graphics,tbl_)
    x = x + tbl_.Size[1]
  end
  y=y+h -- new row
  local h = 16
  for i=1, props['Component Count'].Value do
    x = 3 -- reset x anchor
    table.insert(graphics,{Type="Text",Text=tostring(i),Position={x,y},Size={w.Number,h},FontSize=12,HTextAlign="Center"})
    x=x+w.Number -- start after the number column
    for _,v in ipairs(columns_) do
      local tbl_ = {}
      for i1,v1 in pairs(v.Cell) do tbl_[i1]=tbl_[v1] end
      tbl_.Style = v.Cell.Style -- this is done in the line above but repeated here because it wasn't working
      tbl_.PrettyName = "Device "..i.."~"..v.Id
      tbl_.Position={x,y}
      tbl_.Size={w[v.Cell.Style],h}
      tbl_.FontSize=12
      layout[v.Id..' '..i] = tbl_
      x = x + tbl_.Size[1]
    end
    y=y+h -- new row
  end
  graphics[groupBoxId_].Size={x+h, y+2*h}

end
