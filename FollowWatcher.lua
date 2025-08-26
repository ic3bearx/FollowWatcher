-- FollowWatcher.lua (Classic, ASCII-safe, no varargs)
local ADDON_NAME = "FollowWatcher"

-- SavedVariables
FollowWatcherDB = FollowWatcherDB or {
  enablePrint = true,
  locked = false,
  frame = { x = 0, y = 0, point = "CENTER", relPoint = "CENTER" },
}

local function msg(text)
  if FollowWatcherDB.enablePrint and DEFAULT_CHAT_FRAME and text then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[FollowWatcher]|r " .. tostring(text))
  end
end

-- UI: Mini window
local FW = CreateFrame("Frame", "FW_FollowFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
FW:SetWidth(220)
FW:SetHeight(42)
FW:SetPoint(FollowWatcherDB.frame.point or "CENTER", UIParent, FollowWatcherDB.frame.relPoint or "CENTER", FollowWatcherDB.frame.x or 0, FollowWatcherDB.frame.y or 0)

FW:SetBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
})
local function setBGColor(r,g,b,a) FW:SetBackdropColor(r,g,b,a or 0.35) end
FW:SetBackdropBorderColor(0.2,0.2,0.2,1)

FW:EnableMouse(true)
FW:SetMovable(true)
FW:RegisterForDrag("LeftButton")
FW:SetScript("OnDragStart", function(self)
  if not FollowWatcherDB.locked then self:StartMoving() end
end)
FW:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint()
  FollowWatcherDB.frame.point, FollowWatcherDB.frame.relPoint = point, relPoint
  FollowWatcherDB.frame.x, FollowWatcherDB.frame.y = x, y
end)

local label = FW:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", FW, "CENTER", 0, 6)
label:SetText("Kein Follow")

local labelParty = FW:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
labelParty:SetPoint("TOP", label, "BOTTOM", 0, -2)
labelParty:SetText("")

-- group follow table
local partyFollows = {}  -- [follower] = target

local function rebuildPartyLine()
  local parts = {}
  for follower, target in pairs(partyFollows) do
    if target and target ~= "" then
      table.insert(parts, follower .. " -> " .. target)
    end
  end
  return table.concat(parts, ", ")
end

local function updatePartyLabel()
  labelParty:SetText(rebuildPartyLine())
end

local function setStatus(following, name)
  if following then
    setBGColor(0.00, 0.60, 0.00, 0.35) -- green
    if name and name ~= "" then
      label:SetText("Folge: " .. name)
    else
      label:SetText("Folge: ?")
    end
  else
    setBGColor(0.60, 0.00, 0.00, 0.35) -- red
    label:SetText("Kein Follow")
  end
  updatePartyLabel()
end

setStatus(false)

-- group sync
local PREFIX = "FW1"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function cleanName(n)
  if not n then return nil end
  return n:gsub("%-.*$", "")
end

local function sendFollowMsg(kind, target)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
  if IsInGroup() or IsInRaid() then
    local who = UnitName("player") or ""
    local payload = string.upper(kind or "") .. ":" .. who .. ":" .. (target or "")
    C_ChatInfo.SendAddonMessage(PREFIX, payload, IsInRaid() and "RAID" or "PARTY")
  end
end

-- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("AUTOFOLLOW_BEGIN")
f:RegisterEvent("AUTOFOLLOW_END")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")

local function isInMyGroup(name)
  name = cleanName(name)
  if not name then return false end
  if IsInRaid() then
    for i=1, GetNumGroupMembers() do
      local n = GetRaidRosterInfo(i)
      if cleanName(n) == name then return true end
    end
  elseif IsInGroup() then
    for i=1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      local n = UnitName(unit)
      if cleanName(n) == name then return true end
    end
  end
  return name == cleanName(UnitName("player"))
end

f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    FollowWatcherDB = FollowWatcherDB or { enablePrint = true, locked = false, frame = {point="CENTER",relPoint="CENTER",x=0,y=0} }
    FW:ClearAllPoints()
    FW:SetPoint(FollowWatcherDB.frame.point or "CENTER", UIParent, FollowWatcherDB.frame.relPoint or "CENTER", FollowWatcherDB.frame.x or 0, FollowWatcherDB.frame.y or 0)
    updatePartyLabel()
    msg("geladen. /fw fuer Hilfe.")

  elseif event == "AUTOFOLLOW_BEGIN" then
    local targetName = cleanName(arg1)
    setStatus(true, targetName)
    partyFollows[cleanName(UnitName("player"))] = targetName
    updatePartyLabel()
    sendFollowMsg("BEGIN", targetName)
    msg("Du folgst jetzt: " .. (targetName or "?"))

  elseif event == "AUTOFOLLOW_END" then
    setStatus(false)
    partyFollows[cleanName(UnitName("player"))] = nil
    updatePartyLabel()
    sendFollowMsg("END")
    msg("Follow beendet.")

  elseif event == "PLAYER_ENTERING_WORLD" then
    setStatus(false)
    partyFollows[cleanName(UnitName("player"))] = nil
    updatePartyLabel()

  elseif event == "GROUP_ROSTER_UPDATE" then
    for follower,_ in pairs(partyFollows) do
      if not isInMyGroup(follower) then
        partyFollows[follower] = nil
      end
    end
    updatePartyLabel()

  elseif event == "CHAT_MSG_ADDON" then
    local prefix = arg1
    local message = arg2
    if prefix == PREFIX and type(message) == "string" then
      local kind, who, target = message:match("^([^:]*):([^:]*):(.*)$")
      who   = cleanName(who)
      target= cleanName(target)
      if who and who ~= cleanName(UnitName("player")) then
        if kind == "BEGIN" then
          partyFollows[who] = target or ""
        elseif kind == "END" then
          partyFollows[who] = nil
        end
        updatePartyLabel()
      end
    end
  end
end)

-- Slash commands
SLASH_FOLLOWWATCHER1 = "/fw"
SlashCmdList.FOLLOWWATCHER = function(cmd)
  cmd = (cmd or ""):lower():gsub("^%s+", "")
  if cmd == "lock" then
    FollowWatcherDB.locked = true;  msg("Fenster gesperrt (lock).")
  elseif cmd == "unlock" then
    FollowWatcherDB.locked = false; msg("Fenster entsperrt (unlock).")
  elseif cmd == "toggle" then
    if FW:IsShown() then FW:Hide() else FW:Show() end
    msg("Fenster: " .. (FW:IsShown() and "sichtbar" or "versteckt"))
  elseif cmd == "reset" then
    FollowWatcherDB.frame = { point="CENTER", relPoint="CENTER", x=0, y=0 }
    FW:ClearAllPoints(); FW:SetPoint("CENTER")
    msg("Position zurueckgesetzt.")
  elseif cmd == "print" then
    FollowWatcherDB.enablePrint = not FollowWatcherDB.enablePrint
    msg("Chat-Ausgabe: " .. (FollowWatcherDB.enablePrint and "AN" or "AUS"))
  else
    msg("Befehle: /fw lock, /fw unlock, /fw toggle, /fw reset, /fw print")
  end
end
