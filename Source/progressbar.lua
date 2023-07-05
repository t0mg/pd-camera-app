-- A progress bar with text label, that can animate and stretch vertically. 
-- Based on https://devforum.play.date/t/more-clarity-on-drawtext-and-sprites/6928/21

local pd <const> = playdate
local gfx <const> = pd.graphics

class('ProgressBar').extends(gfx.sprite)

function ProgressBar:init(x, y, width, height)
  self._baseX = x
  self._baseY = y
  self._baseWidth = width
  self._baseHeight = height
	self:setImage(gfx.image.new(width, height))
	self.progress = 0
	self:moveTo(x, y)
	self:add()
	self:set(0)
end

function ProgressBar:update()
  if (self._heightAnimator ~= nil and not self._heightAnimator:ended()) then
    self:draw()
  end
  ProgressBar.super.update(self)
end

function ProgressBar:draw()
  local height = self.height
  if (self._heightAnimator ~= nil) then
    height = self._heightAnimator:currentValue()
  end
  local bar_image = gfx.image.new(self.width, height, self.bgcolor)
  local progressWidth = self.progress/100 * (self.width - 4)
  gfx.setFontFamily(gfx.getSystemFont())
  local _, fontHeight = gfx.getTextSize("TEST")
	gfx.pushContext(bar_image)
	gfx.setLineWidth(2)
	gfx.drawRect(1, 1, self.width-2, height - 2)
  if (self.fillProgress) then
    gfx.setColor(self.bgcolor == gfx.kColorBlack and gfx.kColorWhite or gfx.kColorBlack)
    gfx.fillRect(2, 2, progressWidth, height - 4)
  end
	gfx.setImageDrawMode(gfx.kDrawModeNXOR)
	gfx.drawTextAligned(self.label, self.width/2, (height - fontHeight)/2 + 2, kTextAlignment.center)
	gfx.popContext()
	self:setImage(bar_image)
end

function ProgressBar:message(text, backgroundColor, fillProgress)
  self.label = text
  self.bgcolor = backgroundColor
  self.fillProgress = fillProgress
  self:draw()
end

function ProgressBar:set(percentage, optPrefixMessage, backgroundColor)
  optPrefixMessage = optPrefixMessage == nil and "" or optPrefixMessage
  local color = backgroundColor == nil and gfx.kColorWhite or backgroundColor
	self.progress = percentage
  self:message(optPrefixMessage .. math.floor(self.progress) .. "%", color, true)
end

function ProgressBar:slideIn()
  self:setAnimator(gfx.animator.new(
    250,
    pd.geometry.point.new(self._baseX, - self._baseHeight / 2),
    pd.geometry.point.new(self._baseX, self._baseY),
    pd.easingFunctions.inOutExpo))
end

function ProgressBar:slideOut()
  self:setAnimator(gfx.animator.new(
    250,
    pd.geometry.point.new(self._baseX, self._baseY),
    pd.geometry.point.new(self._baseX, - self._baseHeight / 2),
    pd.easingFunctions.inOutExpo))
end

function ProgressBar:goFullHeight()
  self:setAnimator(gfx.animator.new(
    600,
    pd.geometry.point.new(self._baseX, self._baseY),
    pd.geometry.point.new(self._baseX, 120),
    pd.easingFunctions.inOutExpo))
  self._heightAnimator = gfx.animator.new(
    600,
    self._baseHeight,
    240,
    pd.easingFunctions.inOutExpo
  )
end

function ProgressBar:exitFullHeight()
  self:setAnimator(gfx.animator.new(
    600,
    pd.geometry.point.new(self._baseX, 120),
    pd.geometry.point.new(self._baseX, self._baseY),
    pd.easingFunctions.inOutExpo))
  self._heightAnimator = gfx.animator.new(
    600,
    240,
    self._baseHeight,
    pd.easingFunctions.inOutExpo
  )
end