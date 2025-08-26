-- FollowWatcher.lua (Classic, ASCII, safe init, Shift+Left drag)
local ADDON_NAME = "FollowWatcher"

-- ===== SavedVariables safe getter =====
local function getDB()
  if type(FollowWatcherDB) ~= "table" then
    FollowWatcherDB = {
      enablePrint = true,
      locked = false,
      frame = { x = 0, y = 0, point = "CENTER", relPoint = "CENTER" },
    }
  end
  return FollowWatcherDB
end

local function msg(text)
  local db = getDB()
  if db.enablePrint and DEFAULT_CHAT_FRAME and text then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[FollowWatcher]|r " .. tostring(text))
  end
end

-- ===== UI frame (no DB access here) =====
local FW = CreateFrame("Frame", "FW_FollowFrame", UIParent)
FW:SetWidth(220); FW:SetHeight(42)

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

local label = FW:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", FW, "CENTER", 0, 6)
label:SetText("Kein Follow")

local labelParty = FW:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
labelParty:SetPoint("TOP", label, "BOTTOM", 0, -2)
labelParty:SetText("")

-- ===== Follow status + party line (no DB access) =====
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
    setBGColor(0.00, 0.60, 0.00, 0.35)
    label:SetText((name and name ~= "") and ("Folge: " .. name) or "Folge: ?")
  else
    setBGColor(0.60, 0.00, 0.00, 0.35)
    label:SetText("Kein Follow")
  end
  updatePartyLabel()
end

setStatus(false)

-- ===== Addon message helpers =====
local PREFIX = "FW1"

local function cleanName(n)
  if not n then return nil end
  return n:gsub("%-.*$", "")
end

local function registerPrefix(prefix)
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  end
end

local function sendAddon(prefix, msgText, channel)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(prefix, msgText, channel)
  elseif SendAddonMessage then
    SendAddonMessage(prefix, msgText, channel)
  end
end

local function sendFollowMsg(kind, target)
  if IsInRaid() or IsInGroup() then
    local who = UnitName("player") or ""
    local payload = string.upper(kind or "") .. ":" .. who .. ":" .. (target or "")
    sendAddon(PREFIX, payload, IsInRaid() and "RAID" or "PARTY")
  end
end

-- ===== Events =====
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("AUTOFOLLOW_BEGIN")
f:RegisterEvent("AUTOFOLLOW_END")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")

-- Drag handlers (bound after ADDON_LOADED)
local function onDragStart(frame)
  local db = getDB()
  if IsShiftKeyDown() and not db.locked then
    frame:StartMoving()
  end
end
local function onDragStop(frame)
  frame:StopMovingOrSizing()
  local point, _, relPoint, x, y = frame:GetPoint()
  local db = getDB()
  db.frame.point, db.frame.relPoint = point, relPoint
  db.frame.x, db.frame.y = x, y
end

f:SetScript("OnEvent", function(self, event, arg1, arg2)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    local db = getDB()

    -- now that DB exists, position + drag scripts
    FW:ClearAllPoints()
    FW:SetPoint(db.frame.point or "CENTER", UIParent, db.frame.relPoint or "CENTER", db.frame.x or 0, db.frame.y or 0)
    FW:RegisterForDrag("LeftButton")
    FW:SetScript("OnDragStart", onDragStart)
    FW:SetScript("OnDragStop",  onDragStop)

    registerPrefix(PREFIX)
    updatePartyLabel()
    msg("geladen. /fw fuer Hilfe. (Shift+Left drag)")

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

-- ===== Slash commands =====
SLASH_FOLLOWWATCHER1 = "/fw"
SlashCmdList.FOLLOWWATCHER = function(cmd)
  cmd = (cmd or ""):lower():gsub("^%s+", "")
  local db = getDB()
  if cmd == "lock" then
    db.locked = true;  msg("Fenster gesperrt (lock).")
  elseif cmd == "unlock" then
    db.locked = false; msg("Fenster entsperrt (unlock).")
  elseif cmd == "toggle" then
    if FW:IsShown() then FW:Hide() else FW:Show() end
    msg("Fenster: " .. (FW:IsShown() and "sichtbar" or "versteckt"))
  elseif cmd == "reset" then
    db.frame = { point="CENTER", relPoint="CENTER", x=0, y=0 }
    FW:ClearAllPoints(); FW:SetPoint("CENTER")
    msg("Position zurueckgesetzt.")
  elseif cmd == "print" then
    db.enablePrint = not db.enablePrint
    msg("Chat-Ausgabe: " .. (db.enablePrint and "AN" or "AUS"))
  else
    msg("Befehle: /fw lock, /fw unlock, /fw toggle, /fw reset, /fw print")
  end
end
