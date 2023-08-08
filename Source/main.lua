import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/frameTimer"
import "CoreLibs/ui"
import "CoreLibs/animator"

import "camera"
import "viewfinder"
import "roll"

local pd <const> = playdate
local gfx <const> = pd.graphics
local timer <const> = pd.timer

-- home, roll, viewfinder
local state = 'home'
local cameraReady = false

-- Camera class singleton. The Teensy-side code calls _cameraImage and _cameraStatus
-- which need to be declared and connected to the singleton instance.

local camera = Camera()

camera:onStatusChange(function(newCameraStatus)
  local prevCameraReady <const> = cameraReady
  if (newCameraStatus < 2) then
    cameraReady = false
  else
    cameraReady = true
  end
  if (state == 'home' and prevCameraReady ~= cameraReady) then
    drawHomeScreen()
  end
end)

function _cameraImage(message)
  camera:processImage(message)
end

function _cameraStatus(statusCode)
  print("received new status code " .. statusCode)
  camera:processStatusCode(tonumber(statusCode))
end

local viewfinder = Viewfinder(camera)
local roll = Roll()

function drawHomeScreen()
  local titleFontFamily <const> = gfx.font.newFamily({
    [gfx.font.kVariantNormal] = "fonts/noto-serif-regular"
  })
  gfx.setFontFamily(titleFontFamily)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 0, 400, 240)

  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  local font = gfx.getFont()
  local title <const> = "PD-Camera Mark III"
  font:drawTextAligned(title, 200, 80, kTextAlignment.center)

  gfx.setFontFamily(gfx.getSystemFont())
  font = gfx.getSystemFont()
  local status = "Waiting for camera module to connect..."
  if (cameraReady) then
    status = "Press Ⓐ to start the camera."
  end
  font:drawTextAligned(status, 200, 190, kTextAlignment.center)
  font:drawTextAligned("Press Ⓑ to view the camera roll.", 200, 220, kTextAlignment.center)
  
  local versionFontFamily <const> = gfx.font.newFamily({
    [gfx.font.kVariantNormal] = "fonts/Mini Mono"
  })
  gfx.setFontFamily(versionFontFamily)
  font = gfx.getFont()
  font:drawTextAligned("v" .. pd.metadata.version .. "." .. pd.metadata.buildNumber, 398, 2, kTextAlignment.right)
end

function pd.update()
  if (state == 'home') then
  elseif (state == 'viewfinder') then
    viewfinder:update()
  elseif (state == 'roll') then
    roll:update()
  end

  pd.timer.updateTimers()
  pd.frameTimer.updateTimers()
end

function pd.AButtonDown()
  if (state == 'home' and cameraReady) then
    state = 'viewfinder'
    viewfinder:enable()
  elseif (state == 'roll') then
    roll:action()
  elseif (state == 'viewfinder') then
    viewfinder:snap()
  end
end

function pd.AButtonHeld()
  if (state == 'viewfinder' and viewfinder:getAltControl()) then
    viewfinder:startRecording()
  end
end

function pd.AButtonUp()
  if (state == 'viewfinder' and viewfinder:getAltControl()) then
    viewfinder:stopRecording()
  end
end

function goHome()
  state = 'home'
  drawHomeScreen()
end

function pd.BButtonDown()
  if (state == 'home') then
    roll:load()
    state = 'roll'
  elseif (state == 'viewfinder') then
    viewfinder:disable()
    goHome()
  elseif (state == 'roll') then
    roll:unload()
    goHome()
  end
end

-- Unfortunately the magnets on the case make this unreliable
-- function pd.crankDocked()
--   viewfinder:disableVideoMode()
-- end

-- function pd.crankUndocked()
--   viewfinder:enableVideoMode()
-- end

function pd.cranked(change, acceleratedChange)
  if (state == 'viewfinder' and change > 0) then
    viewfinder:onCrank()
  end
end

function pd.gameWillTerminate()
  camera:disconnect()
end

function pd.deviceWillLock()
  if (state == 'viewfinder') then
    viewfinder:disable()
    goHome()
  end
  camera:disconnect()
end

function pd.deviceDidUnlock()
  camera:connect()
end

function pd.gameWillPause()
  if (state == 'viewfinder') then
    viewfinder:disable()
  else
    camera:disconnect()
  end
end

function pd.gameWillResume()
  if (state == 'viewfinder') then
    viewfinder:enable()
  else
    camera:connect()
  end
end

function init()
  local menu = pd.getSystemMenu()
  menu:addCheckmarkMenuItem("no crank", false, function(value)
    viewfinder:setAltControl(value)
  end)
  drawHomeScreen()
end

init()
