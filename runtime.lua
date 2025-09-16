-----------------------------------------------------------------------------------------------------------------------
-- dependencies
-----------------------------------------------------------------------------------------------------------------------
rapidjson = require "rapidjson"
-----------------------------------------------------------------------------------------------------------------------
-- Variables
-----------------------------------------------------------------------------------------------------------------------
local DebugTx=Controls.DebugTx.Boolean
local DebugRx=Controls.DebugRx.Boolean
local DebugFunction=Controls.DebugFunction.Boolean
local DebugPrint = Properties["Debug Print"].Value
local DebugPattern = '^Enable' --'^Selector 0' --'%.*'--'invert' -- sometimes i want to pick a single control type to debug and not see the rest
-----------------------------------------------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------------------------------------------
-- A function to determine common print statement scenarios for troubleshooting
-- A function to determine common print statement scenarios for troubleshooting
function SetupDebugPrint()
  if Properties["Debug Print"].Value=="Tx/Rx" then
    DebugTx,DebugRx=true,true
  elseif Properties["Debug Print"].Value=="Tx" then
    DebugTx=true
  elseif Properties["Debug Print"].Value=="Rx" then
    DebugRx=true
  elseif Properties["Debug Print"].Value=="Function Calls" then
    DebugFunction=true
  elseif Properties["Debug Print"].Value=="All" then
    DebugTx,DebugRx,DebugFunction=true,true,true
    --DebugTx,DebugFunction=true,true,true
  end
  Controls.DebugFunction.Boolean = DebugFunction
  Controls.DebugTx.Boolean = DebugTx
  Controls.DebugRx.Boolean = DebugRx

  Controls.DebugFunction.EventHandler = function(ctl) DebugFunction = ctl.Boolean end
  Controls.DebugTx.EventHandler = function(ctl) DebugTx = ctl.Boolean end
  Controls.DebugRx.EventHandler = function(ctl) DebugRx = ctl.Boolean end
end
SetupDebugPrint()

obj = {}
obj.TablePrint = function(tbl, indent)
  if not indent then indent = 0 end 
  --print('TablePrint type.'..type(tbl))
  
  local function LinePrint(k,v)
      --print('LinePrint - type.'..type(v))
      formatting = string.rep("  ", indent) .. k .. ": "
      if type(v) == "table" then
          print(formatting)
          obj.TablePrint(v, indent+1)
      elseif type(v) == 'string' or type(v) == 'boolean' or type(v) == 'number' then
          print(formatting .. tostring(v))
      --elseif type(v) == 'userdata' then
      else
          print(formatting .. 'Type.'..type(v))
      end
  end

  if type(tbl) == "table" then
      for k, v in pairs(tbl) do LinePrint(k,v) end
  elseif type(tbl) == "userdata" then
      --for k, v in ipairs(tbl) do LinePrint(k,v) end
      --print(table.concat)
      local success, err = pcall(function() print(tostring(tbl)) for k, v in pairs(tbl) do LinePrint(k,v) end end)
      --print('33 TablePrint type.'..type(tbl))
      --pcall(function() for k, v in ipairs(tbl) do LinePrint(k,v) end end)
  elseif type(tbl) == "string" then
      LinePrint('Type.'..type(tbl), tbl)
  else
      print('TablePrint Type.'..type(tbl))
  end
end

function deep_copy(orig, copies)
  copies = copies or {}
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
      if copies[orig] then
          copy = copies[orig]
      else
          copy = {}
          copies[orig] = copy
          for orig_key, orig_value in next, orig, nil do
              copy[deep_copy(orig_key, copies)] = deep_copy(orig_value, copies)
          end
          setmetatable(copy, deep_copy(getmetatable(orig), copies))
      end
  else -- number, string, boolean, etc
      copy = orig
  end
  return copy
end
-----------------------------------------------------------------------------------------------------------------------
-- Remote Q-Sys control functions
-----------------------------------------------------------------------------------------------------------------------
local messageId = 1

socket = TcpSocket.New()
BufferTimer = Timer.New()
local BufferTime = 0.001 -- 0.001 adjust to how fast the system can handle data
local rxBuffer = ''
local rxLock = false

local txBuffer = ''
local txLock = false

SyncComponentTimer = Timer.New()
local SyncComponentTime = 0.01 -- 0.01 adjust to how fast the system can handle processing
local SyncComponentQueue = {}
local SyncComponentLock = false

local subscriber = {}
local subscribersBuffer = ''
local subscribersLock = false

local StatusState = { OK = 0, COMPROMISED = 1, FAULT = 2, NOTPRESENT = 3, MISSING = 4, INITIALIZING = 5 }

local rapidjson = require 'rapidjson'

local commandQueue = {}
local queueBusy = false

local messageIDs = {}
local LocalComponents  = {} -- the components on the local system gathered by Component.New()
local LocalControls    = {}   -- The controls on the local system gathered by Component.GetControls(cmp)
local LocalCodeBackup  = {} -- 'code' on local components backed up and restored when the ClearLocalCode control is toggle
local RemoteComponents = {}
local RemoteControls   = {} -- e.g. RemoteControls['Mic1']['gain'] = {"Name":"bypass","Value":false}
local RemoteSubscriptions = {}
local LocalSelectors  = {} -- e.g. LocalSelectors['Mic1'] = { 1,2 } -- meaning Controls.RemoteComponents[1]=='Mic1' and RemoteComponents[2]=='Mic1'
local RemoteSelectors = {} 
local ChangeGroup = tostring(math.random(255))
local AutoPollInitiated = false
local PollRate = 0.5 -- lower this to 0.5 when it all works

local function getTableAndRaw(data) --data={table={},string=''}
  --print('getTableAndRaw type: '..type(data))
  --print('getTableAndRaw: '..rapidjson.encode(data))
  local str_ = data.string and data.string or rapidjson.encode(data.table)
  local tbl_ = data.table  and data.table  or rapidjson.decode(data.string)
  --print('getTableAndRaw done: '..rapidjson.encode(data))
  return tbl_, str_
end

function Dequeue(queue, busy)
  if busy~=nil then queueBusy = busy end
  if not queueBusy and #queue > 0 and socket.IsConnected and (Controls.LoggedIn.Boolean or not Controls.LoginRequired.Boolean) then
    --if DebugFunction then print('Dequeue() size: '..#queue) end
    queueBusy = true
    local item_ = table.remove(queue, 1) -- item = { func:{}, params:{}}
    local tbl_, str_ = getTableAndRaw(item_.params)
    if false then --DebugFunction then 
      print('Dequeueing: '..(tbl_.method and 'method: '..tbl_.method or ''))
      print('Dequeueing #params: '..#item_.params) 
    end
    item_.func(item_.params and (#item_.params>1 and table.unpack(item_.params) or item_.params) or nil)
  else
    --if DebugFunction then print('Dequeue() size: '..#queue..', not ready') end
  end
  --if DebugFunction then print('Dequeue done size: '..#queue) end
end

function Enqueue(queue, data) -- data = { func:{}, params:{}}
  local tbl_, str_ = getTableAndRaw(data.params)
  --if DebugFunction then print('Enqueue size '..(#queue+1)..(tbl_.method and ', method '..tbl_.method or '')) end
  queue[#queue+1] = data
  Dequeue(queue)
end

function TrackSubscription(data, raw) -- keep track of which scripts requested subscriptions to return data to them
  --if DebugFunction then print('TrackSubscription() #raw: '..#raw) end
  if data then
    if data.jsonrpc then 
      if data.id then
        --if DebugFunction then print('value.id: '..data.id) end --'BGM zone source assign-18'
        local localComponentId_, messageId_ = string.match(data.id, "(.*)%-(%d+)")
        if DebugFunction then print('TrackSubscription() local Component id: "'..localComponentId_..'", messageId: '..messageId_..'", method: '..data.method) end -- 'BGM zone source assign'
        if data.method == 'ChangeGroup.AddComponentControl' then 
          local remoteComponentId_ = data.params.Component.Name
          if DebugFunction then print('TrackSubscription() remote Component id: "'..remoteComponentId_..'"') end
          if not subscriber[localComponentId_] then subscriber[localComponentId_] = {} end
          if DebugFunction then print('Adding subscriber. [local: "'..localComponentId_..'"][remote: "'..remoteComponentId_..'"] = value =>(Id: "'..data.params.Id..'"", name: "'..data.params.Component.Name..'" #controls: '..#data.params.Component.Controls..'")') end
          if subscriber[localComponentId_][remoteComponentId_] and subscriber[localComponentId_][remoteComponentId_].params.Component.Controls then
            for _,v in ipairs(data.params.Component.Controls) do -- avoid duplicates
              local found_ = false
              for _,v1 in ipairs(subscriber[localComponentId_][remoteComponentId_].params.Component.Controls) do 
                if v.Name == v1.Name then found_ = true break end
              end
              if not found_ then
                if DebugFunction then print('Adding subscriber control "'..v.Name..'"') end
                table.insert(subscriber[localComponentId_][remoteComponentId_].params.Component.Controls, v)
              end
            end            
          else 
            if DebugFunction then print('Adding subscriber table') end
            subscriber[localComponentId_][remoteComponentId_] = data --data.params.Component.Controls
          end
        end
      end
    end
  end
end

function GetRxBufferBlock() -- need to use global buffer
  local str = rxBuffer
  --print('GetRxBufferBlock(#'..#str..')')
  local first_json_pos = str:find("[%[{]") -- Trim garbage before the first `{` or `[`
  --print('first_json_pos: '..first_json_pos)
  if not first_json_pos then -- No possible JSON in buffer, discard everything
    --print('No possible JSON in rxBuffer:\n'..rxBuffer)
    rxBuffer = ""
    return nil, nil, "No possible JSON in rxBuffer:\n"..rxBuffer
  elseif first_json_pos > 1 then
    str = str:sub(first_json_pos) -- Trim leading garbage
    rxBuffer = str
    --if DebugFunction then print('GetRxBufferBlock lead trimmed '..first_json_pos..', new buffer size #'..#rxBuffer) end
  end
  
  local start, finish, candidate = str:find("(%b{})")  -- Try to find the first balanced JSON object or array
  if not candidate or start > 1 then
    start, finish, candidate = str:find("(%b[])")
  end
  if not candidate or start > 1  then return nil, nil, "Incomplete json block" end
  --print('GetRxBufferBlock start:'..start..', finish: '..finish)
  --print('candidate(#'..#candidate..')\n'..candidate)
  finish = finish+1
  if #rxBuffer==finish then rxBuffer = ''
  else                      rxBuffer = str:sub(finish) end
  local decoded = rapidjson.decode(candidate)  -- Try decoding to check if it's valid JSON
  if decoded then -- Remove the matched block from the buffer
    --print('GetRxBufferBlock matched new(#'..#rxBuffer..')')
    --return decoded, candidate
    return decoded, str:sub(start, finish)
  else -- If the match wasn't valid JSON, discard it and continue
    return nil, nil, "Invalid JSON"
  end
end

function GetSubscribersBufferBlock() -- need to use global subscribersBuffer
  local str = subscribersBuffer
  --print('GetSubscribersBufferBlock(#'..len..')')  
  local first_json_pos = str:find("[%[{]") -- Trim garbage before the first `{` or `[`
  if not first_json_pos then -- No possible JSON in buffer, discard everything
    print('No possible JSON in buffer:\n'..buffer)
    subscribersBuffer = ""
    return nil, nil, "No possible JSON in buffer"
  elseif first_json_pos > 1 then
    str = str:sub(first_json_pos) -- Trim leading garbage
    subscribersBuffer = str
  end

  local start, finish, candidate = str:find("(%b{})")  -- Try to find the first balanced JSON object or array
  if not candidate or start > 1 then
    start, finish, candidate = str:find("(%b[])")
  end
  if not candidate or start > 1  then return nil, nil, "Incomplete json block" end
  local decoded = rapidjson.decode(candidate)  -- Try decoding to check if it's valid JSON
  if decoded then -- Remove the matched block from the buffer
    subscribersBuffer = str:sub(finish + 1)
    return decoded, candidate
  else -- If the match wasn't valid JSON, discard it and continue
    subscribersBuffer = str:sub(finish + 1)
    return nil, nil, "Invalid JSON"
  end
end

local function Write(data) --data={table={},string=''}
  --print('write() type: '..type(data))
  local tbl_, str_ = getTableAndRaw(data)
  --print('Write'..(tbl_.method and ', method '..tbl_.method or ''))
  if socket.IsConnected then
    local tbl_, str_ = getTableAndRaw(data)
    messageIDs[data.table.id] = tbl_
    if DebugTx then print("Tx: "..str_) end
    socket:Write(str_..'\n\r\x00')
  elseif DebugFunction then print("DIDN'T SEND DATA - NO CONNECTION TO HOST") end
end

function EnqueueData(method, params)
  --if DebugFunction and socket.IsConnected then print('EnqueueData( method: '..method..', params: '..(params and rapidjson.encode(params) or {})) end
  local params_ = params or ''
  messageId = messageId+1
  local data_ = {
      ['jsonrpc'] = '2.0',
      ['id'] = messageId,
      ['method'] = method,
      ['params'] = params_
  }
  local tbl_ = {['table']=data_} 
  messageIDs[messageId] = tbl_ -- add message id for comparing rx
  if false then --DebugFunction then 
    print('Added messageIDs['..messageId..']')
    print('id:'..tbl_['table'].id)
  end
  --local t_,s_ = getTableAndRaw(tbl_)
  Enqueue(commandQueue, { func=Write, params=tbl_ })
end

local function ProcessSubscribersBuffer()
  if not subscribersLock and #subscribersBuffer>0 and socket.IsConnected and (Controls.LoggedIn.Boolean or not Controls.LoginRequired.Boolean) then
    subscribersLock = true
    while #subscribersBuffer>0 do
      --if DebugFunction then print('GetSubscribersBufferBlock() buffer: '..#subscribersBuffer..' bytes') end
      local tbl, raw, err = GetSubscribersBufferBlock()
      if DebugFunction then print('GetSubscribersBufferBlock() done, buffer: '..#subscribersBuffer..' bytes') end
      if not tbl then break end
      TrackSubscription(tbl, raw)
      if socket.IsConnected and tbl.id then 
        print('storing message id: '..tbl.id)
        messageIDs[tbl.id] = tbl 
      end
      Enqueue(commandQueue, {func=Write, params={['table']=tbl, ['string']=raw}})
    end
    subscribersLock = false
  end
end

function array_intersection(table1, table2) -- returns the intersection of two arrays (elements present in both)
  local lookup = {}
  local result = {}
  local index = 1
  for _, value in ipairs(table1) do lookup[value] = true end -- Create lookup table from table1
  -- Check table2 elements against lookup, avoid duplicates
  local seen = {}
  for _, value in ipairs(table2) do
    if lookup[value] and not seen[value] then
      seen[value] = true
      result[index] = value
      index = index + 1
    end
  end
  return result
end

local sysControlNames = { 'log.%w', 'script.%w', 'halt.%w', 'magic.number', 'reload' }  
local sysControlProps = { 'Name', 'Component', 'Direction', 'Type' }  
local function isInvalid(val, invalid_values)
  for _,v in ipairs(invalid_values) do
    if val==v or val:match(v) then return true end
  end
end 

local function UpdateCommonControls(i)
  print('UpdateCommonControls('..(i or '')..')')
  local remote_name = Controls.RemoteComponents[i].String
  --local max = 8880 -- Max execution error at this amount of comparisons
  print('UpdateCommonControls('..i..') "'..remote_name..'", local controls: '..#Controls.LocalControls[i].Choices)
  local choices = {[1]= ''}
  local lookup = {}
  for _,v in pairs(Controls.LocalControls[i].Choices) do 
    if v~='' then lookup[v] = true end -- Create lookup table
  end
  local seen = {} -- avoid repeats
  for _,v in ipairs(Controls.RemoteControls[i].Choices) do
    if v~='' and lookup[v] and not seen[v] then
      seen[v] = true
      table.insert(choices, v)
    end
  end
  if DebugFunction then print('found '..#choices..' common controls') end

  Controls.CommonControls[i].String = ''
  Controls.CommonControls[i].Choices = choices

  if #remote_name>0 then
    if not RemoteSubscriptions[remote_name] then 
      if DebugFunction then print('Creating RemoteSubscriptions["'..remote_name..']') end
      RemoteSubscriptions[remote_name] = {} 
    else
      if DebugFunction then 
        if #RemoteSubscriptions[remote_name]==0 then
        local count=0
          for i1,v1 in pairs(RemoteSubscriptions[remote_name]) do
            print('RemoteSubscriptions["'..remote_name..'"]['..i1..']: '..tostring(v1))
            count=count+1
          end
          print('RemoteSubscriptions["'..remote_name..'"] has existing '..count..' controls')
        else
          print('RemoteSubscriptions["'..remote_name..'"] has existing '..#RemoteSubscriptions[remote_name]..' controls')
        end
      end
    end
    local remote_controls = {}
    for _,v in ipairs(choices) do -- only subscribe to controls if not already subscribed and they are not system controls
      if v~='' and not RemoteSubscriptions[remote_name][v] then
        if v=='code' and not Controls.EnablePullingCode.Boolean then
          if DebugFunction then print('Not adding RemoteSubscriptions["'..remote_name..'"]["'..v..'"]') end
        elseif isInvalid(remote_name, sysControlNames) then
          if DebugFunction then print('Not adding RemoteSubscriptions["'..remote_name..'"]["'..v..'"]') end
        else
          --if DebugFunction then print('Adding RemoteSubscriptions["'..remote_name..'"]["'..v..'"]') end
          table.insert(remote_controls, {["Name"]=v})
        end
      else
        --if DebugFunction then print('RemoteSubscriptions["'..remote_name..'"]["'..v..'"] already subscribed') end
      end
    end
    -- subscribe to controls 
    if DebugFunction then print('Subscribing to remote['..i..'] "'..remote_name..'" of '..#remote_controls..' remote controls from '..#choices..' common controls') end
    if #remote_controls>0 then
      EnqueueData('ChangeGroup.AddComponentControl', {
        ["Id"]=ChangeGroup, 
        ["Component"]={
          ["Name"]=remote_name,
          ["Controls"]=remote_controls
        }
      })
      if not AutoPollInitiated then
        EnqueueData('ChangeGroup.AutoPoll', {
          ["Id"]=ChangeGroup, 
          ["Rate"]=PollRate
        })
      end
    end
  end 
end

local function SyncControl(component_name, control_name) 
  if control_name then
    if control_name:match(DebugPattern) then print('SyncControl('..component_name..', '..control_name..')') end
    if (control_name=='code' and not Controls.EnablePullingCode.Boolean) then 
      --print('Not synching control: "code"')
    elseif isInvalid(control_name, sysControlNames) then
      --print('Not Synching a system control: "'..control_name..'"')
    else
      for _,j in pairs(RemoteSelectors[component_name]) do
        local local_ = Component.New(Controls.LocalComponents[j].String)
        for k,v in pairs(RemoteControls[component_name][control_name]) do 
          if not isInvalid(k, sysControlProps) then 
            local success, msg = pcall(function() 
              --print('~~~ '..' synching ['..localName_..']['..control_name..']['..k..']: '..v)
              if local_[control_name][k] then
                if DebugFunction then 
                  --print('Updating LocalComponents["'..component_name..'"]["'..control_name..'"]["'..k..'"]: '..(type(v)=='table' and table.concat(v,",") or tostring(v))) 
                  if control_name:match(DebugPattern) and k=='Choices' then
                    --print(string.rep('*',35)..' synching:\n    ['..component_name..']['..control_name..']['..k..']: '..(type(v)=='table' and ('\n    ['..table.concat(v,",")) or ('['..tostring(v)))..']')
                  end
                end
                local_[control_name][k] = v
              end
            end) --pcall because sometimes an unexpected Property does not exist on Control (such as 'Indeterminate', 'Invisible', 'Disabled')
            --if not success and DebugFunction then print('local "'..control_name..'"["'..k..'"] error\n'..msg) end
          end 
        end
      end 
    end
  end
end

local function SyncComponents()
  if DebugFunction then print('SyncComponents('..(remote_name or '')..')') end 
  
  local function SyncNexItem()
    --if DebugFunction then print('SyncNexItem()') end
    local componentsEmpty = true
    if not SyncComponentLock then
      for componentName,componentVal in pairs(SyncComponentQueue) do -- look for components to be updated
        componentsEmpty = false
        local controlsEmpty = true
        for controlName,controlVal in pairs(componentVal) do -- look for a control to be updated
          controlsEmpty = false
          SyncComponentLock = true
          SyncControl(componentName, controlName)
          --if DebugFunction then print('Clearing SyncComponentQueue['..componentName..']['..controlName..']') end
          SyncComponentQueue[componentName][controlName] = nil -- remove the control from the queue when synched
          if SyncComponentQueue[componentName][controlName] then
            print('ERROR SyncComponentQueue['..componentName..']['..controlName..'] IS NOT CLEAR')
          end
          SyncComponentLock = false
          break
        end
        if controlsEmpty then 
          if DebugFunction then print('Clearing SyncComponentQueue['..componentName..']') end
          SyncComponentQueue[componentName]=nil
          if SyncComponentQueue[componentName] then
            if DebugFunction then print('ERROR SyncComponentQueue['..componentName..'] IS NOT CLEAR') end
          end
        end
        break
      end
      if componentsEmpty then 
        if DebugFunction then print('SyncComponentQueue is empty, stopping timer') end
        SyncComponentTimer:Stop() 
      end
    else
      if DebugFunction then print('SyncNexItem is busy') end
    end 
  end
 
  --if DebugFunction then print('SyncComponentTimer is '..(SyncComponentTimer:IsRunning() and '' or 'not ')..'running') end
  if not SyncComponentTimer:IsRunning() then
    --if DebugFunction then print('Starting SyncComponentTimer') end
    SyncComponentTimer.EventHandler = SyncNexItem
    SyncComponentTimer:Start(SyncComponentTime)
  end 
end

local function UpdateCommonComponents(remote) -- remote is RemoteComponents
  if DebugFunction then print('UpdateCommonComponents') end
 	local choices = { [1]='' }
  local common = {} 
	for i,v in pairs(remote) do 
    --if DebugFunction then print(i..': '..v.Name) end
    local local_ = Component.New(v.Name)
    if #Component.GetControls(local_)>0 then
      table.insert(choices, v.Name)
    end
	end
	for i=1, Properties['Component Count'].Value do Controls.CommonComponents[i].Choices = choices end
end

local function HandleRemoteControlsData(data) --{"Name":"FunctionMicGain_1","Controls":[{"Name":"bypass","Type":"Boolean","Value":false,"String":"no","Position":0.0,"Direction":"Read/Write"},{"Name":"gain","Type":"Float","Value":0.0,"ValueMin":-21.0,"ValueMax":0.0,"StringMin":"-21.0dB","StringMax":"0dB","String":"0dB","Position":1.0,"Direction":"Read/Write"},{"Name":"invert","Type":"Boolean","Value":false,"String":"normal","Position":0.0,"Direction":"Read/Write"},{"Name":"mute","Type":"Boolean","Value":true,"String":"muted","Position":1.0,"Direction":"Read/Write"}]}
  if type(data)~='table' then
    if DebugFunction then  print("HandleRemoteControlsData, invalid data type: "..type(data)) end
  else
    if DebugFunction then print('HandleRemoteControlsData["'..data.Name.. '"] has '..#data.Controls..' controls') end
    local choices = { [1]= '' }
    if not RemoteControls[data.Name] then RemoteControls[data.Name] = {} end
    if not SyncComponentQueue[data.Name] then SyncComponentQueue[data.Name] = {} end

    if DebugFunction then print('iterating through '..#data.Controls.. ' data.Controls') end
    for i,j in ipairs(data.Controls) do
      RemoteControls[data.Name][j.Name] = j -- replace indexes with names. e.g. RemoteControls['Mic1']['gain'] = {"Name":"bypass","Value":false}
      SyncComponentQueue[data.Name][j.Name] = j -- add to queu for updating 
      table.insert(choices, j.Name) 
      if DebugFunction then
        --print(string.rep('*',35)..'\nPopulating RemoteControls["'..data.Name..'"]['..j.Name..']: '..tostring(j.Value)) 
      end
    end
    
    if DebugFunction then print('iterating through '..#RemoteSelectors[data.Name].. ' RemoteSelectors[data.Name]') end 
    if RemoteSelectors[data.Name] and #RemoteSelectors[data.Name]>0 then --RemoteSelectors[data.Name]=={ 1,2 } meaning Controls.RemoteComponents[1]==data.Name and RemoteComponents[2]==data.Name
      for i,j in ipairs(RemoteSelectors[data.Name]) do
        if Controls.RemoteComponents[j].String == data.Name then -- this line shouldn't be necessary
          if DebugFunction then print('Populating Controls.RemoteComponents['..j..'].Choices with RemoteControls["'..data.Name..'"]') end
          Controls.RemoteControls[j].Choices = choices
        end
      end
      UpdateCommonControls(RemoteSelectors[data.Name][1])
      SyncComponents()
    end
  end
end

local function HandleRemoteComponentsData(data) -- [{"Name": "APM ABC", "Type": "apm", "Properties":[{"Name": "multi_channel_type","Value": "1"},]},]
	if DebugFunction then print('HandleRemoteComponentsData, found '..(data==nil and 'no data' or #data..' RemoteComponents')) end
  if data~=nil then
    RemoteComponents = data
    local choices = { [1]='' }
    for _, v in ipairs(data) do table.insert(choices, v.Name) end
    for i=1, Properties['Component Count'].Value do Controls.RemoteComponents[i].Choices = choices end
    UpdateCommonComponents(RemoteComponents)
  end
end

local function HandleRemoteSubscriptionData(result, message)
	if DebugFunction then print('HandleRemoteSubscriptionData') end
  local comp_ = message.params.Component
	if DebugFunction then print('component: '..comp_.Name) end
  if not RemoteSubscriptions[comp_.Name] then RemoteSubscriptions[comp_.Name] = {} end
  for i,v in pairs(comp_.Controls) do
    if not RemoteSubscriptions[comp_.Name][v.Name] then
      --if DebugFunction then print('Remote subscription to "'..comp_.Name..'"["'..v.Name..'"] '..(result and 'Success' or 'Failed')) end
      RemoteSubscriptions[comp_.Name][v.Name] = result
    end
  end
end

local function UpdateLocalSubsriberScripts(change) -- subscriber scripts on this core
  for localScript_, subscribers_ in pairs(subscriber) do
    --print('  localScript_['..localScript_..']')
    -- subscriber[componentId][subscribers]         
    --[[ {"jsonrpc":"2.0","method":"ChangeGroup.Poll","params":{"Id":"1","Changes":[
            {"Component":"Zone1Gain","Name":"mute","String":"muted","Value":1.0,"Position":1.0},
            {"Component":"Zone1Gain","Name":"gain","String":"-15.6dB","Value":-15.55555343,"Position":0.6888889},
            {"Component":"Zone2Gain","Name":"mute","String":"muted","Value":1.0,"Position":1.0},
            {"Component":"Zone2Gain","Name":"gain","String":"0dB","Value":0.0,"Position":1.0}
          ]}}
    ]]--
    for i, subscriber_ in pairs(subscribers_) do 
      --print('   ['..localScript_..']['..i..']') -- localScript_ = 'BGM level controls' i = 'Zone1Gain'
      -- localScript_ == 'BGM zone source assign'
      -- subscriber_.params.Component.Name = 'BGM XFADE'
      -- subscriber_.params.Component.Controls[1].Name = 'InputSelect 1'
      if change.Component == subscriber_.params.Component.Name then --e.g. 'BGM XFADE', 'lighting'
        --if DebugFunction then log = log..'\n  Matched local component ['..change.Component..'], remote control ['..change.Name..']' end
        for _, v in ipairs(subscriber_.params.Component.Controls) do -- change.Name = 'mute', 'preset.3 1'
          --if DebugFunction then log = log..'\n   subscriber control: v.Name ['..v.Name..']' end
          if change.Name == v.Name then -- 'InputSelect 1' or 'mute'
            --if DebugFunction then log = log..'\n  Matched local: ['..localScript_..'], remote: ['..change.Component..']['..v.Name..']' end
            if not localUpdates_[localScript_] then
              localUpdates_[localScript_] = {
                ['jsonrpc'] = data.jsonrpc,
                ['method'] = data.method,
                ['params'] = { 
                  ['Id'] = id, 
                  ['Changes'] = {}
                }
              }
            end
            table.insert(localUpdates_[localScript_].params.Changes, change)
          end
        end
      end
    end
  end
end
--[[
local function UpdateLocalComponents(change) -- subscribers in this plugin
  if DebugFunction then print('UpdateLocalComponents(["'..change.Component..'"]["'..change.Name..'"])') end
  if RemoteSelectors[change.Component] then --RemoteSelectors[change.Component]=={ 1,2 } meaning Controls.RemoteComponents[1]==change.Component and RemoteComponents[2]==change.Componen
    if DebugFunction then print('RemoteSelectors["'..change.Component..'"] is defined in '..#RemoteSelectors[change.Component]..' sSelectors')
    for i,j in ipairs(RemoteSelectors[change.Component]) do
      if Controls.RemoteComponents[j].String == change.Component then -- this line shouldn't be necessary         
        if change.Name=='code' and not Controls.EnablePullingCode.Boolean then -- ignore script 'code'
          if DebugFunction then print('not synching ChangeGroup for RemoteComponents['..i..']["'..change.Component..'"]["'..change.Name..'"]') end
          elseif isInvalid(change.Name, sysControlNames) then
          --if DebugFunction then print('not synching ChangeGroup for RemoteComponents['..i..']["'..change.Component..'"]["'..change.Name..'"]') end
        else
          if i==1 then -- only do for first component, the others are pointing at the same component
            SyncComponents(change.Component) -- this runs through a timed queue to stop max executions
          end
        end
      end
    end
  end
end
]]--
      
local function HandleRemoteChangeGroupData(data)
  -- ChangeGroup.Poll doesn't include a data.id so need to figure out what subscriber scripts to send it to
  if DebugFunction then 
    --print('HandleRemoteChangeGroupData()\n method: '..data.method..', '..#data.params.Changes..' changes')
  end
  --{"jsonrpc":"2.0","method":"ChangeGroup.Poll","params":{"Id":"1","Changes":[]}}
  if #data.params.Changes > 0 then 
    if DebugFunction then print('HandleRemoteChangeGroupData() populating unique RemoteControls\n method: '..data.method..', '..#data.params.Changes..' changes') end
    for _, change_ in ipairs(data.params.Changes) do
      -- change_ = { "Component": "BGM XFADE", "Name": "InputSelect 1", "String": "BGM GLOBAL 1", .. }
      if DebugFunction then
        if change_.Name:match(DebugPattern) then
          print('Setting RemoteControls['..change_.Component..']['..change_.Name..']: '..tostring(change_)) 
        end
      end
      if not RemoteControls[change_.Component] then RemoteControls[change_.Component] = {} end
      RemoteControls[change_.Component][change_.Name] = change_
      if not SyncComponentQueue[change_.Component] then SyncComponentQueue[change_.Component] = {} end
      SyncComponentQueue[change_.Component][change_.Name] = change_
      UpdateLocalSubsriberScripts(change_)
    end
    SyncComponents()
  end
end

local function Logon(params)--Logon{ ['User'] = Controls.Username.String, ['Password'] = Controls.Password.String }
  --if DebugFunction then print('Logon, params: '..(params and rapidjson.encode(params) or '')) end
  local params_ = params or ''
  messageId = 1
  local data_ = {
      ['jsonrpc'] = '2.0',
      ['id'] = messageId,
      ['method'] = 'Logon',
      ['params'] = params_
  }  
  local tbl_ = {['table']=data_} 
  messageIDs[messageId] = tbl_ -- add message id for comparing rx
  Write(tbl_)
end 

local function LoggedIn(status)
  if status and not Controls.LoggedIn.Boolean then
    if DebugFunction then print('Login success, message queue size: '..#commandQueue) end
    Controls.LoggedIn.Boolean = true 
    queueBusy = false  
    ProcessSubscribersBuffer()
  end
end

function ParseResponse(data, raw) -- TODO: break this up onto smaller functions, best to create a table of method fiunctions to handle
  --{"jsonrpc":"2.0","id":"Script killer-186","error":{"code":10,"message":"Logon required"}}
  --{"jsonrpc":"2.0","method":"EngineStatus","params":{"Platform":"Core 110f","State":"Active","DesignName":"Gosford RSL CORE110F DEV V1.5.0 20250114","DesignCode":"srOW2FUZF3HC","IsRedundant":false,"IsEmulator":false,"Status":{"Code":4,"String":"Missing - 1 OK, 4 Compromised, 76 Missing"}}}
  local log = ''
  --raw = rapidjson.encode(data) -- raw is getting spurious data so uding 'data'
  --if DebugFunction then print('ParseResponse length: '..#raw..'\n'..raw) end
  if data then
    if data.jsonrpc then 
      --if DebugFunction then print('jsonrpc: '..data.jsonrpc) end
      if data.id then
        --if DebugFunction then log = log..'\n value.id: "'..data.id..'", type: '..type(data.id) end
        local componentId_, messageId_
        if type(data.id)=='number' then 
          messageId_ = data.id
        else
          componentId_, messageId_ = (data.id):match("^(.*)%-(%d+)") -- e.g. 'component name-1' is used for subscriptions
        end
        if componentId_ then -- subscription from a local component
          if DebugFunction then log = log..'\n component id: "'..componentId_..'", messageId: '..messageId_ end
          --if DebugFunction then print('component id: "'..componentId_..'", messageId: '..messageId_) end
          if data.error then
            if DebugFunction then log = log..'\n error code: "'..data.error.code..'", message: '..data.error.message end
            if data.error.code == 10 then --"error":{"code":10,"message":"Logon required"}
              Controls.LoginRequired.Boolean = true 
              Controls.LoggedIn.Boolean = false 
              print('LoginRequired, logging in')
              Logon({ User = Controls.Username.String, Password = Controls.Password.String })
            end
          else
            local component_ = Component.New(componentId_)
            if component_ and #Component.GetControls(component_)>0 then 
              if DebugFunction then log = log..'\n forwarding '..#raw..' bytes to: ["'..componentId_..'"].StringFromRemoteQSYS' end
              if DebugSubscribeTx then log = log..'\n'..raw end
              component_.StringFromRemoteQSYS.String = raw
            end
          end
				else -- sent from this plugin
          if DebugFunction then log = log..'\n response for this plugin, messageId: '..messageId_..', type: '..type(messageId_) end
					if messageIDs[messageId_] then
            local tbl_ = messageIDs[messageId_]
            if DebugFunction then
              log = log..', method:'..(tbl_.method or 'nil') 
              if data.result==nil then print(log..' data.result is nil') log='' end
              if tbl_.method==nil then print(log..' tbl_.method is nil') log='' end
            end
            if tbl_.method==nil then --
            elseif tbl_.method == "Logon" then 
              LoggedIn(data.result)
            elseif tbl_.method == "Component.GetControls" then 
              HandleRemoteControlsData(data.result)
            elseif tbl_.method == "Component.GetComponents" then 
              HandleRemoteComponentsData(data.result)
            elseif tbl_.method == "ChangeGroup.AddComponentControl" then
              HandleRemoteSubscriptionData(data.result, tbl_)
            elseif tbl_.method == "ChangeGroup.AutoPoll" then
              AutoPollInitiated = data.result
            elseif tbl_.method == "Component.Set" then 
              --HandleRemoteComponentSet(data.result) -- not handled. If it failed it'll sync on the next AutoPoll            
            else
              if DebugFunction then log = log..'\n message method "'..tbl_.method..'" not handled' end
            end
            table.remove(messageIDs[messageId_]) -- release resources
          end
        end
      end

      --if DebugFunction then print('type(value.result): '..type(data.result)) end
      if data.method then 
        if data.params then 
          --print('params:')
          if data.method == 'EngineStatus' then
            --if DebugFunction then log = log..' method: '..data.method end
            log = '' -- stop spamming this in the log
           for k,v in pairs(data.params) do
              if Controls[k] and type(v) == 'string' then Controls[k].String = v end
            end

          elseif data.method == 'ChangeGroup.Poll' then
            HandleRemoteChangeGroupData(data)
          else           
            if DebugFunction then log = log..'\n method: '..data.method end
          end
        else           
          if DebugFunction then log = log..'\n method: '..data.method end
        end 
      elseif type(data.result)=='nil' then
        if DebugFunction then log = log..'\n result: nil' end
      elseif type(data.result)=='boolean' then
        if DebugFunction then log = log..'\n result: '..tostring(data.result) end
        if data.result then  --{"jsonrpc":"2.0","result":true,"id":1}
          LoggedIn(data.result)
        end
      elseif data.result then
        if data.result.Name then
          --{"Name":"BGM zone source assign","Controls":[{"Name":"OutputName 1","String":"Staff Breakout","Value":0.0,"Position":0.0,"Choices":[],"Color":"","Indeterminate":false,"Invisible":false,"Disabled":false,"Legend":"","CssClass":""}
          if DebugFunction then 
            log = log..'\n Name: '..data.result.Name
            if data.result.Controls then 
              log = log..'\n #Controls: '..#data.result.Controls
            end
          end
        end
      end
    elseif data.Component then
      local componentId_ = data.Component
      if DebugFunction then log = log..'\n Remote component id: '..componentId_ end
      if subscriber[componentId_] then 
        if DebugFunction then log = log..'\n Existing subscriber' end
      else 
        for k,v in pairs(subscriber) do
          if v[componentId_] then
            if DebugFunction then log = log..'\n Local component: '..k  end
            --v.params.Component.Controls)
            componentId_ = k
          break end 
        end
      end
      local component_ = Component.New(componentId_)
      if #Component.GetControls(component_)>0 then 
        if DebugFunction then log = log..'\n sending '..#raw..' bytes to: ["'..componentId_..'"].StringFromRemoteQSYS' end
        if DebugSubscriberTx then log = log..'\n data: '..raw end
        component_.StringFromRemoteQSYS.String = raw
      end
    else
      if DebugFunction then log = log..'\njson snippet in buffer:\n'..raw end 
    end
    --print('clearing buffer')
		if data.id and messageIDs[data.id] then 
      --if DebugFunction then print('releasing message id: '..data.id) end
      table.remove(messageIDs[data.id])
    end -- release resources
    buffer = ''
    Dequeue(commandQueue, false) -- disable the busy flag 

  else 
    if DebugFunction then log = log..'\ninvalid json in buffer, waiting for more data' end
  end

  if DebugFunction and #log>0 then print(log) end
end

local function RemoteComponentSelectEvent(i)
  local ctl = Controls.RemoteComponents[i]
  if DebugFunction then
    print('RemoteComponentSelectEvent('..i..')')
    print('Controls.RemoteComponents['..i..'].String: '..Controls.RemoteComponents[i].String)
  end
  -- clear lookup table
  if not RemoteSelectors[ctl.String] then RemoteSelectors[ctl.String] = {} end
  for _,v in pairs(RemoteSelectors) do -- e.g. i==1 and RemoteSelectors['Mic1'] = { 1,2 }
    if v[i] then                      -- RemoteSelectors['Mic1'][1] exists
      v[i] = nil                      -- remove from table
    end
  end

  if ctl.String == '' then 
    Controls.RemoteControls[i].Choices = {}
    Controls.CommonControls[i].Choices = {}
  else
    local exists = false
    for _,v1 in ipairs(RemoteSelectors[ctl.String]) do
      if v1~=i and #Controls.RemoteComponents[v1].Choices>0 then
        ctl.Choices = Controls.RemoteComponents[v1].Choices
        exists = true
        print('Copying Controls.RemoteComponents['..i..'].Choices from existing Controls.RemoteComponents['..v1..'].Choices')
        break
      end
    end
    table.insert(RemoteSelectors[ctl.String], i) -- add lookup -- e.g. i==1 and RemoteSelectors['Mic1'] = { 1 }
    if not exists then EnqueueData('Component.GetControls', {["Name"]=ctl.String}) end
  end
end

local function LoggedOut()
  Controls.Platform.String = ''
  Controls.DesignName.String = ''
  Controls.LoggedIn.Boolean = false 
  commandQueue = nil -- clear queue
  commandQueue = {}
  RemoteSubscriptions = nil -- clear
  RemoteSubscriptions = {}
  AutoPollInitiated = false
end 

local function SocketClosed()
  ReportStatus("MISSING","Socket closed")
  LoggedOut()
end 
  
function Connect()
  if Controls.IPAddress.String == "" then
    --Controls.IPAddress.String = System.IsEmulating and "localhost" or Network.Interfaces()[1].Address
    Controls.IPAddress.String = Network.Interfaces()[1].Address
    if DebugFunction then print('IPAddress is empty, setting default: '..Controls.IPAddress.String) end
  end
  if Controls.Port.String == '0' or Controls.Port.String == '' then
    if DebugFunction then print('Port is zero, setting default: '..Controls.Port.String) end
    Controls.Port.Value = 1710
    --Controls.Port.String = '1710'
  end
  if DebugFunction then print('Connect('..Controls.IPAddress.String..':'..Controls.Port.String..') IsConnected: '..tostring(socket.IsConnected)) end
  if socket.IsConnected then
    LoggedOut()
    socket:Disconnect()
  end
  socket:Connect(Controls.IPAddress.String, Controls.Port.Value)
end 

local status = 'INITIALIZING'
function ReportStatus(state,msg)
  if status ~= StatusState[state] then --if Controls.Status.Value ~= StatusState[state] then
	  if DebugFunction then -- Controls.Status.Value doesn't update correctly so using a variable
      print("ReportStatus("..state..") "..(msg or ''))
    end
	end
  local msg=msg or ""
	Controls.Status.String = msg
	Controls.Status.Value = StatusState[state]
  status = StatusState[state]
  Controls.Connected.Boolean = socket.IsConnected
  if not socket.IsConnected then Controls.LoggedIn.Boolean = false end
end

socket.Connected = function(sock)
  ReportStatus("OK","")
  if #Controls.Username.String > 0 then
    Controls.LoginRequired.Boolean = true 
    Logon({ ['User'] = Controls.Username.String, ['Password'] = Controls.Password.String })
  end
  EnqueueData('Component.GetComponents', {})
  local updated = {}
  for i,v in ipairs(Controls.RemoteComponents) do 
    if v.String~= '' and updated[v.String or 'nil']==nil then -- only update if not done so already
      RemoteComponentSelectEvent(i)
      updated[v.String] = true
    end 
  end
  ProcessSubscribersBuffer()
end

socket.Reconnect = function(sock)
  ReportStatus("MISSING","Socket Reconnect")
end

socket.Closed = SocketClosed

socket.Error = function(sock, err)
	ReportStatus("MISSING","Socket error")
end

socket.Timeout = function(sock, err)
  ReportStatus("MISSING","Socket Timeout")
end

socket.Data = function()		
  ReportStatus("OK","")
  local str = socket:Read(socket.BufferLength)
  rxBuffer = rxBuffer .. str
  if DebugRx then print((DebugFunction and 'TCP socket: '..#str..' bytes, rxBuffer: '..#rxBuffer..' bytes' or '')..(DebugRx and '. Rx <-\n'..str or '')) end
  if Controls.RxData then Controls.RxData.String = str end
  
  local function ProcessBuffer()
    if not rxLock then 
      rxLock = true
      if #rxBuffer==0 then
        BufferTimer:Stop()   
      else
        --if DebugFunction then print('ProcessBuffer(), rxBuffer: '..#rxBuffer..' bytes') end
        local tbl, raw, err = GetRxBufferBlock()
        if tbl then 
          ParseResponse(tbl, raw)
          if DebugFunction then 
            --print('GetRxBufferBlock done, #rxBuffer: '..#rxBuffer..' bytes, raw: '..(raw and #raw or 0)..' bytes')
            --print('rxBuffer raw:\n'..raw)
          end
        else
          if DebugFunction then 
            if err then --print(err)
            else        print('done parsing buffer #'..#rxBuffer..', raw #'..(raw and #raw or 0)) end
          end
        end
      end
      rxLock = false
    else
      if DebugFunction then print('ProcessBuffer(), rxLock is busy') end
    end
  end
  
  if not BufferTimer:IsRunning() then
    BufferTimer.EventHandler = ProcessBuffer
    BufferTimer:Start(BufferTime)
  end
end

function InitialiseCore()
  if DebugFunction then print('InitialiseCore') end
  queueBusy = false -- enable queue to process
  Controls.Platform.String = ''
  Controls.DesignName.String = ''
  if #Controls.IPAddress.String<1 then
    --Controls.IPAddress.String = System.IsEmulating and "localhost" or Network.Interfaces()[1].Address
    Controls.IPAddress.String = Network.Interfaces()[1].Address
  end
  Controls.IPAddress.EventHandler = Connect
  if Controls.Port.Value<1 then Controls.Port.Value = 1710 end
  Controls.Port.EventHandler = Connect

  Controls.StringToSend.EventHandler = function(ctl)
    if #ctl.String > 0 then
      subscribersBuffer = subscribersBuffer..ctl.String
      --if DebugFunction then print('StringToSend '..#subscribersBuffer..' bytes') end
      ctl.String = '' -- clear it to allow for future strings
      ProcessSubscribersBuffer()
    end
  end

  Controls.Username.EventHandler = LoggedOut
  Controls.Password.EventHandler = LoggedOut

  ReportStatus("INITIALIZING","Socket Initializing")
  Connect()
end

-----------------------------------------------------------------------------------------------------------------------
-- Component control functions
-----------------------------------------------------------------------------------------------------------------------
function InitialiseComponents()

  local function SendEventToRemote(component_name, control_name, value)
  if DebugFunction then print('SendEventToRemote['..component_name..']['..control_name..']: '..tostring(value)) end
      for i,v in ipairs(Controls.LocalComponents) do
      if v.String == component_name then -- send to the remote
        local remote_mame = Controls.RemoteComponents[i].String
        if DebugFunction then print('Matching remote['..i..']['..remote_mame..']') end
        if DebugFunction then print('Sending to remote['..i..']['..remote_mame..']: '..tostring(value)) end
        EnqueueData('Component.Set', {
          ["Name"]=remote_mame, 
          ["Controls"]={{
            ["Name"]=control_name, 
            ["Value"]=value
          }}
        } )
        if RemoteControls[remote_mame] and RemoteControls[remote_mame][control_name] then
          if DebugFunction then print('RemoteControls['..remote_mame..']['..control_name..'] exists') end
        else  
          local count = 0  
          for i1,j1 in pairs(RemoteControls[remote_mame]) do
            count = i1 
            print('RemoteControls['..remote_mame..']['..tostring(j1)..'] found')
          end
          if count == 0 then 
            if DebugFunction then 
              print('RemoteControls['..remote_mame..'] has no controls stored')
            end
          end
        end   
      end
    end
  end 

  local function LocalComponentSelectEvent(i)
    local local_component_name = Controls.LocalComponents[i].String
    if DebugFunction then print('LocalComponentSelectEvent('..i..') "'..local_component_name..'"') end
   -- clear lookup table
    if not LocalSelectors[local_component_name] then LocalSelectors[local_component_name] = {} end
    for _,v in pairs(LocalSelectors) do -- e.g. i==1 and LocalSelectors['Mic1'] = { 1,2 }
      if v[i] then                      -- LocalSelectors['Mic1'][1] exists
        v[i] = nil                      -- remove from table
      end
    end
    
    if local_component_name == '' then 
      Controls.LocalControls[i].Choices  = {}
      Controls.CommonControls[i].Choices = {}
    else
      table.insert(LocalSelectors[local_component_name], i) -- add lookup -- e.g. i==1 and LocalSelectors['Mic1'] = { 1 }
      local cmp = Component.New(local_component_name)
      local ctls = Component.GetControls(cmp)
      print('Local component['..i..'] selected "'..local_component_name..'", has '..#ctls..' controls')
      local choices_ = { [1]='' }
      for _,v1 in pairs(ctls) do table.insert(choices_, v1.Name) end       
      -- Define control EventHandler on demand if not already defined (prevents Max execution error)
      if LocalControls[local_component_name] then
        if DebugFunction then print('control EventHandlers for "'..local_component_name..'" are already defined') end
      else
        if DebugFunction then print('Adding control EventHandlers for "'..local_component_name..'"') end
        LocalControls[local_component_name] = ctls
        for _,v1 in ipairs(ctls) do
          if LocalComponents[local_component_name][v1.Name]~=nil then
            --if DebugFunction then print('adding EventHandler for "'..local_component_name..'"["'..tostring(v1.Name)..'"]') end
            LocalComponents[local_component_name][v1.Name].EventHandler = function(ctl)   
              local val = ctl.Type=='Text' and ctl.String or ctl.Value
              if ctl.Type=='Boolean' then val = ctl.Boolean -- can't do this in a ternary because a boolean can be false
              elseif ctl.Type=='Trigger' then val = ctl.Boolean -- Triggers aren't really supported in QSC protocol
              end -- can't do this in a ternary because a boolean can be false
              if v1.Name=='code' and not Controls.EnablePushingCode.Boolean then 
                 if DebugFunction then print('not sending local '..ctl.Type..' event "'..local_component_name..'"["'..tostring(v1.Name)..'"]')  end
              else
                if DebugFunction then print('local '..ctl.Type..' event "'..local_component_name..'"["'..tostring(v1.Name)..'"]: '..tostring(val))  end
                if ctl.Type=='Trigger' then
                  SendEventToRemote(local_component_name, v1.Name, 'trigger')
                end
                SendEventToRemote(local_component_name, v1.Name, val)
              end
            end
          end
        end  
      end
      Controls.LocalControls[i].Choices = choices_
      --UpdateCommonControls(i) -- this is called from HandleRemoteControlsData()
      EnqueueData('Component.GetControls', {["Name"]=Controls.RemoteComponents[i].String}) -- refresh remote data to sync with
    end
  end

  local function GetLocalComponents()
    if DebugFunction then print('GetLocalComponents()') end
    local choices = { [1] = '' }
    for i,v in pairs(Component.GetComponents()) do
      table.insert(choices, v.Name)
      LocalComponents[v.Name] = Component.New(v.Name)
      local types = { -- for info only to use some other time
          'gain', 'device_controller_script', 'usb_telephony', 'usb_ccontrols', 'usb_keyboard',
          'lightbar', 'touchscreen_sensors', 'spe_uci', 'snapshot_controller',
          'onvif_camera_operative', 'usb_uvc', 'custom_controls',
          '%PLUGIN%_(.+)_%FP%_(.+)' --'%PLUGIN%_63fb5d0a-5fdc-4c31-b63f-120c0fd29ca2_%FP%_f0e0123189fe1a5e530828d7ce47fcce'
          --'%PLUGIN%_qsysc.NVX.DEC.0.0.0.1-master_%FP%_e049ab3aa8b6cbf3302947c6fa21df05',
          --'%PLUGIN%_Samsung Commercial Display (MDC) v1.4*_%FP%_c985f891d86fa02029dfb3ecd0a97fbe',
      }
    end

    if DebugFunction then print('Found '..#choices..' local components with local script access') end
    for i,v in ipairs(Controls.LocalComponents) do 
      v.Choices = choices
      v.EventHandler = function() LocalComponentSelectEvent(i) end
    end

    Controls.ClearLocalCode.EventHandler = function(ctl) --LocalCodeBackup
      local clearedCodeScript = "print('code cleared by q-sys-plugin-remote-sync plugin - ClearLocalCode control')"
      for i,v in ipairs(Controls.LocalComponents) do
        if v.String~='' and LocalComponents[v.String] and LocalComponents[v.String]['code'] then
          if ctl.Boolean then -- clear code
            if #LocalComponents[v.String]['code'].String>0 and LocalComponents[v.String]['code'].String~=clearedCodeScript then
              LocalCodeBackup[v.String] = LocalComponents[v.String]['code'].String -- back it up
            end
            LocalComponents[v.String]['code'].String = clearedCodeScript
            if DebugFunction then print('Cleared local code for "'..v.String..'"') end
          else -- restore code
            if LocalComponents[v.String]['code'].String=='' or LocalComponents[v.String]['code'].String==clearedCodeScript then
              if LocalCodeBackup[v.String] then --attempt to restore code from memory
                if DebugFunction then print('Restoring code from backup "'..v.String..'"]\n'..LocalCodeBackup[v.String]) end
                LocalComponents[v.String]['code'].String = LocalCodeBackup[v.String]
              elseif Controls.EnablePullingCode.Boolean then --attempt to pull and sync code from remote
                if DebugFunction then print('Restoring code from remote "'..v.String..'"') end
                EnqueueData('Component.Get', {
                  ["Name"]=v.String, 
                  ["Controls"]={{["Name"]='code'}}
                })
              end
            end
          end
        break end
      end
    end
  end

	local function GetRemoteComponents()
		if DebugFunction then print('GetRemoteComponents()') end
    EnqueueData('Component.GetComponents', {})
    for i=1, Properties['Component Count'].Value do
      Controls.RemoteComponents[i].EventHandler = function(ctl) RemoteComponentSelectEvent(i) end
    end
	end

  function GetComponents()
		GetLocalComponents()
		GetRemoteComponents()
    -- Common components EventHandlers
    for i=1, Properties['Component Count'].Value do

      Controls.CommonComponents[i].EventHandler = function(ctl)
        print('Common component['..i..'] selected "'..ctl.String)
        Controls.LocalComponents[i].String = ctl.String
        LocalComponentSelectEvent(i)
        Controls.RemoteComponents[i].String = ctl.String
        RemoteComponentSelectEvent(i)
      end 
      -- updade component lists. todo: modify this so it doesn't repeat any unnecessary code
      if Controls.LocalComponents[i].String  ~= '' then LocalComponentSelectEvent(i) end
      if Controls.RemoteComponents[i].String ~= '' then RemoteComponentSelectEvent(i) end

      Controls.SyncComponent[i].EventHandler = function(ctl)
        --print('SyncComponent['..i..'] event '..tostring(ctl.Boolean))
        if ctl.Boolean then SyncComponent(Controls.CommonComponents[i].String) end
      end

    end 
	end

  GetComponents()
  Controls.LoadComponents.EventHandler = GetComponents
	
end

function Initialise()
  InitialiseCore()
  InitialiseComponents()
end
Initialise()
-----------------------------------------------------------------------------------------------------------------------
-- End of module
-----------------------------------------------------------------------------------------------------------------------