-----------------------------------------------------------------------
-- LibDBIcon-1.0
--
-- Allows addons to easily create a lightweight minimap icon as an alternative to heavier LDB displays.
--

local MAJOR, MINOR = "LibDBIcon-1.0", 45
assert(LibStub, MAJOR .. " requires LibStub")
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.objects = lib.objects or {}
lib.callbackRegistered = lib.callbackRegistered or nil
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.notCreated = lib.notCreated or {}
lib.radius = lib.radius or 5
lib.tooltip = lib.tooltip or CreateFrame("GameTooltip", "LibDBIconTooltip", UIParent, "GameTooltipTemplate")

local next, Minimap = next, Minimap
local isDraggingButton = false

local function getAnchors(frame)
  local x, y = frame:GetCenter()
  if not x or not y then return "CENTER" end
  local hhalf = (x > UIParent:GetWidth() * 2 / 3) and "RIGHT" or (x < UIParent:GetWidth() / 3) and "LEFT" or ""
  local vhalf = (y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
  return vhalf .. hhalf, frame, (vhalf == "TOP" and "BOTTOM" or "TOP") .. hhalf
end

local function onEnter(self)
  if isDraggingButton then return end

  for _, button in next, lib.objects do
    if button.showOnMouseover then
      button.fadeOut:Stop()
      button:SetAlpha(button.db.minimapPos and button.db.minimapPos.alpha or 1)
    end
  end

  local obj = self.dataObject
  if obj.OnTooltipShow then
    lib.tooltip:SetOwner(self, "ANCHOR_NONE")
    lib.tooltip:SetPoint(getAnchors(self))
    obj.OnTooltipShow(lib.tooltip)
    lib.tooltip:Show()
  elseif obj.OnEnter then
    obj.OnEnter(self)
  end
end

local function onLeave(self)
  lib.tooltip:Hide()

  if not isDraggingButton then
    for _, button in next, lib.objects do
      if button.showOnMouseover then
        button.fadeOut:Play()
      end
    end
  end

  local obj = self.dataObject
  if obj.OnLeave then
    obj.OnLeave(self)
  end
end

--------------------------------------------------------------------------------

local onDragStart, onDragStop

local function onUpdate(self)
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale

  local pos = math.deg(math.atan2(py - my, px - mx)) % 360
  self.db.minimapPos = pos
  self:ClearAllPoints()
  self:SetPoint("CENTER", Minimap, "CENTER", (lib.radius + (self.db.radius or 0)) * math.cos(math.rad(pos)),
    (lib.radius + (self.db.radius or 0)) * math.sin(math.rad(pos)))
end

function onDragStart(self)
  self:LockHighlight()
  self.isMouseDown = true
  self:SetScript("OnUpdate", onUpdate)
  isDraggingButton = true
  lib.tooltip:Hide()
  for _, button in next, lib.objects do
    if button.showOnMouseover then
      button.fadeOut:Stop()
      button:SetAlpha(button.db.minimapPos and button.db.minimapPos.alpha or 1)
    end
  end
end

function onDragStop(self)
  self:SetScript("OnUpdate", nil)
  self.isMouseDown = false
  self:UnlockHighlight()
  isDraggingButton = false
  for _, button in next, lib.objects do
    if button.showOnMouseover then
      button.fadeOut:Play()
    end
  end
end

local function onClick(self, b)
  if self.dataObject.OnClick then
    self.dataObject.OnClick(self, b)
  end
end

local function updatePosition(button, position)
  if not position then position = button.db.minimapPos or button.db.minimapPos or 0 end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", (lib.radius + (button.db.radius or 0)) * math.cos(math.rad(position)),
    (lib.radius + (button.db.radius or 0)) * math.sin(math.rad(position)))
end

local function createButton(name, object, db)
  local button = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
  button.dataObject = object
  button.db = db
  button:SetFrameStrata("MEDIUM")
  button:SetSize(31, 31)
  button:SetFrameLevel(8)
  button:RegisterForClicks("anyUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture(136477) --"Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
  local overlay = button:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture(136430) --"Interface\\Minimap\\MiniMap-TrackingBorder"
  overlay:SetPoint("TOPLEFT")
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture(136467) --"Interface\\Minimap\\UI-Minimap-Background"
  background:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  button.icon = icon
  button.background = background

  button.isMouseDown = false

  local fadeOut = button:CreateAnimationGroup()
  local alpha = fadeOut:CreateAnimation("Alpha")
  alpha:SetFromAlpha(1)
  alpha:SetToAlpha(0)
  alpha:SetDuration(0.2)
  alpha:SetSmoothing("OUT")
  alpha:SetScript("OnFinished", function() button:SetAlpha(0.2) end)
  button.fadeOut = fadeOut

  button:SetScript("OnEnter", onEnter)
  button:SetScript("OnLeave", onLeave)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnDragStart", onDragStart)
  button:SetScript("OnDragStop", onDragStop)

  button:SetMovable(true)

  updatePosition(button, db.minimapPos)
  return button
end

-- We could use a metatable.__index on lib.objects, but then we'd create
-- the icons when checking things like :IsRegistered, which is not necessary.
local function check(name)
  if lib.notCreated[name] then
    createButton(name, lib.notCreated[name].object, lib.notCreated[name].db)
    lib.objects[name] = lib.notCreated[name]
    lib.notCreated[name] = nil
  end
end

-- Wait a bit with the initial positioning to let any GetMinimapShape addons
-- load up.
if not lib.callbackRegistered then
  lib.callbackRegistered = true
  lib.callbacks:RegisterEvent("ADDON_LOADED")
  lib.callbacks:RegisterEvent("PLAYER_LOGIN")
end

function lib.callbacks:ADDON_LOADED(event, addonName)
  if addonName == "Blizzard_TimeManager" then
    TimeManagerClockButton:Hide()
  end
end

function lib.callbacks:PLAYER_LOGIN()
  for name, button in next, lib.objects do
    updatePosition(button.button, button.db.minimapPos)
    if button.db.hide then
      button.button:Hide()
    else
      button.button:Show()
    end
  end
  lib.callbacks:UnregisterEvent("PLAYER_LOGIN")
end

-- PUBLIC API

function lib:Register(name, object, db)
  if not object then error("Usage: LibDBIcon:Register(name, object[, db]): 'object' - nil or not LDB object", 2) end
  if lib.objects[name] or lib.notCreated[name] then
    error(
      "Usage: LibDBIcon:Register(name, object[, db]): 'name' - object '" .. name .. "' is already registered", 2)
  end
  if not db or not db.hide then
    if not db then db = {} end
  end

  -- Create the button immediately instead of deferring
  local button = createButton(name, object, db)
  lib.objects[name] = { button = button, db = db, callbacks = lib.callbacks }
  lib.objects[name].button:SetAttribute("type", "addon")
  lib.objects[name].button:SetAttribute("addon", name)
  if object.icon then lib.objects[name].button.icon:SetTexture(object.icon) end
  if db.hide then lib.objects[name].button:Hide() end
end

function lib:Lock(name)
  if not lib.objects[name] then return end
  if lib.objects[name].button:GetScript("OnDragStart") then
    lib.objects[name].button:SetScript("OnDragStart", nil)
    lib.objects[name].button:SetScript("OnDragStop", nil)
  end
end

function lib:Unlock(name)
  if not lib.objects[name] then return end
  lib.objects[name].button:SetScript("OnDragStart", onDragStart)
  lib.objects[name].button:SetScript("OnDragStop", onDragStop)
end

function lib:Hide(name)
  if not lib.objects[name] then return end
  lib.objects[name].button:Hide()
end

function lib:Show(name)
  check(name)
  local button = lib.objects[name]
  if button then
    button.button:Show()
    updatePosition(button.button, button.db.minimapPos)
  end
end

function lib:IsRegistered(name)
  return (lib.objects[name] and true) or (lib.notCreated[name] and true) or false
end

function lib:Refresh(name, db)
  if lib.objects[name] then
    lib.objects[name].db = db
    updatePosition(lib.objects[name].button, db.minimapPos)
    if db.hide then
      lib.objects[name].button:Hide()
    else
      lib.objects[name].button:Show()
    end
  elseif lib.notCreated[name] then
    lib.notCreated[name].db = db
  end
end

function lib:GetMinimapButton(name)
  return lib.objects[name] and lib.objects[name].button
end

do
  local function OnMinimapEnter()
    if isDraggingButton then return end
    for _, button in next, lib.objects do
      if button.showOnMouseover then
        button.fadeOut:Stop()
        button:SetAlpha(button.db.minimapPos and button.db.minimapPos.alpha or 1)
      end
    end
  end
  local function OnMinimapLeave()
    if isDraggingButton then return end
    for _, button in next, lib.objects do
      if button.showOnMouseover then
        button.fadeOut:Play()
      end
    end
  end
  Minimap:HookScript("OnEnter", OnMinimapEnter)
  Minimap:HookScript("OnLeave", OnMinimapLeave)
end

lib.ADDON_LOADED = lib.callbacks.ADDON_LOADED
lib.PLAYER_LOGIN = lib.callbacks.PLAYER_LOGIN
