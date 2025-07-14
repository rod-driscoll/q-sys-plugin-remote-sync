 	-----------------------------------------------------------------------------------------------------------------------
	-- dependencies
	-----------------------------------------------------------------------------------------------------------------------
	rapidjson = require "rapidjson"
	-----------------------------------------------------------------------------------------------------------------------
	-- Variables
	-----------------------------------------------------------------------------------------------------------------------
	local DebugTx=false
	local DebugRx=false
	local DebugFunction=false
	local DebugPrint = Properties["Debug Print"].Value

	-----------------------------------------------------------------------------------------------------------------------
  -- Helper functions
	-------------------------------------------------------------------------------------------------------------------
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
    Controls["DebugFunction"].Boolean = DebugFunction
    Controls["DebugTx"].Boolean = DebugTx
    Controls["DebugRx"].Boolean = DebugRx
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

local StatusState = { OK = 0, COMPROMISED = 1, FAULT = 2, NOTPRESENT = 3, MISSING = 4, INITIALIZING = 5 }

local rapidjson = require 'rapidjson'

local subscriber = {}
local commandQueue = {}

local messageIDs = {}
local remoteComponents = {}

function Dequeue(queue)
  if DebugFunction then print('Dequeue() size: '..#queue) end
  if #queue > 0 then
    local item_ = table.remove(queue, 1)
    item_.func(table.unpack(item_.params))
  end
  if DebugFunction then print('Dequeue done size: '..#queue) end
end

function Enqueue(queue, data)
  queue[#queue+1] = data
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
  --print('GetRxBufferBlock(#'..len..')')
  local first_json_pos = str:find("[%[{]") -- Trim garbage before the first `{` or `[`
  if not first_json_pos then -- No possible JSON in buffer, discard everything
    print('No possible JSON in rxBuffer:\n'..rxBuffer)
    rxBuffer = ""
    return nil, nil, "No possible JSON in rxBuffer"
  elseif first_json_pos > 1 then
    str = str:sub(first_json_pos) -- Trim leading garbage
    rxBuffer = str
  end
  
  local start, finish, candidate = str:find("(%b{})")  -- Try to find the first balanced JSON object or array
  if not candidate or start > 1 then
    start, finish, candidate = str:find("(%b[])")
  end
  if not candidate or start > 1  then return nil, nil, "Incomplete json block" end
  local decoded = rapidjson.decode(candidate)  -- Try decoding to check if it's valid JSON
  if decoded then -- Remove the matched block from the buffer
    rxBuffer = str:sub(finish + 1)
    return decoded, candidate
  else -- If the match wasn't valid JSON, discard it and continue
    rxBuffer = str:sub(finish + 1)
    return nil, nil, "Invalid JSON"
  end
end

function GetTxBufferBlock() -- need to use global TxBuffer
  local str = txBuffer
  --print('GetTxBufferBlock(#'..len..')')  
  local first_json_pos = str:find("[%[{]") -- Trim garbage before the first `{` or `[`
  if not first_json_pos then -- No possible JSON in buffer, discard everything
    print('No possible JSON in buffer:\n'..buffer)
    txBuffer = ""
    return nil, nil, "No possible JSON in buffer"
  elseif first_json_pos > 1 then
    str = str:sub(first_json_pos) -- Trim leading garbage
    txBuffer = str
  end

  local start, finish, candidate = str:find("(%b{})")  -- Try to find the first balanced JSON object or array
  if not candidate or start > 1 then
    start, finish, candidate = str:find("(%b[])")
  end
  if not candidate or start > 1  then return nil, nil, "Incomplete json block" end
  local decoded = rapidjson.decode(candidate)  -- Try decoding to check if it's valid JSON
  if decoded then -- Remove the matched block from the buffer
    txBuffer = str:sub(finish + 1)
    return decoded, candidate
  else -- If the match wasn't valid JSON, discard it and continue
    txBuffer = str:sub(finish + 1)
    return nil, nil, "Invalid JSON"
  end
end

local function ProcessTxBuffer()
  if not txLock and #txBuffer>0 and socket.IsConnected and (Controls.LoggedIn.Boolean or not Controls.LoginRequired.Boolean) then
    txLock = true
    while #txBuffer>0 do
      --if DebugFunction then print('GetTxBufferBlock(TX) buffer: '..#txBuffer..' bytes') end
      local tbl, raw, err = GetTxBufferBlock()
      --if DebugFunction then print('GetTxBufferBlock(TX) done, buffer: '..#txBuffer..' bytes') end
      if not tbl then break end
      TrackSubscription(tbl, raw)
      if socket.IsConnected then 
        if DebugTx then print("Tx: "..raw) end
				if tbl.id then messageIDs[tbl.id] = tbl end
        socket:Write(raw..'\n\r\x00')
      else
        print("DIDN'T SEND DATA - NO CONNECTION TO HOST")
      end
    end
    txLock = false
  end
end

local function UpdateCommonComponents()
	for _, v in ipairs(data) do
    table.insert(choices, v.Name)
	end
end

function ConfigureRemoteComponents(data) -- [{"Name": "APM ABC", "Type": "apm", "Properties":[{"Name": "multi_channel_type","Value": "1"},]},]
	remoteComponents = data
	local choices = {}
	for _, v in ipairs(data) do
    table.insert(choices, v.Name)
	end
	Controls.RemoteComponent.Choices = choices
	for i=1, props['Component Count'].Value do
		Controls["LocalComponentSelect"][i].Choices = choices
	end
	UpdateCommonComponents()
end

function ParseResponse(data, raw)
  --{"jsonrpc":"2.0","id":"Script killer-186","error":{"code":10,"message":"Logon required"}}
  --{"jsonrpc":"2.0","method":"EngineStatus","params":{"Platform":"Core 110f","State":"Active","DesignName":"Gosford RSL CORE110F DEV V1.5.0 20250114","DesignCode":"srOW2FUZF3HC","IsRedundant":false,"IsEmulator":false,"Status":{"Code":4,"String":"Missing - 1 OK, 4 Compromised, 76 Missing"}}}
  local log = ''
  if DebugFunction then log = log..'ParseResponse length: '..#raw end
  if data then
    if data.jsonrpc then 
      --if DebugFunction then  print('jsonrpc: '..data.jsonrpc) end
      if data.id then
        if DebugFunction then log = log..'\n value.id: "'..data.id..'", type: '..type(data.id) end
        local componentId_, messageId_
        if type(data.id)=='number' then 
          messageId_= data.id
        else
          componentId_, messageId_ = (data.id):match("^(.*)%-(%d+)") -- e.g. 'comonent name-1' is used for subscriptions
        end
        if componentId_ then -- subscription from a local component
          if DebugFunction then log = log..'\n component id: "'..componentId_..'", messageId: '..messageId_ end
          if data.error then
            if DebugFunction then log = log..'\n error code: "'..data.error.code..'", message: '..data.error.message end
            if data.error.code == 10 then --"error":{"code":10,"message":"Logon required"}
              Controls.LoginRequired.Boolean = true 
              Controls.LoggedIn.Boolean = false 
              local params_ = { ['User'] = Controls.Username.String, ['Password'] = Controls.Password.String }
              SendData('Logon', params_)
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
					if messageIDs[data.id] then
						local msg_ = table.remove(messageIDs[data.id]) -- release resources
						if msg_.method == "Component.GetComponents" then --"result": [{"Name": "APM ABC", "Type": "apm", "Properties":[{"Name": "multi_channel_type","Value": "1"},]},]
							ConfigureRemoteComponents(msg_.result)
						end
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
            -- ChangeGroup.Poll doesn't include a data.id so need to figure out what subscriber scripts to send it to
            if DebugFunction then -- only log changes
              log = #data.params.Changes==0 and '' or log..'\n method: '..data.method..', '..#data.params.Changes..' changes'
            end
            --{"jsonrpc":"2.0","method":"ChangeGroup.Poll","params":{"Id":"1","Changes":[]}}
            if #data.params.Changes > 0 then 
              local updates_ = {} -- create custom responses for each subscriber script
              for _, change_ in ipairs(data.params.Changes) do
                -- change_ = { "Component": "BGM XFADE", "Name": "InputSelect 1", "String": "BGM GLOBAL 1", .. }
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
                    if change_.Component == subscriber_.params.Component.Name then --e.g. 'BGM XFADE', 'lighting'
                      --if DebugFunction then log = log..'\n  Matched local component ['..change_.Component..'], remote control ['..change_.Name..']' end
                      for _, v in ipairs(subscriber_.params.Component.Controls) do -- change_.Name = 'mute', 'preset.3 1'
                        --if DebugFunction then log = log..'\n   subscriber control: v.Name ['..v.Name..']' end
                        if change_.Name == v.Name then -- 'InputSelect 1' or 'mute'
                          --if DebugFunction then log = log..'\n  Matched local: ['..localScript_..'], remote: ['..change_.Component..']['..v.Name..']' end
                          if not updates_[localScript_] then
                            updates_[localScript_] = {
                              ['jsonrpc'] = data.jsonrpc,
                              ['method'] = data.method,
                              ['params'] = { 
                                ['Id'] = id, 
                                ['Changes'] = {}
                              }
                            }
                          end
                          table.insert(updates_[localScript_].params.Changes, change_)
                        end
                      end
                    end
                  end
                end 
              end
              for componentId_, data_ in pairs(updates_) do
                if DebugFunction then log = log..'\ncomponent id: '..componentId_ end
                local component_ = Component.New(componentId_)
                if component_ and #Component.GetControls(component_)>0 then 
                  local str_ = rapidjson.encode(data_)
                  if DebugFunction then log = log..'\nsending '..#str_..' bytes to: '..componentId_..'.StringFromRemoteQSYS' end
                  if DebugSubscriberTx then log = log..'\ndata: '..str_ end
                  component_.StringFromRemoteQSYS.String = str_
                end
              end 
            end
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
          if not Controls.LoggedIn.Boolean then
            Controls.LoggedIn.Boolean = true 
            ProcessTxBuffer()
          end
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
		if data.id and messageIDs[data.id] then table.remove(messageIDs[data.id]) end -- release resources
    buffer = ''
  else 
    if DebugFunction then log = log..'\ninvalid json in buffer, waiting for more data' end
  end

  if DebugFunction and #log>0 then print(log) end
end

function Connect()
  if Controls.IPAddress.String == "" then
    --Controls.IPAddress.String = System.IsEmulating and "localhost" or Network.Interfaces()[1].Address
    Controls.IPAddress.String = Network.Interfaces()[1].Address
    if DebugFunction then print('IPAddress is empty, setting default: '..Controls.IPAddress.String) end
  end
  if Controls.Port.String == 0 then
    if DebugFunction then print('Port is zero, setting default: '..Controls.Port.String) end
    Controls.Port.String = 1710
  end
  if DebugFunction then print('Connect('..Controls.IPAddress.String..':'..Controls.Port.String..')') end
  if socket.IsConnected then
    socket:Disconnect()
  end
  socket:Connect(Controls.IPAddress.String, Controls.Port.Value)
end 

function SendData(method, params)
  --print('SendData: method: '..method..', params: '..params)
  local params_ = params or ''
  local data_ = {
      ['jsonrpc'] = '2.0',
      ['id'] = messageId,
      ['method'] = method,
      ['params'] = params_
  }
  local str_ = rapidjson.encode(data_)..'\n\r\x00' -- '{"jsonrpc": "2.0",\n\r  "id": '..id..',\n\r  "method": "'..method..'",\n\r  "params": "'..params..'"\n}\n\r\x00'
  if DebugTx then print('Tx-> '..str_) end
	messageIDs[messageId] = data_
  socket:Write(str_)
  messageId = messageId+1
end

function ReportStatus(state,msg)
  if Controls.Status.Value ~= StatusState[state] then
	  if DebugFunction then print("ReportStatus("..state..") "..msg) end
	end
  local msg=msg or ""
	Controls.Status.Value = StatusState[state]
	Controls.Status.String = msg
  Controls.Connected.Boolean = socket.IsConnected
  if not socket.IsConnected then Controls.LoggedIn.Boolean = false end
end

socket.Connected = function(sock)
  ReportStatus("OK","")
  messageId = 1
  if #Controls.Username.String > 0 then
    Controls.LoginRequired.Boolean = true 
    local params_ = { ['User'] = Controls.Username.String, ['Password'] = Controls.Password.String }
    SendData('Logon', params_)
  end
  ProcessTxBuffer()
end

socket.Reconnect = function(sock)
  ReportStatus("MISSING","Socket Reconnect")
end

socket.Closed = function(sock)
  ReportStatus("MISSING","Socket closed")
  Controls.Platform.String = ''
  Controls.DesignName.String = ''
end

socket.Error = function(sock, err)
	ReportStatus("MISSING","Socket error")
end

socket.Timeout = function(sock, err)
  ReportStatus("MISSING","Socket Timeout")
end

socket.Data = function()		
  ReportStatus("OK","")
  local str = socket:Read(socket.BufferLength)
  buffer = buffer .. str
  --if DebugFunction then print('TCP socket: '..#str..' bytes, buffer: '..#buffer..' bytes'..(DebugRx and '. Rx <-\n'..str or '')) end
  Controls.Message.String = str
  if not rxLock then 
    rxLock = true
    while #buffer>0 do
      --if DebugFunction then print('GetTxBufferBlock, buffer: '..#buffer..' bytes') end
      local tbl, raw, err = GetTxBufferBlock()
      if not tbl then 
        if DebugFunction then 
          if err then print(err)
          else        print('done parsing buffer #'..#buffer..', raw #'..(raw and #raw or 0)) end
        end
        break
      end
      if DebugFunction then 
        --print('GetTxBufferBlock done, buffer: '..#buffer..' bytes, raw: '..(raw and #raw or 0)..' bytes')
        --if #buffer>1 then print('Buffer:\n'..buffer..'\nraw:\n'..raw) end
      end
      ParseResponse(tbl, raw)
    end
    rxLock = false
  end
end

function InitialiseCore()
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
      txBuffer = txBuffer..ctl.String
      --if DebugFunction then print('StringToSend '..#txBuffer..' bytes') end
      ctl.String = '' -- clear it to allow for future strings
      ProcessTxBuffer()
    end
  end

  ReportStatus("INITIALIZING","Socket Initializing")
  Connect()
end

InitialiseCore()
	-----------------------------------------------------------------------------------------------------------------------
	-- Component control functions
	-----------------------------------------------------------------------------------------------------------------------
function InitialiseComponents()
  -- top level components in design
  local function GetLocalComponents()
    if DebugFunction then print('GetComponents()') end
    local choices = {}
    for i,v in pairs(Component.GetComponents()) do
      table.insert(choices, v.Name)
      print('Component: '..v.Name, ', Type: '..(v.Type or ''))
      local types = { -- for info only to use some other time
          'gain', 'device_controller_script', 'usb_telephony', 'usb_ccontrols', 'usb_keyboard',
          'lightbar', 'touchscreen_sensors', 'spe_uci', 'snapshot_controller',
          'onvif_camera_operative', 'usb_uvc', 'custom_controls',
          --'%PLUGIN%_63fb5d0a-5fdc-4c31-b63f-120c0fd29ca2_%FP%_f0e0123189fe1a5e530828d7ce47fcce'
          --'%PLUGIN%_qsysc.NVX.DEC.0.0.0.1-master_%FP%_e049ab3aa8b6cbf3302947c6fa21df05',
          --'%PLUGIN%_Samsung Commercial Display (MDC) v1.4*_%FP%_c985f891d86fa02029dfb3ecd0a97fbe',
      }
--[[
      local DebugOutput = ""    
      for _,v2 in ipairs(v.Properties) do           --Add the list of properties to the DebugOutput string
        for k3,v3 in pairs(v2) do 
          DebugOutput = DebugOutput.."\n      "..k3.." = "..v3
        end
        DebugOutput = DebugOutput.."\n"
      end 
      print (DebugOutput) 
]]--
      if v.Type then
        DebugOutput = ""    
        for _,v2 in ipairs(v.Type) do           --Add the list of properties to the DebugOutput string
          for k3,v3 in pairs(v2) do 
            DebugOutput = DebugOutput.."\n      "..k3.." = "..v3
          end
          DebugOutput = DebugOutput.."\n"
        end 
        print (DebugOutput) 
      end
    end

    Controls.LocalComponents.Choices = choices
    --Controls["Selected component"].String = Controls.LocalComponents.String
  end

	local function GetRemoteComponents()
		if DebugFunction then print('GetRemoteComponents()') end
		local choices = {}
    SendData('Component.GetComponents', '')
	end

  function GetComponents()
		GetLocalComponents()
		GetRemoteComponents()
	end

  GetComponents()
  Controls.LoadComponents.EventHandler = GetComponents
	
end

InitialiseComponents()
	-----------------------------------------------------------------------------------------------------------------------
	-- End of module
	-----------------------------------------------------------------------------------------------------------------------