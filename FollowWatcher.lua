-- FollowWatcher.lua (Classic, ASCII-safe)
local ADDON_NAME = "FollowWatcher"

-- ===== SavedVariables (safe getter so nothing crashes early) =====
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

-- ===== UI: Mini window =====
local FW = CreateFrame("Frame", "FW_FollowFrame", UIParent)  -- keep simple for Classic
FW:SetWidth(220)
FW:SetHeight(42)

FW:SetBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
})
local function setBGColor(r,g,b,a) FW:SetBackdropColor(r,g,b,a or 0.35) end
FW:SetBackdropBorderColor(0.2,0.2,0.2,1)

-- Mouse/drag is wired after ADDON_LOADED; still enable here
FW:EnableMouse(true)
FW:SetMovable(true)

local label = FW:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", FW, "CENTER", 0, 6)
label:SetText("Kein Follow")

local labelParty = FW:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
labelParty:SetPoint("TOP", label, "BOTTOM", 0, -2)
labelParty:SetText("")

-- ===== Follow status & party line =====
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

-- ===== Group sync (addon messages) =====
local PREFIX = "FW1"

local function cleanName(n)
  if not n then return nil end
  return n:gsub("%-.*$", "")
end

local function sendAddon(prefix, msgText, channel)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(prefix, msgText, channel)
  elseif SendAddonMessage then
    SendAddonMessage(prefix, msgText, channel)
  end
end

local function registerPrefix(prefix)
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  end
end

local function sendFollowMsg(kind, target)
  if (IsInRaid() or IsInGroup()) then
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

f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    local db = getDB()

    -- Position now that SavedVariables are ready
    FW:ClearAllPoints()
    FW:SetPoint(db.frame.point or "CENTER", UIParent, db.frame.relPoint or "CENTER", db.frame.x or 0, db.frame.y or 0)

    -- Drag handlers (Shift + LeftButton)
    FW:RegisterForDrag("LeftButton")
    FW:SetScript("OnDragStart", function(frame)
      if IsShiftKeyDown() and not getDB().locked then
        frame:StartMoving()
      end
    end)
    FW:SetScript("OnDragStop", function(frame)
      frame:StopMovingOrSizing()
      local point, _, relPoint, x, y = frame:GetPoint()
      local d = getDB()
      d.frame.point, d.frame.relPoint = point, relPoint
      d.frame.x, d.frame.y = x, y
    end)

    registerPrefix(PREFIX)
    updatePartyLabel()
    msg("geladen. /fw fuer Hilfe. (Shift+LeftButton drag)")

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
    -- conservative reset on load
    setStatus(false)
    partyFollows[cleanName(UnitName("player"))] = nil
    updatePartyLabel()

  elseif event == "GROUP_ROSTER_UPDATE" then
    -- optional cleanup could be placed here if needed
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
