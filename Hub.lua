-- Titan Up - Hub.lua
-- The launchers: the home hub (TitanBoard, Games, ...) and one page per
-- section (Games: Death Roll, Wheel of Fortune, ...), plus the minimap
-- button (left-click: hub, right-click: TitanBoard, drag: move).
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local Hub = {}
ns.Hub = Hub

-- Only the minimap button exists at login; the hub and section launchers
-- are built the first time they're opened.
function Hub:Init()
    self.launchers = {}
    self:CreateMinimapButton()
end

function Hub:EnsureHome()
    if not self.frame then
        local home = self:BuildLauncher("TitanUpHub", "home", "TITAN UP", ns.MEDIA .. "TitanUpEmblem", ns.Nav:TopLevel(), true)
        self.frame, self.header, self.tiles = home.frame, home.header, home.tiles
    end
    return self.frame
end

function Hub:EnsureSection(key)
    if not self.launchers[key] then
        local sec = ns.Nav.sectionByKey[key]
        local items = sec and ns.Nav:InSection(key) or {}
        if #items == 0 then return nil end
        self.launchers[key] = self:BuildLauncher("TitanUp" .. sec.name:gsub("%W", "") .. "Launcher", key,
            sec.name:upper(), sec.icon, items)
    end
    return self.launchers[key]
end

function Hub:Show() self:EnsureHome():Show() end

function Hub:ShowSection(key)
    local l = self:EnsureSection(key)
    if l then l.frame:Show() end
end

function Hub:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

-- A launcher window: standard title bar + one tile per entry.
function Hub:BuildLauncher(globalName, key, title, icon, items, showVersion)
    local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    f:SetSize(380, 56 + #items * 70)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Skin(f, C.bg, C.line)
    f:Hide()
    tinsert(UISpecialFrames, globalName)

    UI.Watermark(f, 300, 0.08, -10)
    local header = ns.Nav:CreateHeader(f, key, { title = title, icon = icon })
    if showVersion then
        local ver = UI.Text(header, "GameFontHighlightSmall", C.muted)
        ver:SetPoint("LEFT", header.title, "RIGHT", 8, -1)
        ver:SetText("v" .. ns.VERSION)
    end

    local tiles = {}
    for i, m in ipairs(items) do
        local tile = UI.Button(f, 356, 62, "", nil, function() ns.Nav:Switch(m.key, key) end)
        tile:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 70)
        tile.module = m
        tiles[i] = tile
        local ic = tile:CreateTexture(nil, "ARTWORK")
        ic:SetTexture(m.icon)
        ic:SetSize(40, 40)
        ic:SetPoint("LEFT", 12, 0)
        local name = UI.Text(tile, "GameFontNormal", C.text)
        name:SetPoint("TOPLEFT", ic, "TOPRIGHT", 12, -2)
        name:SetText(m.name .. (m.isSection and ("  |cff8a8f9c(" .. #ns.Nav:InSection(m.key) .. ")|r") or ""))
        local desc = UI.Text(tile, "GameFontHighlightSmall", C.muted)
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        desc:SetPoint("RIGHT", -12, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText(m.desc or "")
    end
    return { frame = f, header = header, tiles = tiles }
end

-- ---------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------
local function placeButton(b)
    local a = math.rad(ns.udb.minimap.angle or 200)
    local r = (math.min(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function Hub:CreateMinimapButton()
    local b = CreateFrame("Button", "TitanUpMinimapButton", Minimap)
    self.minimapButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ns.MEDIA .. "TitanUp")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then ns.Board:Toggle() else Hub:Toggle() end
    end)
    b:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            ns.udb.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            placeButton(s)
        end)
    end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Titan Up", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open Titan Up", 0.8, 0.82, 0.86)
        GameTooltip:AddLine("Right-click: TitanBoard", 0.8, 0.82, 0.86)
        GameTooltip:AddLine("Drag to move   (/tu minimap hides it)", 0.55, 0.58, 0.64)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:UpdateMinimapButton()
end

function Hub:UpdateMinimapButton()
    local b = self.minimapButton
    if not b then return end
    if ns.udb.minimap.hidden then b:Hide() else b:Show(); placeButton(b) end
end
