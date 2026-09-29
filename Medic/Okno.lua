-- Medic: okno nastavení kouzel na myši
-- Mřížka: sloupce = tlačítka myši, řádky = bez klávesy / Shift / Ctrl / Alt.
-- Kouzlo se do políčka přetáhne ze spellbooku (jako na akční lištu), pravé tlačítko ho smaže,
-- levé nabídne další možnosti (označit hráče, nabídka, napsat název, výchozí).
-- Kouzla se ukládají zvlášť pro každé povolání.

local M = Medic
local FONT = "Interface\\AddOns\\Medic\\Fonts\\cz.ttf"

local fontNormal = CreateFont("MedicFontNormal")
fontNormal:SetFont(FONT, 12, "")
local fontSmall = CreateFont("MedicFontSmall")
fontSmall:SetFont(FONT, 10, "")
local fontTitle = CreateFont("MedicFontTitle")
fontTitle:SetFont(FONT, 15, "")
-- písmo tlačítek: tlačítko si ho při změně textu/stavu bere z těchto objektů (jinak vrátí herní písmo bez č/ř)
local fontButton = CreateFont("MedicFontButton")
fontButton:SetFont(FONT, 12, "")
fontButton:SetTextColor(1, 0.82, 0)
local fontButtonHl = CreateFont("MedicFontButtonHighlight")
fontButtonHl:SetFont(FONT, 12, "")
fontButtonHl:SetTextColor(1, 1, 1)

-- Vlastní popisek s českým písmem (herní popisek neumí č/ř/ů a měnit ho pro celou hru nechceme)
local tip = CreateFrame("GameTooltip", "MedicTooltip", UIParent, "GameTooltipTemplate")
local function showTip(owner, anchorPoint, lines)
    tip:SetOwner(owner, anchorPoint)
    tip:ClearLines()
    for _, l in ipairs(lines) do tip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1) end
    for i = 1, tip:NumLines() do
        local fs = _G["MedicTooltipTextLeft" .. i]
        if fs then fs:SetFont(FONT, i == 1 and 14 or 12, "") end
    end
    tip:Show()
end
local function hideTip() tip:Hide() end

local function czechButton(b)
    b:SetNormalFontObject(fontButton)
    b:SetHighlightFontObject(fontButtonHl)
    b:SetDisabledFontObject(fontButton)
end

local COLUMNS = {
    { btn = "1", label = "Levé" },
    { btn = "2", label = "Pravé" },
    { btn = "3", label = "Prostřední" },
    { btn = "4", label = "Boční 4" },
    { btn = "5", label = "Boční 5" },
}
local ROWS = {
    { mod = "", label = "Bez klávesy" },
    { mod = "shift-", label = "Shift" },
    { mod = "ctrl-", label = "Ctrl" },
    { mod = "alt-", label = "Alt" },
}
local CELL_W, CELL_H, GAP = 118, 46, 4
local LEFT, TOP = 96, 70

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local win, cells, chooser, typer = nil, {}, nil, nil

local function text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function actionLabel(action)
    if action == "target" then return "Označit hráče" end
    if action == "menu" then return "Nabídka hráče" end
    return action
end

local function actionIcon(action)
    if action == "target" then return "Interface\\Icons\\Ability_Hunter_SniperShot" end
    if action == "menu" then return "Interface\\Icons\\INV_Misc_Note_01" end
    return M.SpellIcon(action) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Kouzlo, které hráč drží na kurzoru (přetažené ze spellbooku)
local function cursorSpell()
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return nil end
    local name
    local id = c or a
    if C_Spell and C_Spell.GetSpellName and id then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then name = n end
    end
    if not name and GetSpellInfo and id then name = GetSpellInfo(id) end
    if not name and GetSpellBookItemName and a and b then name = GetSpellBookItemName(a, b) end
    return name
end

local function combatNote()
    if InCombatLockdown() then M.Msg("jsi v boji - zmena se projevi hned po boji.") end
end

local refresh

local function setBind(key, action)
    M.SetBind(key, action)
    combatNote()
    refresh()
end

-------------------------------------------------------------------------------
-- Nabídka po kliknutí na políčko
-------------------------------------------------------------------------------
local function openTyper(key, cell)
    if not typer then
        typer = CreateFrame("Frame", "MedicTyper", UIParent, "BackdropTemplate")
        typer:SetSize(260, 74)
        typer:SetFrameStrata("DIALOG")
        typer:SetBackdrop(BACKDROP)
        typer:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        typer:SetBackdropBorderColor(0.3, 0.8, 0.5, 1)
        typer.label = text(typer, fontSmall, 0.8, 0.8, 0.8)
        typer.label:SetPoint("TOPLEFT", 10, -8)
        typer.label:SetText("Název kouzla anglicky (jako ve spellbooku), Enter:")
        local eb = CreateFrame("EditBox", nil, typer, "InputBoxTemplate")
        eb:SetSize(236, 22)
        eb:SetPoint("TOPLEFT", 14, -30)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() typer:Hide() end)
        eb:SetScript("OnEnterPressed", function(self)
            local v = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
            if v ~= "" then
                setBind(typer.key, v)
                if not M.KnowsSpell(v) then M.Msg("pozor: kouzlo '" .. v .. "' zatim neumis nebo je napsane jinak.") end
            end
            typer:Hide()
        end)
        typer.eb = eb
    end
    typer.key = key
    typer:ClearAllPoints()
    typer:SetPoint("TOP", cell, "BOTTOM", 0, -2)
    local current = M.GetBinds()[key]
    typer.eb:SetText((current and current ~= "target" and current ~= "menu") and current or "")
    typer:Show()
    typer.eb:SetFocus()
    typer.eb:HighlightText()
end

local CHOICES = {
    { label = "Označit hráče", action = "target" },
    { label = "Nabídka hráče", action = "menu" },
    { label = "Napsat název kouzla…", type = true },
    { label = "Výchozí kouzlo", action = nil, default = true },
    { label = "Nic (vypnout)", action = false },
}

local function openChooser(key, cell)
    if not chooser then
        chooser = CreateFrame("Frame", "MedicChooser", UIParent, "BackdropTemplate")
        chooser:SetFrameStrata("DIALOG")
        chooser:SetBackdrop(BACKDROP)
        chooser:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        chooser:SetBackdropBorderColor(0.3, 0.8, 0.5, 1)
        chooser:SetSize(170, #CHOICES * 22 + 12)
        chooser.buttons = {}
        for i, choice in ipairs(CHOICES) do
            local b = CreateFrame("Button", nil, chooser)
            b:SetSize(160, 20)
            b:SetPoint("TOPLEFT", 5, -6 - (i - 1) * 22)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.3, 0.8, 0.5, 0.25)
            local fs = text(b, fontNormal)
            fs:SetPoint("LEFT", 6, 0)
            fs:SetText(choice.label)
            b:SetScript("OnClick", function()
                chooser:Hide()
                if choice.type then openTyper(chooser.key, chooser.cell)
                else setBind(chooser.key, choice.action) end
            end)
        end
        chooser:SetScript("OnShow", function(self)
            -- zavřít kliknutím jinam
            self:SetPropagateKeyboardInput(true)
        end)
    end
    chooser.key, chooser.cell = key, cell
    chooser:ClearAllPoints()
    chooser:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -2)
    chooser:Show()
end

-------------------------------------------------------------------------------
-- Políčko mřížky
-------------------------------------------------------------------------------
local function onDrop(cell)
    local name = cursorSpell()
    if not name then return false end
    ClearCursor()
    setBind(cell.key, name)
    return true
end

local function createCell(parent, key)
    local cell = CreateFrame("Button", nil, parent, "BackdropTemplate")
    cell:SetSize(CELL_W, CELL_H)
    cell:SetBackdrop(BACKDROP)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.key = key

    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 6, 0)
    cell.icon = icon

    local name = text(cell, fontSmall)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 0)
    name:SetPoint("BOTTOMRIGHT", -4, 4)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    name:SetWordWrap(true)
    cell.nameText = name

    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    cell:SetScript("OnReceiveDrag", onDrop)
    cell:SetScript("OnClick", function(self, button)
        if onDrop(self) then return end
        if button == "RightButton" then setBind(self.key, false) return end
        openChooser(self.key, self)
    end)
    cell:SetScript("OnEnter", function(self)
        local action = M.GetBinds()[self.key]
        showTip(self, "ANCHOR_RIGHT", {
            { self.label },
            { action and actionLabel(action) or "nic", 1, 0.82, 0 },
            { " " },
            { "Přetáhni sem kouzlo ze spellbooku.", 0.7, 0.7, 0.7 },
            { "Levé tlačítko: další možnosti", 0.7, 0.7, 0.7 },
            { "Pravé tlačítko: smazat", 0.7, 0.7, 0.7 },
        })
    end)
    cell:SetScript("OnLeave", hideTip)
    return cell
end

function refresh()
    if not win or not win:IsShown() then return end
    local binds = M.GetBinds()
    for key, cell in pairs(cells) do
        local action = binds[key]
        local custom = M.IsCustom(key)
        if action then
            cell.icon:SetTexture(actionIcon(action))
            cell.icon:SetDesaturated(action ~= "target" and action ~= "menu" and not M.KnowsSpell(action))
            cell.nameText:SetText(actionLabel(action))
            local known = action == "target" or action == "menu" or M.KnowsSpell(action)
            if known then cell.nameText:SetTextColor(1, 1, 1) else cell.nameText:SetTextColor(0.6, 0.6, 0.6) end
        else
            cell.icon:SetTexture(nil)
            cell.nameText:SetText("—")
            cell.nameText:SetTextColor(0.45, 0.45, 0.45)
        end
        cell:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        -- zlatý rámeček = nastavil sis sám, šedý = výchozí
        if custom then cell:SetBackdropBorderColor(1, 0.82, 0, 1) else cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end
    end
end

-------------------------------------------------------------------------------
-- Okno
-------------------------------------------------------------------------------
local function createWindow()
    local w = LEFT + #COLUMNS * (CELL_W + GAP) + 12
    local h = TOP + #ROWS * (CELL_H + GAP) + 76
    win = CreateFrame("Frame", "MedicOptions", UIParent, "BackdropTemplate")
    win:SetSize(w, h)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetBackdrop(BACKDROP)
    win:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
    win:SetBackdropBorderColor(0.3, 0.8, 0.5, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetScript("OnHide", function()
        if chooser then chooser:Hide() end
        if typer then typer:Hide() end
    end)
    tinsert(UISpecialFrames, "MedicOptions")   -- Esc zavře okno

    local className = UnitClass("player")
    local title = text(win, fontTitle, 0.4, 1, 0.6)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Medic – kouzla na myši (" .. (className or "") .. ")")

    local sub = text(win, fontSmall, 0.75, 0.75, 0.75)
    sub:SetPoint("TOPLEFT", 14, -34)
    sub:SetText("Přetáhni kouzlo ze spellbooku (P) na políčko. Každé povolání má vlastní nastavení.")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    for c, col in ipairs(COLUMNS) do
        local fs = text(win, fontNormal, 1, 0.82, 0)
        fs:SetPoint("BOTTOM", win, "TOPLEFT", LEFT + (c - 1) * (CELL_W + GAP) + CELL_W / 2, -TOP + 4)
        fs:SetText(col.label)
    end
    for r, row in ipairs(ROWS) do
        local fs = text(win, fontNormal, 1, 0.82, 0)
        fs:SetPoint("RIGHT", win, "TOPLEFT", LEFT - 8, -TOP - (r - 1) * (CELL_H + GAP) - CELL_H / 2)
        fs:SetText(row.label)
        for c, col in ipairs(COLUMNS) do
            local key = row.mod .. col.btn
            local cell = createCell(win, key)
            cell.label = (row.mod == "" and "" or (row.label .. " + ")) .. col.label .. " tlačítko"
            cell:SetPoint("TOPLEFT", LEFT + (c - 1) * (CELL_W + GAP), -TOP - (r - 1) * (CELL_H + GAP))
            cells[key] = cell
        end
    end

    local legend = text(win, fontSmall, 0.7, 0.7, 0.7)
    legend:SetPoint("BOTTOMLEFT", 14, 44)
    legend:SetText("Zlatý rámeček = nastavil sis sám, šedý = výchozí. Šedé kouzlo = zatím ho neumíš.\nPravé tlačítko = smazat, levé = další možnosti. Změny v boji se projeví po boji.")
    legend:SetJustifyH("LEFT")

    local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    reset:SetSize(170, 24)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    reset:SetText("Vše výchozí")
    czechButton(reset)
    reset:SetScript("OnClick", function()
        M.ResetBinds()
        combatNote()
        refresh()
    end)

    local lock = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lock:SetSize(170, 24)
    lock:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    czechButton(lock)
    local function lockText() lock:SetText(MedicDB.locked and "Odemknout rámečky" or "Zamknout rámečky") end
    lock:SetScript("OnClick", function()
        SlashCmdList.MEDIC(MedicDB.locked and "odemknout" or "zamknout")
        lockText()
    end)
    win:HookScript("OnShow", lockText)
    lockText()

    local ok = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    ok:SetSize(110, 24)
    ok:SetPoint("BOTTOMRIGHT", -12, 12)
    ok:SetText("Zavřít")
    czechButton(ok)
    ok:SetScript("OnClick", function() win:Hide() end)

    win:SetScript("OnShow", refresh)
    -- nové kouzlo naučené u trenéra -> překreslit
    win:RegisterEvent("SPELLS_CHANGED")
    win:SetScript("OnEvent", refresh)
end

function M.OpenOptions()
    if not win then createWindow() end
    if win:IsShown() then win:Hide() else win:Show(); refresh() end
end

-------------------------------------------------------------------------------
-- Ikona u minimapy: levý klik = nastavení, pravý = zamknout/odemknout, tažením posunout
-------------------------------------------------------------------------------
local minimapButton
local function placeMinimapButton()
    local angle = math.rad(MedicDB.minimapAngle or 160)
    local r = (Minimap:GetWidth() / 2) + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function createMinimapButton()
    if minimapButton or not Minimap then return end
    minimapButton = CreateFrame("Button", "MedicMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Spell_Holy_FlashHeal")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SlashCmdList.MEDIC(MedicDB.locked and "odemknout" or "zamknout")
        else
            M.OpenOptions()
        end
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            MedicDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            placeMinimapButton()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    -- tooltip bez diakritiky (písmo tooltipu ji neumí)
    minimapButton:SetScript("OnEnter", function(self)
        showTip(self, "ANCHOR_LEFT", {
            { "Medic", 0.4, 1, 0.6 },
            { "Levý klik: nastavení kouzel" },
            { "Pravý klik: rámečky zamknout / odemknout" },
            { "Tažením posuneš ikonu", 0.7, 0.7, 0.7 },
        })
    end)
    minimapButton:SetScript("OnLeave", hideTip)
    placeMinimapButton()
end

-- Ozubené kolečko na táhle rámečků + ikona u minimapy
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    createMinimapButton()
    C_Timer.After(0, function()
        local handle = MedicAnchor and MedicAnchor.handle
        if not handle then return end
        local gear = CreateFrame("Button", nil, handle)
        gear:SetSize(14, 14)
        gear:SetPoint("RIGHT", -1, 0)
        gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
        gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        gear:SetScript("OnClick", M.OpenOptions)
    end)
end)
