-- This class provides the camera roll view of the Camera app.
-- It allows browsing, viewing and deleting image files taken with the camera.

import "menu"

local pd <const> = playdate
local gfx <const> = pd.graphics

local ImagesRoot <const> = "DCIM/.pdi/"
local MenuRoll <const> = "CAMERA ROLL"
local MenuTimestamp <const> = "SHOW DATE"
local MenuDelete <const> = "DELETE ?"

class('Roll', { images = nil, _menu = nil }).extends()

function Roll:init()
  Roll.super.init(self)
  self.currentImagePath = nil
  self.showFilename = false
end

function Roll:load()
  self._menu = nil
  self.currentImage = gfx.image.new(400, 240)
  self.currentImageSprite = gfx.sprite.new()
  self.currentImageSprite:setCenter(0, 0)

  self.images = pd.file.listFiles(ImagesRoot)

  if (self.images ~= nil and #self.images > 0) then
    table.sort(self.images, function(a, b) return a:lower() > b:lower() end)
    for i, v in ipairs(self.images) do print(v) end

    self._menu = Menu({
      {
        ["title"] = MenuRoll,
        ["images"] = self.images,
        ["values"] = self.images,
        ["path"] = ImagesRoot,
        ["wraps"] = true,
        ["height"] = 60,
        ["scrollDuration"] = 300,
      },
      {
        ["title"] = MenuTimestamp,
        ["options"] = { "Off", "On" },
        ["values"] = { 0, 1 },
        ["default"] = self.showFilename and 2 or 1,
        ["wraps"] = true,
      },
      {
        ["title"] = MenuDelete,
        ["options"] = { "Press A\nto delete" },
        ["values"] = { 0 },
        ["default"] = 1,
      },
    })
    self._menu.sprite:add()
    self.currentImagePath = self.images[1]
    self:viewImage()
  else
    self:showEmptyMessage()
  end
end

function Roll:unload()
  self.images = nil
  self.currentImageSprite:remove()
  self.currentImageSprite = nil
  self.currentImage = nil
  if self._menu ~= nil then
    self._menu:remove()
  end
  self._menu = nil
end

function Roll:update()
  if (self._menu == nil) then
    return
  end

  local subTitle, action = self._menu:update()
  if subTitle == MenuRoll then
    self.currentImagePath = action
    self:viewImage()
  elseif subTitle == MenuTimestamp then
    self.showFilename = action == 1
    self:viewImage()
  end
  gfx.sprite.update()
end

function Roll:viewImage()
  gfx.pushContext(self.currentImage)

  local img = gfx.image.new(ImagesRoot .. self.currentImagePath)
  local width, height = img:getSize()
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
  img:draw(80, 0)

  if self.showFilename then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(80, 220, 400, 20)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.setFontFamily(gfx.getSystemFont())
    local day = self.currentImagePath:sub(1, 4) .. "/" .. self.currentImagePath:sub(6, 7) .. "/" .. self.currentImagePath:sub(9, 10)
    local time = self.currentImagePath:sub(12, 13) .. ":" .. self.currentImagePath:sub(15, 16) .. ":" .. self.currentImagePath:sub(18, 19)
    local text = "*" .. day .. "* at " .. time
    if (self.currentImagePath:sub(21, 25) == "movie") then
      text = "(Movie) " .. text
    end
    gfx.drawTextAligned(text, 400, 222, kTextAlignment.right)
  end

  gfx.popContext()

  self.currentImageSprite:setImage(self.currentImage)
  self.currentImageSprite:add()
  gfx.sprite.update()
end

function Roll:action()
  if self._menu == nil then
    return
  end
  local _, _, subMenuTitle = self._menu:getCurrentSubmenu()
  if subMenuTitle == MenuDelete then
    local imageToDelete = self.currentImagePath
    local currentImagePos = self._menu.subMenus[1]:getSelectedRow()
    print("Deleting " .. imageToDelete)
    self:unload()
    pd.file.delete(ImagesRoot .. imageToDelete)
    if (imageToDelete:sub(21, 25) == "movie") then
      print("deleting " .. "Movies/" .. imageToDelete:sub(1, -11) .. ".gif")
      pd.file.delete("Movies/" .. imageToDelete:sub(1, -11) .. ".gif")
    else
      pd.file.delete("DCIM/" .. imageToDelete:sub(1, -4) .. "gif")
    end
    self:load()
    if self._menu ~= nil then
      local newRow <const> = math.max(currentImagePos - 1, 1)
      self._menu.subMenus[1]:setSelectedRow(newRow)
      self._menu.subMenus[1]:scrollToRow(newRow, true)
    end
  end
end

function Roll:showEmptyMessage()
  gfx.setFontFamily(gfx.getSystemFont())
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 0, 400, 240)

  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  local font <const> = gfx.getFont()
  local message <const> = "The Camera roll is empty. Press Ⓑ to exit."
  font:drawTextAligned(message, 200, 120, kTextAlignment.center)
end
