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
-----------------------------------------------------------------------------------------------------------------------
-- Remote Q-Sys control functions
-----------------------------------------------------------------------------------------------------------------------
local messageId = 1

socket = TcpSocket.New()
local rxBuffer = ''
local rxLock = false

local txBuffer = ''
local txLock = false

local subscriber = {}
local subscribersBuffer = ''
local subscribersLock = false

local StatusState = { OK = 0, COMPROMISED = 1, FAULT = 2, NOTPRESENT = 3, MISSING = 4, INITIALIZING = 5 }

local rapidjson = require 'rapidjson'

local commandQueue = {}
local queueBusy = false

local messageIDs = {}
local LocalComponents = {} -- the components on the local system gathered by Component.New()
local LocalControls = {}   -- The controls on the local system gathered by Component.GetControls(cmp)
local LocalCodeBackup = {}       -- 'code' on local components backed up and restored when the ClearLocalCode control is toggle
local RemoteComponents = {}
local RemoteControls = {}
local RemoteSubscriptions = {}
local RemoteComponentDefined = {}
local ChangeGroup = tostring(math.random(255))
local AutoPollInitiated = false
local PollRate = 0.5 -- lower this to 0.5 when it all works

ChangeTimer = Timer.New()
ChangeTimer:Start(0.1)
local ChangesToProcess = {}

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
  elseif 
    DebugFunction and DebugTx then 
      print("NOTICE: Didn't send "..#str_.." bytes of data - NO CONNECTION TO HOST")
    end
end

function SendData(method, params)
  if DebugFunction then print('SendData method: '..method..', params: '..(params and rapidjson.encode(params) or {})) end
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

local function UpdateCommonControls(i)
  local remote_name = Controls.RemoteComponents[i].String
  print('UpdateCommonControls('..i..') "'..remote_name..'"')
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

  Controls.CommonControls[i].String = ''
  Controls.CommonControls[i].Choices = choices

  if #remote_name>0 then
    if not RemoteSubscriptions[remote_name] then 
      if DebugFunction then print('Creating RemoteSubscriptions["'..remote_name..'"]') end
      RemoteSubscriptions[remote_name] = {} 
    else
      if DebugFunction then 
        if #RemoteSubscriptions[remote_name]==0 then
        local count=0
          for i1,v1 in pairs(RemoteSubscriptions[remote_name]) do
            --print('RemoteSubscriptions["'..remote_name..'"]['..i1..']: '..tostring(v1))
            count=count+1
          end
          print('RemoteSubscriptions["'..remote_name..'"] has '..count..' controls')
        else
          print('RemoteSubscriptions["'..remote_name..'"] has '..#RemoteSubscriptions[remote_name]..' controls')
        end
      end
    end
    local remote_controls = {}
    for _,v in ipairs(choices) do -- only subscribe to controls if not already subscribed
      if v~='' and not RemoteSubscriptions[remote_name][v] then
        if v=='code' and not Controls.EnablePullingCode.Boolean then
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
    if DebugFunction then print('Subscribing to remote['..i..'] "'..remote_name..'" has '..#remote_controls..' remote controls from '..#choices..' common controls') end
    if #remote_controls>0 then
      SendData('ChangeGroup.AddComponentControl', {
        ["Id"]=ChangeGroup, 
        ["Component"]={
          ["Name"]=remote_name,
          ["Controls"]=remote_controls
        }
      })
      if not AutoPollInitiated then
        SendData('ChangeGroup.AutoPoll', {
          ["Id"]=ChangeGroup, 
          ["Rate"]=PollRate
        })
      end
    end
  end 
end


local function SyncComponent(i)
  local local_ = Component.New(Controls.LocalComponents[i].String)
  print('SyncComponent('..i..')\n local: "'..Controls.LocalComponents[i].String..'" has '..#Component.GetControls(local_)..' controls')
  local remoteName_ = Controls.RemoteComponents[i].String
  if RemoteControls[remoteName_] then
    print(' RemoteControls["'..remoteName_..'"] has '..#RemoteControls[remoteName_]..' controls')
  else
    print('RemoteControls["'..remoteName_..'"] not found')
  end
  --for each component line (this func)
  if #Component.GetControls(local_)>0 then
    -- populate remoteControls_ 
    --for i,v in pairs(RemoteControls[remoteName_]) do remoteControls_[i]=v end --local remoteControls_ = RemoteControls[remoteName_] 
    --{"FunctionMicGain_1":[{"Name":"bypass","Type":"Boolean","Value":false,"String":"no","Position":0.0,"Direction":"Read/Write"},{"Name":"gain","Type":"Float","Value":0.0,"ValueMin":-21.0,"ValueMax":0.0,"StringMin":"-21.0dB","StringMax":"0dB","String":"0dB","Position":1.0,"Direction":"Read/Write"},{"Name":"invert","Type":"Boolean","Value":false,"String":"normal","Position":0.0,"Direction":"Read/Write"},{"Name":"mute","Type":"Boolean","Value":true,"String":"muted","Position":1.0,"Direction":"Read/Write"}]}        
    
    for _,v in ipairs(Controls.CommonControls[i].Choices) do -- assuming CommonControls is already updated
      if v~='' and
        RemoteControls[remoteName_][v] and
        not (v=='code' and not Controls.EnablePullingCode.Boolean) and
        local_[v] and
        (not local_[v].Direction or local_[v].Direction:match('Write')) -- "Name":"bypass"
      then -- ignore blank and script 'code'
        
        if DebugFunction then print('Synching "'..v..'" ("Value":"'..tostring(RemoteControls[remoteName_][v].Value)..'")') end
        for i2,v2 in pairs(RemoteControls[remoteName_][v]) do -- i2="Name", v2="bypass"
          local success, err = pcall(function() 
            if i2~='Name' and i2~='Direction' and local_[v][i2] then --["FunctionMicGain_1"]["bypass"]["Value"] = false
              --if DebugFunction then print('  Synching  "'..i2..'": "'..tostring(v2)..'"') end
              local_[v][i2] = RemoteControls[remoteName_][v] 
            end
          end)
        end   
      end           
      --[[ -- to be deleted after the replacement code above is tested successfully
        for _,v1 in ipairs(remoteControls_) do
          if v1.Name == v and local_[v] and (not local_[v].Direction or local_[v].Direction:match('Write')) then -- "Name":"bypass"
            if DebugFunction then print('Synching "'..v..'" ("Value":"'..tostring(v1.Value)..'")') end
            for i2,v2 in pairs(v1) do -- i2="Name", v2="bypass"
              local success, err = pcall(function() 
                if i2~='Name' and i2~='Direction' and local_[v][i2] then --["FunctionMicGain_1"]["bypass"]["Value"] = false
                  --if DebugFunction then print('  Synching  "'..i2..'": "'..tostring(v2)..'"')
                  local_[v][i2] = v2 
                end
              end)
            end   
          end
        end
      end
      ]]--
    end
  end
end

local function UpdateCommonComponents(remote)
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
    RemoteControls[data.Name] = data.Controls
    if DebugFunction then  print('HandleRemoteControlsData["'..data.Name.. '"] has '..#data.Controls..' controls') end
    local choices = { [1]= '' }
    for _,j in ipairs(data.Controls) do table.insert(choices, j.Name) end
    for i=1, Properties['Component Count'].Value do
      if Controls.RemoteComponents[i].String == data.Name then
        if DebugFunction then print('Populating RemoteComponents['..i..'] with RemoteControls["'..data.Name..'"], '..#RemoteControls[data.Name]..' controls') end
        Controls.RemoteControls[i].Choices = choices
        UpdateCommonControls(i)
        SyncComponent(i)
      end
    end
  end
end

function HandleRemoteComponentsData(data) -- [{"Name": "APM ABC", "Type": "apm", "Properties":[{"Name": "multi_channel_type","Value": "1"},]},]
  if type(data)=='boolean' then print('HandleRemoteComponentsData is boolean') return end
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

local function Logon(params)--Logon{ ['User'] = Controls.Username.String, ['Password'] = Controls.Password.String }
  if DebugFunction then print('Logon called') end --, params: '..(params and rapidjson.encode(params) or '')) end
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

local function RemoteComponentEvent(ctl, i)
  print('Remote component['..i..'] selected "'..ctl.String..'"')
  if ctl.String == '' then 
    Controls.RemoteControls[i].Choices = {}
    Controls.CommonControls[i].Choices = {}
    if RemoteComponentDefined[i] then table.remove(RemoteComponentDefined, i) end
  else
    RemoteComponentDefined[i] = true
    for i1=1, Properties['Component Count'].Value do
      if i1~=i and Controls.RemoteComponents[i1].String == ctl.String and #Controls.RemoteComponents[i1].Choices>0 then
        print(i1..': '..Controls.RemoteComponents[i1].String)
        ctl.Choices = Controls.RemoteComponents[i].Choices -- todo: flag that we don't need to send GetControls request now
      end
    end
    SendData('Component.GetControls', {["Name"]=ctl.String})
  end
  UpdateCommonControls(i)
end

local function GetRemoteComponents()
  if DebugFunction then print('GetRemoteComponents()') end
  SendData('Component.GetComponents', {})
  local updated = {}
  for i,v in ipairs(Controls.RemoteComponents) do 
    if v.String~= '' and updated[v.String or 'nil']==nil then -- only update if not done so already
      RemoteComponentEvent(v, i)
      updated[v.String] = true
    end 
  end
  ProcessSubscribersBuffer()
end

local function LoggedIn(status)
  if status and not Controls.LoggedIn.Boolean then
    if DebugFunction then print('Login success, message queue size: '..#commandQueue) end
    Controls.LoggedIn.Boolean = true 
    queueBusy = false
    GetRemoteComponents()
    ProcessSubscribersBuffer()
  end
end

local function UpdateChange(change) -- change = { "Component": "BGM XFADE", "Name": "InputSelect 1", "String": "BGM GLOBAL 1", .. }
  --for i=1, Properties['Component Count'].Value do
  for i,_ in pairs(RemoteComponentDefined) do
    --if DebugFunction then print('Checking RemoteComponents['..i..']') end
    if Controls.RemoteComponents[i].String == change.Component then
      if change.Name=='code' and not Controls.EnablePullingCode.Boolean then -- ignore script 'code'
        if DebugFunction then print('not synching ChangeGroup for RemoteComponents['..i..']["'..change.Component..'"]["'..change.Name..'"]') end
      else
        if DebugFunction then print('ChangeGroup for RemoteComponents['..i..']["'..change.Component..'"]["'..change.Name..'"]: '..tostring(change.Value)) end
        local local_ = LocalComponents[Controls.LocalComponents[i].String]
        if local_ and local_[change.Name] then
          --if DebugFunction then print('LocalComponents["'..Controls.LocalComponents[i].String..'"]["'..change.Name..'"] exists') end
          for k1, v1 in pairs(change) do
            local success, msg = pcall(function() 
              if k1~='Component' and k1~='Name' and k1~='Direction' and (not local_[change.Name].Direction or local_[change.Name].Direction:match('Write')) and local_[change.Name][k1] then
                --if DebugFunction then print('Updating LocalComponents["'..change.Component..'"]["'..change.Name..'"]["'..k1..'"]: '..tostring(v1)) end
                local_[change.Name][k1] = v1
              end
            end) --pcall because sometimes an unexpected Property does not exist on Control (such as 'Indeterminate', 'Invisible', 'Disabled')
            --if not success and DebugFunction then print('local "'..change.Name..'"["'..k1..'"] error\n'..msg) end
          end
        end
      end
    end
  end
  if ChangesToProcess[change.Component] and ChangesToProcess[change.Component][change.Name]~=nil then
    ChangesToProcess[change.Component][change.Name]=nil
  end
end

function ProcessNextChange()
  if ChangesToProcess and #ChangesToProcess>0 then
    for componentName, component in pairs(ChangesToProcess) do 
      if component and #component>0 then
        for controlName, control in pairs(component) do  
          if ChangesToProcess[change.Component]~=nil and ChangesToProcess[change.Component][change.Name]~=nil then
            if DebugFunction then print('Updating and Removing '..change.Component..'['..change.Name..'] from ChangesToProcess') end
          end
          UpdateChange(control)
          return
        end
      end
    end
  end
end

ChangeTimer.EventHandler = ProcessNextChange

local function HandleChangeGroupPollData(data)
  -- ChangeGroup.Poll doesn't include a data.id so need to figure out what subscriber scripts to send it to
  --{"jsonrpc":"2.0","method":"ChangeGroup.Poll","params":{"Id":"1","Changes":[]}}
  local log = ''
  if #data.params.Changes > 0 then 
    if DebugFunction then  log = log..'HandleChangeGroupPollData\n method: '..data.method..', '..#data.params.Changes..' changes'end -- only log changes
    local localUpdates_ = {} -- create custom responses for each subscriber script
    local cur_ = ''
    local success, err = pcall(function()
      for _, change_ in ipairs(data.params.Changes) do 
        cur_ = change_
        if not ChangesToProcess[change_.Component] then ChangesToProcess[change_.Component] = {} end
        ChangesToProcess[change_.Component][change_.Name] = change_ -- load data to be processed on a timer in case of max execution error
        UpdateChange(change_)
      end
    end) --this causes a Max execution error with large components
    if not success then 
      print(log..'\nERROR at UppdateChange ["'..cur_.Component..'"]["'..cur_.Name..'"]\n'..err)
      log = ''
      print('Timer will complete synchronisation with UppdateChange')
    end
  end
  if DebugFunction and log~='' then print(log) end
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
              LoggedOut()
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
            if DebugFunction and log~='' then print(log) log = '' end
            HandleChangeGroupPollData(data)
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

  if DebugFunction and log~='' then print(log) end
end

local function LoggedOut()
  if DebugFunction then print('LoggedOut') end
  Controls.Platform.String = ''
  Controls.DesignName.String = ''
  Controls.LoggedIn.Boolean = false
  commandQueue = nil -- clear queue
  commandQueue = {}
  RemoteSubscriptions = nil -- clear
  RemoteSubscriptions = {}
  AutoPollInitiated = false
  rxBuffer = ''
  rxLock = false
  Logon({ User = Controls.Username.String, Password = Controls.Password.String })
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
    socket:Disconnect()
    LoggedOut()
  end
  socket:Connect(Controls.IPAddress.String, Controls.Port.Value)
end 

function ReportStatus(state,msg)
  if Controls.Status.Value ~= StatusState[state] then
	  if DebugFunction and stat~='OK' then print("ReportStatus("..state..") "..msg) end
	end
  local msg=msg or ""
	Controls.Status.Value = StatusState[state]
	Controls.Status.String = msg
  Controls.Connected.Boolean = socket.IsConnected
  if not socket.IsConnected then Controls.LoggedIn.Boolean = false end
end

socket.Connected = function(sock)
  ReportStatus("OK","Socket connected")
  if #Controls.Username.String > 0 then
    Controls.LoginRequired.Boolean = true
    Logon({ ['User'] = Controls.Username.String, ['Password'] = Controls.Password.String })
  end
  if not Controls.LoginRequired.Boolean then GetRemoteComponents() end
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
  local str = socket:Read(socket.BufferLength)
  ReportStatus("OK", #str.." bytes of data received")
  rxBuffer = rxBuffer .. str
  if DebugRx then print((DebugFunction and 'TCP socket: '..#str..' bytes, rxBuffer: '..#rxBuffer..' bytes'..', rxLock: '..tostring(rxLock) or '')..(DebugRx and '. Rx <-\n'..str or '')) end
  if Controls.RxData then Controls.RxData.String = str end
  if not rxLock then
    rxLock = true
    while #rxBuffer>0 do
      if DebugFunction and DebugRx then print('GetRxBufferBlock, rxBuffer: '..#rxBuffer..' bytes') end
      local tbl, raw, err = GetRxBufferBlock()
      if not tbl then 
        if DebugFunction then 
          if err then --print(err)
          else        print('done parsing buffer #'..#rxBuffer..', raw #'..(raw and #raw or 0)) end
        end
        break
      end
      if DebugFunction and DebugRx then 
        print('GetRxBufferBlock done, #rxBuffer: '..#rxBuffer..' bytes, raw: '..(raw and #raw or 0)..' bytes')
        --print('rxBuffer raw:\n'..raw)
      end
      ParseResponse(tbl, raw)
    end
    rxLock = false
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
    if DebugFunction then print('SendEventToRemote("'..component_name..'","'..control_name..'","'..tostring(value)..'")') end
    for i,v in ipairs(Controls.LocalComponents) do
      if v.String == component_name then -- send to the remote
        local remote_mame = Controls.RemoteComponents[i].String
        if RemoteControls[remote_mame] then
          for i1,j1 in pairs(RemoteControls[remote_mame]) do
            if j1.Name==control_name then
              if DebugFunction then print('Sending to remote['..i..']['..remote_mame..']: '..tostring(value)) end
              SendData('Component.Set', {
                  ["Name"]=remote_mame, 
                  ["Controls"]={{
                    ["Name"]=control_name, 
                    ["Value"]=value
                  }}
                } )
              break
            end
          end
        end       
      end
    end
  end 

  local function LocalComponentEvent(local_component_combo, i)
    local local_component_name = local_component_combo.String
    if local_component_name == '' then 
      Controls.LocalControls[i].Choices  = {}
      Controls.CommonControls[i].Choices = {}
    else
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
      UpdateCommonControls(i)
      if Controls.RemoteComponents[i].String~='' then
        SendData('Component.GetControls', {["Name"]=Controls.RemoteComponents[i].String}) -- refresh remote data to sync with
      end
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
      v.EventHandler = function(ctl) LocalComponentEvent(ctl, i) end
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
                SendData('Component.Get', {
                  ["Name"]=v.String, 
                  ["Controls"]={{["Name"]='code'}}
                })
              end
            end
          end
        break end
      end
    end

    Controls.EnablePullingCode.EventHandler = function(ctl)
      if ctl.Boolean then
        if DebugFunction then print('Enabling code pulling from remote') end
        Controls.ClearLocalCode.Boolean = false -- mutually exclusive
        local seen = {}
        for i,v in ipairs(Controls.RemoteComponents) do
          if v.String~='' and not seen[v.String] then
            seen[v.String] = true
            for _,v1 in ipairs(Controls.CommonControls[i].Choices) do
              if v1=='code' then
                if DebugFunction then print('Subscribing to remote['..i..'] "'..v.String..'".code') end           
                SendData('ChangeGroup.AddComponentControl', {
                  ["Id"]=ChangeGroup,
                  ["Component"]={
                    ["Name"]=v.String,
                    ["Controls"]={ {["Name"]='code'} }
                  }
                })
              end
            end
          end
        end
      else
        if DebugFunction then print('Disabling code pulling from remote') end
      end
    end

  end

  function CreateComponentEventHandlers()
		GetLocalComponents()
    -- RemoteComponents EventHandlers
    for i=1, Properties['Component Count'].Value do
      Controls.RemoteComponents[i].EventHandler = function(ctl) RemoteComponentEvent(ctl, i) end
    end
    -- Common components EventHandlers
    for i=1, Properties['Component Count'].Value do

      Controls.CommonComponents[i].EventHandler = function(ctl)
        print('Common component['..i..'] selected "'..ctl.String)
        Controls.LocalComponents[i].String = ctl.String
        LocalComponentEvent(Controls.LocalComponents[i], i)
        Controls.RemoteComponents[i].String = ctl.String
        RemoteComponentEvent(Controls.RemoteComponents[i], i)
      end 
      -- updade component lists
      if Controls.LocalComponents[i].String  ~= '' then LocalComponentEvent(Controls.LocalComponents[i], i) end
      if Controls.RemoteComponents[i].String ~= '' then RemoteComponentEvent(Controls.RemoteComponents[i], i) end

      Controls.SyncComponent[i].EventHandler = function(ctl)
        --print('SyncComponent['..i..'] event '..tostring(ctl.Boolean))
        if ctl.Boolean then SyncComponent(i) end
      end

    end
	end

  CreateComponentEventHandlers()
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
