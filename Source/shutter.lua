-- A simple camera shutter effect animation.

local pd <const> = playdate
local gfx <const> = pd.graphics

class('Shutter', { anim = nil, openAnim = nil, rad = 0 }).extends(gfx.sprite)

function Shutter:init(x, y, width, height)
  Shutter.super.init(self)
  self:setCenter(0, 0)
  self.rad = math.sqrt(width * width + height * height) / 2
  self:setBounds(x, y, width, height)
end

function Shutter:update()
  if (self.anim == nil) then
    return
  end
  if (self.anim:ended()) then
    return
  end
  local stencil = gfx.image.new(self.width, self.height)
  gfx.pushContext(stencil)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 0, self.width, self.height)
  gfx.setColor(gfx.kColorClear)
  gfx.fillCircleAtPoint(self.width / 2, self.height / 2, self.anim:currentValue())
  gfx.popContext()
  self:setImage(stencil)
  Shutter.super.update(self)
end

function Shutter:open()
  self.anim = gfx.animator.new(250, 0, self.rad, pd.easingFunctions.inOutExpo, 600)
  self.anim.reverses = false
  self.anim.repeatCount = 0
end

function Shutter:snap(speed)
  self.anim = gfx.animator.new(250, self.rad, 0, pd.easingFunctions.inOutExpo)
  self.anim.reverses = true
  self.anim.repeatCount = 0
end