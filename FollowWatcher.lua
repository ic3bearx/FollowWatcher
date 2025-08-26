# FollowWatcher – komplettes Addon (Classic)

Dieses Paket zeigt ein verschiebbares **Mini‑Fenster** (grün = du folgst *X*, rot = kein Follow) **und** synchronisiert in der **Gruppe/Raid**, wer wem folgt (Zeile: `A → B, C → D`).

> **Installation**
>
> 1. Ordner anlegen: `.../_classic_/Interface/AddOns/FollowWatcher/`
> 2. Dateien wie unten anlegen (genau diese Namen)
> 3. Spiel starten oder `/reload`
> 4. In der Addon‑Liste „FollowWatcher“ aktivieren
>
> **Slash‑Befehle**: `/fw lock`, `/fw unlock`, `/fw toggle`, `/fw reset`, `/fw print`

---

## 1) `FollowWatcher.toc`

```toc
## Title: FollowWatcher
## Notes: Mini-Statusfenster für Auto-Follow, Gruppen-Sync wer wem folgt
## Author: You
## Version: 1.2.0
## SavedVariables: FollowWatcherDB
## Interface: 11505
FollowWatcher.lua
```

> **Hinweis:** Wenn das Addon nicht erscheint, passe `Interface:` an (nimm die Zahl aus einem funktionierenden Addon deiner Classic‑Version).

---

## 2) `FollowWatcher.lua`

```lua
-- FollowWatcher.lua (Classic)
local ADDON = ...

-- =============================
-- SavedVariables (Persistenz)
-- =============================
FollowWatcherDB = FollowWatcherDB or {
  enablePrint = true,
  locked = false,
  frame = { x = 0, y = 0, point = "CENTER", relPoint = "CENTER" },
}

local function msg(...)
  if FollowWatcherDB.enablePrint then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[FollowWatcher]|r "..table.concat({...}, " "))
  end
end

-- =============================
-- Mini-Fenster (UI)
-- =============================
local FW = CreateFrame("Frame", "FW_FollowFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
FW:SetSize(220, 42)
FW:SetPoint(FollowWatcherDB.frame.point or "CENTER", UIParent, FollowWatcherDB.frame.relPoint or "CENTER", FollowWatcherDB.frame.x or 0, FollowWatcherDB.frame.y or 0)

-- Optik
FW:SetBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
})
local function setBGColor(r,g,b,a) FW:SetBackdropColor(r,g,b,a or 0.35) end
FW:SetBackdropBorderColor(0.2,0.2,0.2,1)

-- Dragging
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

-- Texte
local label = FW:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
label:SetPoint("CENTER", FW, "CENTER", 0, 6)
label:SetText("Kein Follow")

local labelParty = FW:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
labelParty:SetPoint("TOP", label, "BOTTOM", 0, -2)
labelParty:SetText("")

-- Status-Setter
local function setStatus(following, name)
  if following then
    setBGColor(0.00, 0.60, 0.00, 0.35) -- grün
    label:SetText((name and name ~= "") and ("Folge: "..name) or "Folge: ?")
  else
    setBGColor(0.60, 0.00, 0.00, 0.35) -- rot
    label:SetText("Kein Follow")
  end
end

-- Init-Status
setStatus(false)

-- =============================
-- Gruppen-Sync (wer folgt wem)
-- =============================
local PREFIX = "FW1"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local partyFollows = {}  -- [followerName] = targetName
local function cleanName(n)
  if not n then return nil end
  return n:gsub("%-.*$", "")
end
local function rebuildPartyLine()
  local parts = {}
  for follower, target in pairs(partyFollows) do
    if target and target ~= "" then
      table.insert(parts, follower.." → "..target)
    end
  end
  return table.concat(parts, ", ")
end

local function updatePartyLabel()
  labelParty:SetText(rebuildPartyLine())
end

local function sendFollowMsg(kind, target)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
  if IsInGroup() or IsInRaid() then
    local who = UnitName("player")
    local payload = (kind or ""):upper()..":"..(who or "")..":"..(target or "")
    C_ChatInfo.SendAddonMessage(PREFIX, payload, IsInRaid() and "RAID" or "PARTY")
  end
end

-- =============================
-- Events
-- =============================
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
      local n, _, _, _, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
      if cleanName(n) == name then return true end
    end
  elseif IsInGroup() then
    for i=1, GetNumSubgroupMembers() do
      local unit = "party"..i
      local n = UnitName(unit)
      if cleanName(n) == name then return true end
    end
  end
  return name == cleanName(UnitName("player"))
end

f:SetScript("OnEvent", function(self, event, arg1, ...)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    FollowWatcherDB = FollowWatcherDB or { enablePrint = true, locked = false, frame = {point="CENTER",relPoint="CENTER",x=0,y=0} }
    -- Position anwenden
    FW:ClearAllPoints()
    FW:SetPoint(FollowWatcherDB.frame.point or "CENTER", UIParent, FollowWatcherDB.frame.relPoint or "CENTER", FollowWatcherDB.frame.x or 0, FollowWatcherDB.frame.y or 0)
    updatePartyLabel()
    msg("geladen. /fw für Hilfe.")

  elseif event == "AUTOFOLLOW_BEGIN" then
    local targetName = cleanName(arg1)
    setStatus(true, targetName)
    partyFollows[cleanName(UnitName("player"))] = targetName
    updatePartyLabel()
    sendFollowMsg("BEGIN", targetName)
    msg("Du folgst jetzt: "..(targetName or "?"))

  elseif event == "AUTOFOLLOW_END" then
    setStatus(false)
    partyFollows[cleanName(UnitName("player"))] = nil
    updatePartyLabel()
    sendFollowMsg("END")
    msg("Follow beendet.")

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Beim Zonen-/Weltwechsel konservativ auf rot
    setStatus(false)
    partyFollows[cleanName(UnitName("player"))] = nil
    updatePartyLabel()

  elseif event == "GROUP_ROSTER_UPDATE" then
    -- Einträge von Leuten entfernen, die nicht mehr in der Gruppe sind
    for follower,_ in pairs(partyFollows) do
      if not isInMyGroup(follower) then
        partyFollows[follower] = nil
      end
    end
    updatePartyLabel()

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, channel, sender = arg1, ...
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

-- =============================
-- Slash-Commands
-- =============================
SLASH_FOLLOWWATCHER1 = "/fw"
SlashCmdList.FOLLOWWATCHER = function(cmd)
  cmd = (cmd or ""):lower():gsub("^%s+", "")
  if cmd == "lock" then
    FollowWatcherDB.locked = true
    msg("Fenster gesperrt (lock).")
  elseif cmd == "unlock" then
    FollowWatcherDB.locked = false
    msg("Fenster entsperrt (unlock).")
  elseif cmd == "toggle" then
    if FW:IsShown() then FW:Hide() else FW:Show() end
    msg("Fenster: "..(FW:IsShown() and "sichtbar" or "versteckt"))
  elseif cmd == "reset" then
    FollowWatcherDB.frame = { point="CENTER", relPoint="CENTER", x=0, y=0 }
    FW:ClearAllPoints(); FW:SetPoint("CENTER")
    msg("Position zurückgesetzt.")
  elseif cmd == "print" then
    FollowWatcherDB.enablePrint = not FollowWatcherDB.enablePrint
    msg("Chat-Ausgabe: "..(FollowWatcherDB.enablePrint and "AN" or "AUS"))
  else
    msg("Befehle: /fw lock, /fw unlock, /fw toggle, /fw reset, /fw print")
  end
end
```

---

## Hinweise & Troubleshooting

* **Interface-Version:** Wenn das Addon im Spiel nicht sichtbar ist, `Interface:` in der TOC anpassen (Zahl aus einem funktionierenden Classic‑Addon übernehmen).
* **Gruppensync:** Die Gruppenzeile füllt sich nur, wenn **andere Spieler das Addon ebenfalls aktiv** haben.
* **Verschieben:** `/fw unlock` → ziehen mit linker Maustaste; `/fw lock` sperrt wieder.
* **Persistenz:** Position & Einstellungen werden in `FollowWatcherDB` gespeichert.
* **Sicherheit:** Keine Automatisierung von Follow, nur Anzeige & manuelle Befehle.
