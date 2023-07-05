-- This class provides the main view of the Camera app.
-- It shows the camera feed and image settings, and can record images to the filesystem. 

import "shutter"
import "menu"
import "progressbar"

local pd <const> = playdate
local gfx <const> = pd.graphics
local datastore <const> = pd.datastore
local timer <const> = pd.timer

class('Viewfinder', {
  _camera = nil,
  _frame = nil,
  _shutter = nil,
  _menu = nil,
  _enabled = false,
  _videoMode = false,
  _recording = false,
  _crankTicks = 0,
  _currMovie = nil,
  _currFrame = 0,
  _maxFrames = 100,
  _videoPalette = 1,
  _altControl = false,
}).extends()

function Viewfinder:init(camera)
  Viewfinder.super:init(self)
  self._camera = camera
  self._frame = gfx.sprite.new()
  self._frame:setCenter(0, 0)
  self._frame:moveTo(80, 0)
  self._shutter = Shutter(80, 0, 320, 240)
  self._shutter:setZIndex(100)
  self._progress = ProgressBar(240, 16, 320, 32)
  self._progress:setZIndex(99)
  self._progress:remove()

  self._menu = Menu({
    {
      ["title"] = "FILTER",
      ["options"] = { "Stucki", "Atkinson", "Floyd Steinberg", "Fast", "Bayer", "Random", "Threshold" },
      ["values"] = { "stucki", "atkinson", "fs", "fast", "bayer", "random", "threshold" },
      ["wraps"] = true,
    },
    {
      ["title"] = "BRIGHTNESS",
      ["options"] = { "+3", "+2", "+1", "0", "-1", "-2", "-3"},
      ["values"] = { 112, 96, 80, 64, 56, 48, 32 },
      ["default"] = 4,
    },
    {
      ["title"] = "CONTRAST",
      ["options"] = { "+3", "+2", "+1", "0", "-1", "-2", "-3" },
      ["values"] = { 112, 96, 80, 64, 56, 48, 32 },
      ["default"] = 4,
    },
    {
      ["title"] = "THRESHOLD ADJUST",
      ["options"] = { "+4", "+3", "+2", "+1", "0", "-1", "-2", "-3", "-4" },
      ["values"] = { 160, 152, 144, 136, 128, 120, 112, 104, 96 },
      ["default"] = 5,
      ["trigger"] = { ["col"] = 1,["row"] = 7 },
    },
    {
      ["title"] = "SELFIE MODE",
      ["options"] = { "Off", "On" },
      ["values"] = { 0, 1 },
      ["default"] = 1,
      ["wraps"] = true,
    },
    {
      ["title"] = "VIDEO MODE",
      ["options"] = { "Off", "On" },
      ["values"] = { 0, 1 },
      ["default"] = 1,
      ["wraps"] = true,
    },
    {
      ["title"] = "VIDEO PALETTE",
      ["options"] = { "Black & White", "Simulator", "Half of DMG-001", "Purple & Yellow" },
      ["values"] = { 1, 2, 3, 4 },
      ["default"] = 1,
      ["wraps"] = true,
      ["trigger"] = { ["col"] = 6, ["row"] = 2 },
    },
  })

  local this = self
  self._camera:onNewFrame(function (image)
    this:drawFrame(image)
    if (this._recording and not this._processing) then
      this._currFrame = this._currFrame + 1
      this:recordFrame(image)
      this._progress:set(this._currFrame / this._maxFrames * 100, "*REC* - Memory usage ")
      if (this._currFrame >= this._maxFrames) then
        this:stopRecording()
      end
      gfx.sprite.update()
    end
  end)
end

function Viewfinder:setAltControl(value)
  self._altControl = value
  if (self._videoMode and not self._recording and not self._processing) then
    self._progress:message(self:_getRecordMessage(), gfx.kColorWhite)
  end
end

function Viewfinder:getAltControl()
  return self._altControl
end

function Viewfinder:enable()
  if not self._enabled then
      self._camera:startStream()
      self._frame:add()
      self._menu:add()
      self._shutter:add()
      self:drawFrame(gfx.image.new("images/testcard.png"))
      if(self._videoMode) then
        self._progress:add()
      end
      self._shutter:open()
  end
  self._enabled = true
end

function Viewfinder:disable()
  if self._enabled then
    self._enabled = false
    self._camera:stopStream()
    self._frame:remove()
    self._shutter:remove()
    self._menu:remove()
    self._progress:remove()
  end
end

function Viewfinder:drawFrame(image)
  self._frame:setImage(image)
end

function Viewfinder:recordFrame(image)
  if (not self._recording or not self._currMovie) then
    return
  end
  local filename = self._currFrame .. ".pdi"
  -- add leading zeros to make sure we can list the files in order
  if (self._currFrame < 100) then
    filename = "0" .. filename
    if (self._currFrame < 10) then
      filename = "0" .. filename
    end
  end
  if (self._currFrame == 1) then
    -- first frame will act as thumbnail for the camera roll
    local thumb = image:copy()
    gfx.pushContext(thumb)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, 32, 240)
    gfx.fillRect(288, 0, 32, 240)
    gfx.setColor(gfx.kColorWhite)
    for i = 0, 9, 1 do
      gfx.fillRoundRect(6, 24 * i + 4, 20, 16, 4)
      gfx.fillRoundRect(294, 24 * i + 4, 20, 16, 4)
    end
    gfx.popContext()
    datastore.writeImage(thumb, "DCIM/.pdi/" .. self._currMovie .. "_movie.pdi")
  end
  datastore.writeImage(image, "Movies/.temp/" .. self._currMovie .. "/" .. filename)
end

function Viewfinder:getTimestamp()
  local time = pd.getTime()
  local pad = function(prop)
      if (prop < 10) then
          return "0" .. prop
      end
      return prop
  end
  return table.concat({ time.year, pad(time.month), pad(time.day) }, "-") ..
      "_" .. table.concat({ pad(time.hour), pad(time.minute), pad(time.second) }, "-")
end

function Viewfinder:snap()
  if (not self._enabled or not self._camera:canSnap() or self._recording or self._processing) then
    return
  end

  self._camera:stopStream()
  self._shutter:snap(250)
  local snap = self._camera:snap()
  if (snap == nil) then
      return
  end

  local time  = pd.getTime()
  local ts <const> = self:getTimestamp()
  datastore.writeImage(snap, "DCIM/" .. ts .. ".gif")
  datastore.writeImage(snap, "DCIM/.pdi/" .. ts .. ".pdi")
  local cam = self._camera
  pd.timer.performAfterDelay(1000, function() cam:startStream() end)
end

function Viewfinder:_getRecordMessage()
  if (self._altControl) then
    return "Hold Ⓐ to record video"
  else
    return "🎣 to record video"
  end
end

function Viewfinder:_getGifProcessMessage()
  local message = "Creating "
  if (self._videoPalette == 2) then
    message = message .. "Simulator style"
  elseif (self._videoPalette == 3) then
    message = message .. "DMG-001 style"
  elseif (self._videoPalette == 4) then
    message = message .. "Purple & Yellow"
  else
    message = message .. "Black & White"
  end
  return message .. " gif "
end

function Viewfinder:_processGif()
  pd.resetElapsedTime()
  local filepaths <const> = pd.file.listFiles("Movies/.temp/" .. self._currMovie)
  if (filepaths ~= nil) then
    local msg <const> = self:_getGifProcessMessage()
    _createGif("Movies/" .. self._currMovie .. ".gif", self._videoPalette) -- This function is implemented in ../src/main.c
    for index, value in ipairs(filepaths) do
      local res = _appendImage("Movies/.temp/" .. self._currMovie .. "/" .. value)
      self._progress:set(index / #filepaths * 100, msg, gfx.kColorBlack)
      gfx.sprite.update()
      coroutine.yield()
    end
    _closeGif()
    coroutine.yield()
    pd.file.delete("Movies/.temp/" .. self._currMovie, true)
    coroutine.yield()
  end
  print("GIF created in " .. pd.getElapsedTime())
  self._progress:exitFullHeight()
  self._progress:message(self:_getRecordMessage(), gfx.kColorWhite)
  self._processing = false
  self._camera:startStream()
end

function Viewfinder:enableVideoMode()
  if (self._videoMode) then
    return
  end
  self._videoMode = true
  if (self._processing) then
    return
  end
  self._progress:message(self:_getRecordMessage(), gfx.kColorWhite)
  self._progress:add()
  self._progress:slideIn()
end

function Viewfinder:disableVideoMode()
  if (self._videoMode == false) then
    return
  end
  self._videoMode = false
  if (not self._processing) then
    self._progress:slideOut()
  end
end

function Viewfinder:startRecording()
  if (not self._videoMode) then
    return
  end
  if (self._recording or self._processing) then
    return
  end
  self._currMovie = self:getTimestamp()
  self._currFrame = 0
  self._recording = true
end

function Viewfinder:stopRecording()
  if (not self._videoMode) then
    return
  end
  if (not self._recording or self._processing) then
    return
  end
  self._recording = false
  self._processing = true
  self._camera:stopStream()
  self._progress:message(self:_getGifProcessMessage(), gfx.kColorBlack)
  self._progress:goFullHeight()
  self._processGifOnUpdate = true
end

function Viewfinder:onCrank()
  local this = self

  -- busy rendering the previous video, ignore crank
  if (self._processing) then
    return
  end

  if (self._crankTimer ~= nil) then
    self._crankTimer:remove()
  end

  -- cranking just started; allow for a delay before starting to record
  if (not self._recording) then
    self._crankTicks = self._crankTicks + 1
    if (self._crankTicks > 30) then
      self:startRecording()
    end
  end

  -- stop everything when the crank stops ticking for more than 300ms
  self._crankTimer = timer.new(300, function()
    this._crankTicks = 0
    if (this._recording) then
      this:stopRecording()
    end
  end)
end

function Viewfinder:update()
  self._shutter:update()
  local subTitle, action = self._menu:update()
  if subTitle == "FILTER" then
      self._camera:setDitherMode(action)
  elseif subTitle == "BRIGHTNESS" then
      self._camera:setBrightness(action)
  elseif subTitle == "CONTRAST" then
      self._camera:setContrast(action)
  elseif subTitle == "THRESHOLD ADJUST" then
      self._camera:setThreshold(action)
  elseif subTitle == "SELFIE MODE" then
      self._camera:setMirror(action)
  elseif subTitle == "VIDEO MODE" then
    if action == 0 then
      self:disableVideoMode()
    else
      self:enableVideoMode()
    end
  elseif subTitle == "VIDEO PALETTE" then
    self._videoPalette = action
  end

  gfx.sprite.update()

  -- we need the gif creation to be initiated from update for yeield to work
  if (self._processGifOnUpdate and self._currMovie ~= nil) then
    self._processGifOnUpdate = false
    self:_processGif()
  end
end
