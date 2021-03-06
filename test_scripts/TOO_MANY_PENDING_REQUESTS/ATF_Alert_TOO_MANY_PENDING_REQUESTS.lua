Test = require('connecttest')
require('cardinalities')
local events = require('events')
local mobile_session = require('mobile_session')
local mobile  = require('mobile_connection')
local tcp = require('tcp_connection')
local file_connection  = require('file_connection')

local commonSteps = require('user_modules/shared_testcases/commonSteps')

function DelayedExp()
  local event = events.Event()
  event.matches = function(self, e) return self == e end
  EXPECT_EVENT(event, "Delayed event")
  RUN_AFTER(function()
              RAISE_EVENT(event, event)
            end, 5000)
end


local n = 0
--///////////////////////////////////////////////////////////////////////////--
--Script cheks TOO_MANY_PENDING_REQUEST resultCode in Alert response from SDL
--///////////////////////////////////////////////////////////////////////////--

---------------------------------------------------------------------------------------------
-------------------------------------------Preconditions-------------------------------------
---------------------------------------------------------------------------------------------
  --Begin Precondition.1
  --Description: Allow GetVehicleData in all levels
  function Test:PreconditionStopSDLToChangeIniFile( ... )
    -- body
    StopSDL()
    DelayedExp(1000)
  end

  function Test:PreconditionBackUpIniFile()
    -- body
    os.execute('cp ' .. config.pathToSDL .. 'smartDeviceLink.ini' .. ' ' .. config.pathToSDL .. 'backup_smartDeviceLink.ini')
  end

  function Test:PreconditionSetPendingRequestsAmountInIniFile()
      local SDLini = config.pathToSDL .. tostring("smartDeviceLink.ini")
      local StringToReplace = "PendingRequestsAmount = 3\n"
      f = assert(io.open(SDLini, "r"))
      if f then
          fileContent = f:read("*all")

          fileContentUpdated  =  string.gsub(fileContent, "%p?PendingRequestsAmount%s-=%s?[%w%d;]-\n", StringToReplace)

          if fileContentUpdated then
            f = assert(io.open(SDLini, "w"))
            f:write(fileContentUpdated)
          else 
            userPrint(31, "Finding of 'PendingRequestsAmount = value' is failed. Expect string finding and replacing of value to true")
          end
          f:close()
      end
  end

  local function StartSDLAfterChangePreloaded()
    -- body

    Test["Precondition_StartSDL"] = function(self)
      StartSDL(config.pathToSDL, config.ExitOnCrash)
      DelayedExp(1000)
    end

    Test["Precondition_InitHMI_1"] = function(self)
      self:initHMI()
    end

    Test["Precondition_InitHMI_onReady_1"] = function(self)
      self:initHMI_onReady()
    end

    Test["Precondition_ConnectMobile_1"] = function(self)
      self:connectMobile()
    end

    Test["Precondition_StartSession_1"] = function(self)
      self.mobileSession = mobile_session.MobileSession(self, self.mobileConnection)
    end

  end

  StartSDLAfterChangePreloaded()

  function Test:RestoreIniFile()
    -- body
    os.execute('cp ' .. config.pathToSDL .. 'backup_smartDeviceLink.ini' .. ' ' .. config.pathToSDL .. 'smartDeviceLink.ini')
    os.execute('rm ' .. config.pathToSDL .. 'backup_smartDeviceLink.ini')
  end
  --End Precondition.1

  --Begin Precondition.2
  --Description: Activation application     
  local GlobalVarAppID = 0
  function RegisterApplication(self)
    -- body
    local corrID = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)

    EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered")
    :Do(function (_, data)
      -- body
      GlobalVarAppID = data.params.application.appID
    end)

    EXPECT_RESPONSE(corrID, {success = true})

    -- delay - bug of ATF - it is not wait for UpdateAppList and later
    -- line appID = self.applications["Test Application"]} will not assign appID
    DelayedExp(1000)
  end

  function Test:RegisterApp()
    -- body
    self.mobileSession:StartService(7)
    :Do(function (_, data)
      -- body
      RegisterApplication(self)
    end)
  end
  --End Precondition.2

  --Begin Precondition.3
  --Description: Activation App by sending SDL.ActivateApp  
  function Test:ActivationApp(AppNumber, TestCaseName)  
    
    local deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"

    --hmi side: sending SDL.ActivateApp request
    local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = GlobalVarAppID})
    EXPECT_HMIRESPONSE(RequestId)
    :Do(function(_,data)
      if
        data.result.isSDLAllowed ~= true then
        local RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"DataConsent"}})
        
        --hmi side: expect SDL.GetUserFriendlyMessage message response
        --TODO: update after resolving APPLINK-16094.
        --EXPECT_HMIRESPONSE(RequestId,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
        EXPECT_HMIRESPONSE(RequestId)
        :Do(function(_,data)            
          --hmi side: send request SDL.OnAllowSDLFunctionality
          --self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", {allowed = true, source = "GUI", device = {id = config.deviceMAC, name = "127.0.0.1"}})
          self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", {allowed = true, source = "GUI", device = {id = deviceMAC, name = "127.0.0.1"}})

          --hmi side: expect BasicCommunication.ActivateApp request
          EXPECT_HMICALL("BasicCommunication.ActivateApp")
          :Do(function(_,data)
            --hmi side: sending BasicCommunication.ActivateApp response
            self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
          end)
          :Times(AnyNumber())
        end)

      end
    end)
    
    --mobile side: expect notification
    EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL", systemContext = "MAIN"}) 
  end
  --End Precondition.3

-- --///////////////////////////////////////////////////////////////////////////--
-- --Sending 300 Alert requests
-- for n = 1, 300 do
--   Test["AlertRequest"..tostring(n)] = function(self)
--     --mobile side: Alert request  
--       self.mobileSession:SendRPC("Alert",
--                   {
--                     alertText1 = "alertText1",
--                     alertText2 = "alertText2",
--                     alertText3 = "alertText3",
--                     ttsChunks = 
--                     { 
                      
--                       { 
--                         text = "TTSChunk",
--                         type = "TEXT",
--                       } 
--                     }, 
--                     duration = 3000,
--                     softButtons = 
--                     { 
                      
--                       { 
--                         type = "TEXT",
--                         text = "Close" ,
--                         isHighlighted = true,
--                         softButtonID = 3,
--                         systemAction = "DEFAULT_ACTION",
--                       }
--                     }
                  
--                   })
--   end
-- end


--///////////////////////////////////////////////////////////////////////////--
--Check TOO_MANY_PENDING_REQUEST resultCode in Alert response from HMI
  function Test:Alert_TooManyPendingRequest()
    local numberOfRequest = 20
    for n = 1, numberOfRequest do
    --mobile side: Alert request  
      self.mobileSession:SendRPC("Alert",
                  {
                    alertText1 = "alertText1",
                    alertText2 = "alertText2",
                    alertText3 = "alertText3",
                    ttsChunks = 
                    { 
                      
                      { 
                        text = "TTSChunk",
                        type = "TEXT",
                      } 
                    }, 
                    duration = 3000
                  
                  })
  end

  EXPECT_RESPONSE("Alert")
    :ValidIf(function(exp,data)
      if 
        data.payload.resultCode == "TOO_MANY_PENDING_REQUESTS" then
          n = n+1
          print(" \27[32m ChangeRegistration response came with resultCode TOO_MANY_PENDING_REQUESTS \27[0m ")
        return true
      elseif 
        exp.occurences == numberOfRequest and n == 0 then 
          print(" \27[36m  Response ChangeRegistration with resultCode TOO_MANY_PENDING_REQUESTS did not came \27[0m")
          return false
      elseif 
        data.payload.resultCode == "GENERIC_ERROR" then
          print(" \27[32m  ChangeRegistration response came with resultCode GENERIC_ERROR \27[0m")
          return true
      else
          print(" \27[36m  ChangeRegistration response came with resultCode "..tostring(data.payload.resultCode) .."\27[0m")
          return false
        end
      end)
      :Times(AtLeast(numberOfRequest))
      :Timeout(15000)

  --expect absence of OnAppInterfaceUnregistered
  EXPECT_NOTIFICATION("OnAppInterfaceUnregistered")
  :Times(0)

  --expect absence of BasicCommunication.OnAppUnregistered
  EXPECT_HMICALL("BasicCommunication.OnAppUnregistered")
  :Times(0)

  DelayedExp()
  end















