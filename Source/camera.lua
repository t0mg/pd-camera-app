-- This class handles communication with the Teensy module over serial.

local timer <const> = playdate.timer
local frameTimer <const> = playdate.frameTimer

-- enum StatusCode
-- {
--   INIT = 48,         // 0 in ASCII
--   READY = 49,        // 1
--   STREAMING = 50,    // 2
--   OK = 51,           // 3
--   ERROR = 52         // 4
-- };

class('Camera', {
  status = nil,
  _stopping = false,
  _debug = true,
  _frameBuffer = nil,
  _frameSnapped = false,
  _newFrameCallback = nil,
  _statusChangeCallback = nil,
  _connectTimer = nil,
  _healthCheckTimer = nil,
}).extends()

Camera.Status = {
  UNKNOWN = -1,
  DISCONNECTED = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  -- REQUESTING_STREAM = '3',
  STREAMING = 3,
  -- SNAPPING = 6,
  STOPPING_STREAM = 4,
}

-- Messages sent to the Teensy over serial.
Camera.Message = {
  CONNECT = 'connect',
  DISCONNECT = 'disconnect',
  REQUEST_FRAME = 'readyForNextFrame',
  SET_DITHER = 'dither:',
  SET_BRIGHTNESS = 'brightness:',
  SET_CONTRAST = 'contrast:',
  SET_THRESHOLD = 'threshold:',
  SET_MIRROR = 'mirror:',
}

-- Status codes received from the Teensy over serial.
Camera.Code = {
  INIT = 0,
  READY = 1,
  STREAMING = 2,
  OK = 3,
  ERROR = 4
}

Camera.DitherTypes = { "atkinson", "stucki", "fs", "fast", "bayer", "random", "threshold" }

function Camera:sendMessage(message)
  print("Camera:" .. message)
end

function Camera:debugPrint(info)
  if (self._debug) then
    print("[camera.lua] " .. info)
  end
end

function Camera:stopConnectionPing()
  if (self._connectTimer ~= nil) then
    self._connectTimer:remove()
    self._connectTimer = nil
  end
end

function Camera:connect()
  self:stopConnectionPing()
  self.status = Camera.Status.UNKNOWN
  self:sendMessage(Camera.Message.CONNECT)
  local this = self
  self._connectTimer = timer.new(2000, function()
    this:connect()
  end)
end

function Camera:disconnect()
  self:stopConnectionPing()
  self.status = Camera.Status.INIT
  self:sendMessage(Camera.Message.CONNECT)
end

function Camera:resetHealthcheck()
  local this = self
  if (self._healthCheckTimer ~= nil) then
    self._healthCheckTimer:remove()
  end
  self._healthCheckTimer = timer.new(4000, function()
    this:debugPrint("Health check failed, marking camera status as unknown.")
    this:connect()
    if (this._statusChangeCallback ~= nil) then
      this._statusChangeCallback(this.status)
    end
  end)
end

function Camera:init()
  Camera.super.init(self)
  self.status = Camera.Status.DISCONNECTED
  self:resetHealthcheck()
  self:connect()
end

function Camera:processStatusCode(code)
  self:debugPrint("Processing status code " .. code)
  self:resetHealthcheck()
  local message = nil
  local prevStatus <const> = self.status
  if (code == Camera.Code.INIT) then
    message = "initializing"
    self.status = Camera.Status.INIT
  elseif (code == Camera.Code.READY) then
    message = "ready"
    self.status = Camera.Status.CONNECTED
    self:stopConnectionPing()
  elseif (code == Camera.Code.STREAMING) then
    message = "streaming"
    if (prevStatus ~= Camera.Status.STOPPING_STREAM) then
      self.status = Camera.Status.STREAMING
    end
  elseif (code == Camera.Code.OK) then
    message = "command ack"
  elseif (code == Camera.Code.ERROR) then
    message = "command error"
  else
    self.status = Camera.Status.UNKNOWN
    message = "Received unknown status code " .. code
  end
  self:debugPrint("[Teensy message] " .. message)
  if (prevStatus ~= self.status and self._statusChangeCallback ~= nil) then
    self:debugPrint("Camera status changed to " .. self.status)
    self._statusChangeCallback(self.status)
  end
end

function Camera:startStream()
  self._stopping = false
  if (self.status == Camera.Status.CONNECTED or self.status == Camera.Status.STOPPING_STREAM) then
    self:sendMessage(Camera.Message.REQUEST_FRAME)
  elseif (self.status == Camera.Status.STREAMING) then
    self:debugPrint("Already started")
  else
    self:debugPrint("Can't start stream, Camera is not ready")
  end
end

function Camera:stopStream()
  if (self.status == Camera.Status.STREAMING) then
    self.status = Camera.Status.STOPPING_STREAM
    self._stopping = true
    self:connect()
  else
    self:debugPrint("Can't stop stream, Camera is not streaming")
  end
end

function Camera:processImage(data)
  if (self._stopping) then
    return
  end
  if (self.status == Camera.Status.STREAMING) then
    self._frameBuffer = _cameraProcessMessage(data) -- C function injected into Lua runtime
    self._frameSnapped = false
    if (self._newFrameCallback ~= nil) then
      self._newFrameCallback(self._frameBuffer)
    end
    frameTimer.performAfterDelay(2, self.requestFrame, self)
  end
end

function Camera:requestFrame()
  if (self.status == Camera.Status.STREAMING) then
    self:sendMessage(Camera.Message.REQUEST_FRAME)
  end
end

function Camera:onNewFrame(callback)
  self._newFrameCallback = callback
end

function Camera:onStatusChange(callback)
  self._statusChangeCallback = callback
end

function Camera:canSnap()
  return self._frameBuffer ~= nil and self.status == Camera.Status.STREAMING
end

function Camera:snap()
  if (self._frameBuffer ~= nil) then
    self._frameSnapped = true
    return self._frameBuffer:copy()
  end
  return nil
end

function Camera:snapIfNewFrame()
  if (not self._frameSnapped) then
    return self:snap()
  end
  return nil
end

function Camera:setDebugMode(enable)
  self._debug = enable
end

function Camera:setDitherMode(mode)
  if table.indexOfElement(Camera.DitherTypes, mode) ~= nil then
    self:sendMessage(Camera.Message.SET_DITHER .. mode)
  end
end

function Camera:setBrightness(value)
  if value > 0 and value < 256 then
    self:sendMessage(Camera.Message.SET_BRIGHTNESS .. value)
  end
end

function Camera:setContrast(value)
  if value > 0 and value < 256 then
    self:sendMessage(Camera.Message.SET_CONTRAST .. value)
  end
end

function Camera:setThreshold(value)
  if value > 0 and value < 256 then
    self:sendMessage(Camera.Message.SET_THRESHOLD .. value)
  end
end

function Camera:setMirror(value)
  if value >= 0 and value <= 1 then
    self:sendMessage(Camera.Message.SET_MIRROR .. value)
  end
end

-- Lua version of the frame decoding logic; super slow but kept here for posterity.
-- Frames are now decoded in C for better performance (see src/main.c).

-- function frameLua(message)
-- 	print("Procesing frame")
-- 	pd.graphics.clear(pd.graphics.kColorWhite)
-- 	pd.graphics.setColor(pd.graphics.kColorBlack)
-- 	local cursor = pd.geometry.point.new(0, -1)
-- 	for i = 0, string.len(message) do
-- 			if math.fmod(i, 50) == 0 then
-- 					cursor:offset(0, 1)
-- 					cursor.x = 0
-- 			end
-- 			local byte = string.unpack("B", message, i)
-- 			for j = 7, 0, -1 do
-- 					local bit = (byte >> j) & 1
-- 					if (bit == 0) then
-- 							pd.graphics.drawPixel(cursor)
-- 					end
-- 					cursor:offset(1, 0)
-- 			end
-- 	end
-- 	print("Ready for next frame")
-- end
