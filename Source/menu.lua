-- A somewhat generic and flexible 2d menu that can be configured with a table.
-- Might actually be useful in other projects.

local pd <const> = playdate
local gfx <const> = pd.graphics

class('Buffer', {_first = 0, _last = -1, _values = {}}).extends()

function Buffer:init(size)
  Buffer.super:init(self)
  self.size = size
end

function Buffer:push(key, value)
  local first = self._first - 1
  self._values[key] = value
  self._first = first
  self[first] = key
  while self._last - self._first > self.size do
    self:pop()
  end
end

function Buffer:get(key)
  return self._values[key]
end

function Buffer:pop()
  local _last = self._last
  if self._first > _last then error("Buffer is empty") end
  local key = self[_last]
  self[_last] = nil
  self._last = _last - 1
  local value = self._values[key]
  self._values[key] = nil
  return key, value
end

class('Menu', {
  width = 80,
  height = 240,
  left = 0,
  top = 0,
  isLocked = {},
  menus = {}}).extends()

function Menu:init(menus)
  self.menus = menus
  Menu.super.init(self)

  self.mainGrid = pd.ui.gridview.new(self.width, self.height)
  self.mainGrid:setNumberOfColumns(#self.menus)
  self.mainGrid:setNumberOfRows(1)
  self.sprite = gfx.sprite.new()
  self.sprite:setCenter(0, 0)
  self.sprite:moveTo(0, 0)
  self.fontFamily = gfx.font.newFamily({ [gfx.font.kVariantNormal] = "fonts/Mini Mono" })

  local menuSelf = self

  self.menuTitles = {}
  self.subMenus = {}

  for i=1, #self.menus do
    local menu = self.menus[i]
    table.insert(self.menuTitles, menu["title"]);
    local isImageMenu = menu["images"] ~= nil

    local itemCount = 0
    if isImageMenu == true then
      itemCount = #menu["images"]
    else
      itemCount = #menu["options"]
    end

    local cellHeight = menu["height"] or math.max((self.height - 34) / itemCount, 16)
    local subMenu = pd.ui.gridview.new(self.width, cellHeight)
    if type(menu["scrollDuration"]) == "number" then
      subMenu:setScrollDuration(menu["scrollDuration"])
      subMenu.scrollEasingFunction = pd.easingFunctions.inOutQuad
    end
    
    if isImageMenu == true then
      local rootPath = menu["path"]
      subMenu.imageBuffer = Buffer(20)
      subMenu.bufferHistory = {}
      function subMenu:drawCell(section, row, column, selected, x, y, width, height)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(x, y, width, height)
        if selected then
          gfx.setColor(gfx.kColorBlack)
          gfx.fillRoundRect(x + 1, y, width - 2, height, 4)
        end

        local imgName = menu["images"][row]
        local img = self.imageBuffer:get(imgName)

        -- load image, compute thumbnail and store in memory
        if img == nil then
          -- print(" + load image " .. row)
          img = gfx.image.new(rootPath .. imgName)
          local _, height = img:getSize()
          img = img:blurredImage(1, 1, gfx.image.kDitherTypeScreen, true)
          -- we need the scale to be 1/2n+1 for the dithered image to scale decently
          local maxScale = cellHeight/height
          local scale = 1
          while (maxScale < 1/scale) do
            scale = scale + 2
          end
          img = img:scaledImage(1/scale)
          self.imageBuffer:push(imgName, img)
        end

        -- print("draw image " .. row)
        img:drawCentered(x + width/2, y + height/2)

      end
    else
      function subMenu:drawCell(section, row, column, selected, x, y, width, height)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(x, y, width, height)
        gfx.setColor(gfx.kColorBlack)
        if selected then
          gfx.fillRoundRect(x + 1, y, width - 2, height, 4)
          gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
          gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
        menuSelf:_drawCenteredMultiline(menu["options"][row], x + 1, y, width - 2, height)
      end
    end

    subMenu:setNumberOfRows(itemCount)
    local default = menu["default"] or 1
    subMenu:setSelectedRow(default)
    table.insert(self.subMenus, subMenu)
  end

  function self.mainGrid:drawCell(section, row, column, selected, x, y, width, height)
    local menuCell = gfx.image.new(width, height)
    gfx.pushContext(menuCell)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.setFontFamily(menuSelf.fontFamily)
    local text = menuSelf.menuTitles[column]
    menuSelf:_drawCenteredMultiline(text, x, 0, width, 32)
    local sub = menuSelf.subMenus[column]
    sub:drawInRect(x, y + 33, menuSelf.width, menuSelf.height - 33)
    gfx.popContext()

    if menuSelf.isLocked[column] then
      menuCell:drawFaded(x, y, 0.5, gfx.image.kDitherTypeBayer2x2)
    else
      menuCell:draw(x, y)
    end
  end

  self:_updateLocks()
end

function Menu:_drawCenteredMultiline(text, x, y, width, height)
  local font <const> = gfx.getFont()
  local fontHeight = font:getHeight()
  if string.len(text) > 9 then
    local centeredText = gfx.image.new(width, height)
    gfx.pushContext(centeredText)
    local _, textH = gfx.drawTextInRect(text, 0, 0, width, height, nil, nil, kTextAlignment.center)
    gfx.popContext()
    centeredText:draw(x, y + (height/2 - textH/2) + 2)
  else
  gfx.drawTextInRect(text, x, y + (height/2 - fontHeight/2) + 2, width, height, nil, nil, kTextAlignment.center)
  end
end

function Menu:_updateLocks()
  for i=1, #self.menus do
    self.isLocked[i] = false
    local triggerInfo = self.menus[i]["trigger"]
    if triggerInfo ~= nil and triggerInfo["row"] ~= self.subMenus[triggerInfo["col"]]:getSelectedRow() then
      self.isLocked[i] = true
    end
  end
end

function Menu:getCurrentSubmenu()
  local _, _, col = self.mainGrid:getSelection()
  return self.subMenus[col], col, self.menuTitles[col]
end

function Menu:update()
  local action = nil
  local subMenu = nil
  if (pd.buttonJustPressed(pd.kButtonLeft) or pd.buttonJustPressed(pd.kButtonRight)) then
    local _, _, col = self.mainGrid:getSelection()
    self.prevSubIndex = col
    if pd.buttonJustPressed(pd.kButtonLeft) then
      self.mainGrid:selectPreviousColumn(true)
    else
      self.mainGrid:selectNextColumn(true)
    end
  end

  if (pd.buttonJustPressed(pd.kButtonUp) or pd.buttonJustPressed(pd.kButtonDown)) then
    local sub, subIndex = self:getCurrentSubmenu()
    if self.isLocked[subIndex] then
      return
    end
    local wraps = self.menus[subIndex]["wraps"] or false
    local row = sub:getSelectedRow()
    if pd.buttonJustPressed(pd.kButtonUp) then
      sub:selectPreviousRow(wraps)
    else
      sub:selectNextRow(wraps)
    end
    local newRow = sub:getSelectedRow()
    if (row ~= newRow) then
      action = self.menus[subIndex]["values"][newRow]
      subMenu = self.menus[subIndex]["title"]
      self:_updateLocks()
      self.mainGrid.needsDisplay = true
      local scrollDuration = self.menus[subIndex]["scrollDuration"]
      if type(scrollDuration) == "number" then
        self.displayTimer = pd.timer.new(2 * scrollDuration)
      end
    end
  end

  if (self.displayTimer ~= nil and self.displayTimer.timeLeft > 0) or self.mainGrid.needsDisplay then
    local gridviewImage = gfx.image.new(self.width, self.height)
    gfx.pushContext(gridviewImage)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, self.width, 32)
    self.mainGrid:drawInRect(self.left, self.top, self.width, self.height)
    gfx.popContext()
    self.sprite:setImage(gridviewImage)
  end

  return subMenu, action
end

function Menu:add()
  self.sprite:add()
end

function Menu:remove()
  self.sprite:remove()
end