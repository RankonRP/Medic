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
local LEFT, TOP = 96, 90

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local win, cells, chooser, typer = nil, {}, nil, nil
local createIndicatorsPage, createKeysPage, createLookPage, refreshKeys

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

-- klíč políčka: "shift-1" = myš, "key:SHIFT-Q" = klávesa při najetí na rámeček
local function keyOf(key) return key:match("^key:(.+)$") end

local function getAction(key)
    local k = keyOf(key)
    if k then return M.GetKeys()[k] or nil end
    return M.GetBinds()[key]
end

local function setBind(key, action)
    local k = keyOf(key)
    if k then
        M.SetKey(k, action or false)   -- „výchozí“ u klávesy = bez kouzla
    else
        M.SetBind(key, action)
    end
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
    local current = getAction(key)
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
        local action = getAction(self.key)
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

local function paintCell(cell, action, custom)
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

function refresh()
    if not win or not win:IsShown() then return end
    local binds = M.GetBinds()
    for key, cell in pairs(cells) do paintCell(cell, binds[key], M.IsCustom(key)) end
    if refreshKeys then refreshKeys() end
end

-------------------------------------------------------------------------------
-- Záložka „Klávesnice“: kouzlo na klávesu při najetí myší na rámeček
-------------------------------------------------------------------------------
local KEY_NAMES = {
    SPACE = "Mezerník", TAB = "Tab", ENTER = "Enter", BACKSPACE = "Backspace",
    MOUSEWHEELUP = "Kolečko nahoru", MOUSEWHEELDOWN = "Kolečko dolů",
}
local function keyText(k)
    local mods, base = k:match("^(.-)([^%-]+)$")
    base = KEY_NAMES[base] or base:gsub("^NUMPAD", "Num ")
    mods = mods:gsub("ALT%-", "Alt + "):gsub("CTRL%-", "Ctrl + "):gsub("SHIFT%-", "Shift + ")
    return mods .. base
end
local IGNORE_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true, LMETA = true, RMETA = true }

createKeysPage = function(page)
    local sub = text(page, fontSmall, 0.75, 0.75, 0.75)
    sub:SetPoint("TOPLEFT", 14, -40)
    sub:SetWidth(680)
    sub:SetJustifyH("LEFT")
    sub:SetText("Najeď myší na rámeček hráče a zmáčkni klávesu – kouzlo se sešle na něj. Jinde klávesy fungují normálně.\nPřidej klávesu a pak na políčko přetáhni kouzlo ze spellbooku. Každé povolání má vlastní klávesy.")

    local add = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    add:SetSize(170, 24)
    add:SetPoint("TOPLEFT", 12, -78)
    czechButton(add)
    add:SetText("Přidat klávesu")

    local empty = text(page, fontNormal, 0.6, 0.6, 0.6)
    empty:SetPoint("TOPLEFT", 20, -120)
    empty:SetText("Zatím žádné klávesy. Klikni na „Přidat klávesu“.")

    -- zachytávání klávesy
    local cap = CreateFrame("Button", nil, page, "BackdropTemplate")
    cap:SetPoint("LEFT", add, "RIGHT", 10, 0)
    cap:SetSize(360, 24)
    cap:SetBackdrop(BACKDROP)
    cap:SetBackdropColor(0.3, 0.8, 0.5, 0.25)
    cap:SetBackdropBorderColor(0.3, 0.8, 0.5, 1)
    local capText = text(cap, fontNormal)
    capText:SetPoint("CENTER")
    capText:SetText("Zmáčkni klávesu (i se Shift/Ctrl/Alt)… Esc = zrušit")
    cap:Hide()
    cap:EnableKeyboard(true)
    cap:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(false)
        if IGNORE_KEYS[key] then return end
        self:Hide()
        if key == "ESCAPE" then return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local n = 0
        for _ in pairs(M.GetKeys()) do n = n + 1 end
        if M.GetKeys()[combo] == nil and n >= 12 then M.Msg("vic nez 12 klaves se do okna nevejde.") return end
        if M.GetKeys()[combo] == nil then M.SetKey(combo, false) end
        combatNote()
        refresh()
    end)
    cap:SetScript("OnMouseDown", function(self) self:Hide() end)
    add:SetScript("OnClick", function() cap:Show() end)
    page:HookScript("OnHide", function() cap:Hide() end)

    -- řádky: 2 sloupce po 6
    local rows = {}
    for i = 1, 12 do
        local col, r = math.floor((i - 1) / 6), (i - 1) % 6
        local x, y = 14 + col * 350, -116 - r * 50
        local row = {}
        row.label = text(page, fontTitle, 1, 0.82, 0)
        row.label:SetPoint("TOPLEFT", x, y - 14)
        row.label:SetWidth(120)
        row.label:SetJustifyH("RIGHT")
        row.cell = createCell(page, "key:?")
        row.cell:SetPoint("TOPLEFT", x + 128, y)
        row.del = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        row.del:SetSize(26, 22)
        row.del:SetPoint("LEFT", row.cell, "RIGHT", 6, 0)
        row.del:SetText("X")
        row.del:SetScript("OnClick", function()
            M.SetKey(row.key, nil)
            combatNote()
            refresh()
        end)
        rows[i] = row
    end

    refreshKeys = function()
        if not page:IsShown() then return end
        local keys = {}
        for k in pairs(M.GetKeys()) do keys[#keys + 1] = k end
        table.sort(keys)
        empty:SetShown(#keys == 0)
        for i, row in ipairs(rows) do
            local k = keys[i]
            row.key = k
            local show = k ~= nil
            row.label:SetShown(show)
            row.cell:SetShown(show)
            row.del:SetShown(show)
            if show then
                row.label:SetText(keyText(k))
                row.cell.key = "key:" .. k
                row.cell.label = "Klávesa " .. keyText(k)
                paintCell(row.cell, M.GetKeys()[k] or nil, true)
            end
        end
    end
    page:HookScript("OnShow", refreshKeys)
end

-------------------------------------------------------------------------------
-- Záložka „Ukazatele a velikost“: buffy, debuffy, aggro, velikost rámečků
-------------------------------------------------------------------------------
-- Pomůcky pro stránky s volbami (nadpis, poznámka, zaškrtávátko, − hodnota +)
local function pageHelpers(page)
    local refreshers = {}
    page.refresh = function() for _, fn in ipairs(refreshers) do fn() end end

    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 8, -40)
    bg:SetPoint("BOTTOMRIGHT", -8, 44)
    bg:SetColorTexture(1, 1, 1, 0.03)

    local h = { refreshers = refreshers }
    function h.heading(x, y, label)
        local fs = text(page, fontTitle, 1, 0.82, 0)
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetText(label)
    end
    function h.note(x, y, label, width)
        local fs = text(page, fontSmall, 0.65, 0.65, 0.65)
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetWidth(width or 215)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        return fs
    end
    function h.check(x, y, label, get, set)
        local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", x, y)
        if cb.Text then cb.Text:SetText("") end
        local fs = text(page, fontNormal)
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetWidth(212)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            M.UpdateAll()
            page.refresh()
        end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
        return cb
    end
    function h.stepper(x, y, label, get, step, min, max, fmt, apply)
        local l = text(page, fontNormal)
        l:SetPoint("TOPLEFT", x, y - 4)
        l:SetText(label)
        local minus = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        minus:SetSize(26, 22)
        minus:SetPoint("TOPLEFT", x + 82, y)
        minus:SetText("-")
        local val = text(page, fontNormal, 1, 1, 1)
        val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        val:SetWidth(40)
        local plus = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        plus:SetSize(26, 22)
        plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
        plus:SetText("+")
        local function change(d)
            local v = math.floor((get() + d) / step + 0.5) * step
            v = math.max(min, math.min(max, v))
            if not apply(v) then M.Msg("v boji to hra nedovoli - zkus to po boji.") end
            M.UpdateAll()
            page.refresh()
        end
        minus:SetScript("OnClick", function() change(-step) end)
        plus:SetScript("OnClick", function() change(step) end)
        refreshers[#refreshers + 1] = function() val:SetText(fmt:format(get())) end
    end
    return h
end

-------------------------------------------------------------------------------
-- Záložka „Ukazatele“: buffy, debuffy, aggro, cíl, mana, štíty, oživení
-------------------------------------------------------------------------------
createIndicatorsPage = function(page)
    local h = pageHelpers(page)
    local heading, note, check = h.heading, h.note, h.check

    -- Buffy ------------------------------------------------------------------
    local x = 18
    heading(x, -50, "Buffy")
    check(x, -74, "Hlídat chybějící buff", function() return MedicDB.buffs end, function(v) MedicDB.buffs = v end)
    check(x, -100, "Ikonka = buff chybí", function() return MedicDB.buffMode ~= "present" end, function() MedicDB.buffMode = "missing" end)
    check(x, -126, "Ikonka = buff má (zmizí, když spadne)", function() return MedicDB.buffMode == "present" end, function() MedicDB.buffMode = "present" end)
    check(x, -152, "Jen mimo boj", function() return MedicDB.buffOOC end, function(v) MedicDB.buffOOC = v end)
    check(x, -178, "Jen buff ode mě", function()
        local c = M.BuffConfig()
        return c and c.mine
    end, function(v) MedicDB.buffMine[M.Class] = v end)
    local lbl = text(page, fontNormal)
    lbl:SetPoint("TOPLEFT", x + 4, -210)
    lbl:SetText("Hlídané buffy:")
    local eb = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    eb:SetSize(205, 22)
    eb:SetPoint("TOPLEFT", x + 8, -228)
    eb:SetAutoFocus(false)
    local function saveBuffs()
        MedicDB.buffNames[M.Class] = eb:GetText()
        M.UpdateAll()
        page.refresh()
    end
    eb:SetScript("OnEnterPressed", function(self) saveBuffs(); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", saveBuffs)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = note(x + 4, -254, "")
    h.refreshers[#h.refreshers + 1] = function()
        if not eb:HasFocus() then eb:SetText(MedicDB.buffNames[M.Class] or "") end
        local def = M.BuffDefaultText()
        hint:SetText("Víc buffů odděl čárkou, anglicky. Prázdné = výchozí" .. (def and (": " .. def) or " (tvé povolání žádný nemá)") .. ".")
    end

    -- Debuffy ----------------------------------------------------------------
    x = 258
    heading(x, -50, "Debuffy")
    check(x, -74, "Zvýraznit debuffy, které umím odstranit", function() return MedicDB.debuffs end, function(v) MedicDB.debuffs = v end)
    check(x, -110, "Ukázat ikonku debuffu", function() return MedicDB.debuffIcon end, function(v) MedicDB.debuffIcon = v end)
    check(x, -136, "Ukazovat i ostatní debuffy", function() return MedicDB.debuffAll end, function(v) MedicDB.debuffAll = v end)
    check(x, -162, "Blikat, když jde debuff odstranit", function() return MedicDB.debuffBlink end, function(v) MedicDB.debuffBlink = v end)
    note(x + 4, -194, "Barva rámečku podle typu: magie modrá, kletba fialová, nemoc hnědá, jed zelená. Ostatní debuffy mají jen ikonku.")

    -- Aggro ------------------------------------------------------------------
    x = 498
    heading(x, -50, "Aggro")
    check(x, -74, "Ukazovat aggro", function() return MedicDB.aggro end, function(v) MedicDB.aggro = v end)
    check(x, -100, "Proužek nahoře", function() return MedicDB.aggroStyle ~= "ramecek" end, function() MedicDB.aggroStyle = "pruh" end)
    check(x, -126, "Celý rámeček červeně", function() return MedicDB.aggroStyle == "ramecek" end, function() MedicDB.aggroStyle = "ramecek" end)
    check(x, -152, "Lebka: na koho útočí můj cíl", function() return MedicDB.targetOf end, function(v) MedicDB.targetOf = v end)
    note(x + 4, -184, "Aggro se neukáže, když ho hra skrývá. Lebka funguje vždy, když máš v cíli nepřítele.")

    -- Další ------------------------------------------------------------------
    heading(18, -300, "Další ukazatele")
    check(18, -324, "Zvýraznit můj cíl (bílý rámeček)", function() return MedicDB.targetHighlight end, function(v) MedicDB.targetHighlight = v end)
    check(18, -350, "Štíty (absorpce) za zdravím", function() return MedicDB.absorbs end, function(v) MedicDB.absorbs = v end)
    check(258, -324, "Pruh many", function() return MedicDB.powerBar end, function(v) MedicDB.powerBar = v end)
    check(258, -350, "Manu jen u healerů", function() return MedicDB.powerHealersOnly end, function(v) MedicDB.powerHealersOnly = v end)
    check(498, -324, "Ikonka oživování u mrtvých", function() return MedicDB.rezIcon end, function(v) MedicDB.rezIcon = v end)
end

-------------------------------------------------------------------------------
-- Záložka „Vzhled“: barvy, role, řazení, rozložení, velikosti
-------------------------------------------------------------------------------
createLookPage = function(page)
    local h = pageHelpers(page)
    local heading, note, check, stepper = h.heading, h.note, h.check, h.stepper

    heading(18, -50, "Vzhled")
    check(18, -74, "Barva podle zdraví (jinak podle povolání)", function() return MedicDB.colorMode ~= "class" end,
        function(v) MedicDB.colorMode = v and "hp" or "class" end)
    check(18, -100, "Ikony rolí (tank, healer, dps)", function() return MedicDB.roleIcons end, function(v) MedicDB.roleIcons = v end)
    check(258, -74, "Řadit: tank první, pak healer, pak dps", function() return MedicDB.sortRoles end, function(v)
        MedicDB.sortRoles = v
        if not M.ApplySort() then M.Msg("v boji to hra nedovoli - projevi se po boji.") end
    end)
    check(258, -100, "Ikonky mých HoTů s odpočtem", function() return MedicDB.hots end, function(v) MedicDB.hots = v end)

    heading(18, -140, "Rozložení")
    local function grid(v)
        if not M.ApplyGrid() then M.Msg("v boji to hra nedovoli - projevi se po boji.") end
    end
    check(18, -164, "Vedle sebe (další řada pod nimi)", function() return MedicDB.orientation ~= "vertical" end,
        function() MedicDB.orientation = "horizontal"; grid() end)
    check(18, -190, "Pod sebou (další sloupec vedle)", function() return MedicDB.orientation == "vertical" end,
        function() MedicDB.orientation = "vertical"; grid() end)
    stepper(258, -166, "V řadě", function() return MedicDB.perRow or 5 end, 1, 1, 40, "%d",
        function(v) MedicDB.perRow = v; return M.ApplyGrid() end)
    stepper(258, -194, "Mezera", function() return MedicDB.spacing or 2 end, 1, 0, 20, "%d",
        function(v) MedicDB.spacing = v; return M.ApplyGrid() end)
    note(500, -168, "„V řadě“ = kolik hráčů je vedle sebe (nebo pod sebou), než začne další řada.", 190)

    heading(18, -236, "Velikost")
    stepper(18, -262, "Šířka", function() return MedicDB.width end, 5, 50, 200, "%d",
        function(v) return M.SetLayout(v, MedicDB.height, MedicDB.scale) end)
    stepper(258, -262, "Výška", function() return MedicDB.height end, 2, 20, 80, "%d",
        function(v) return M.SetLayout(MedicDB.width, v, MedicDB.scale) end)
    stepper(498, -262, "Měřítko", function() return MedicDB.scale end, 0.1, 0.5, 2, "%.1f",
        function(v) return M.SetLayout(MedicDB.width, MedicDB.height, v) end)
    stepper(18, -292, "HoTy", function() return MedicDB.hotSize or 15 end, 1, 8, 30, "%d",
        function(v) M.SetIconSize("hotSize", v) return true end)
    stepper(258, -292, "Buff", function() return MedicDB.buffSize or 12 end, 1, 8, 30, "%d",
        function(v) M.SetIconSize("buffSize", v) return true end)
    stepper(498, -292, "Debuff", function() return MedicDB.debuffSize or 14 end, 1, 8, 30, "%d",
        function(v) M.SetIconSize("debuffSize", v) return true end)
    stepper(18, -322, "Mana", function() return MedicDB.powerHeight or 4 end, 1, 2, 12, "%d",
        function(v) MedicDB.powerHeight = v; return true end)
    note(18, -350, "Šířku, výšku, měřítko a rozložení hra v boji měnit nedovolí. Ikonky a manu jde měnit kdykoli.", 660)

    -- Testovací režim --------------------------------------------------------
    heading(18, -378, "Testovací režim")
    stepper(18, -404, "Hráčů", function() return MedicDB.previewSize or 40 end, 1, 1, 40, "%d", function(v)
        MedicDB.previewSize = v
        if M.PreviewCount() > 0 then M.Preview(v) end
        return true
    end)
    local toggle = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    toggle:SetSize(170, 24)
    toggle:SetPoint("TOPLEFT", 258, -403)
    czechButton(toggle)
    local function toggleText() toggle:SetText(M.PreviewCount() > 0 and "Vypnout náhled" or "Zapnout náhled") end
    toggle:SetScript("OnClick", function()
        if M.PreviewCount() > 0 then M.Preview(0)
        elseif InCombatLockdown() then M.Msg("v boji to nejde.")
        else M.Preview(MedicDB.previewSize or 40) end
        toggleText()
    end)
    h.refreshers[#h.refreshers + 1] = toggleText
    note(440, -400, "Vymyšlená skupina jen na ukázku – změny nastavení uvidíš hned. V boji se sám vypne.", 250)
end
-------------------------------------------------------------------------------
-- Okno
-------------------------------------------------------------------------------
local function createWindow()
    local w = LEFT + #COLUMNS * (CELL_W + GAP) + 12
    local h = TOP + #ROWS * (CELL_H + GAP) + 236
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
    title:SetText("Medic (" .. (className or "") .. ")")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- záložky
    local page1 = CreateFrame("Frame", nil, win)
    page1:SetAllPoints()
    local page2 = CreateFrame("Frame", nil, win)
    page2:SetAllPoints()
    page2:Hide()
    createIndicatorsPage(page2)
    local page3 = CreateFrame("Frame", nil, win)
    page3:SetAllPoints()
    page3:Hide()
    createKeysPage(page3)
    local page4 = CreateFrame("Frame", nil, win)
    page4:SetAllPoints()
    page4:Hide()
    createLookPage(page4)
    local pages = { page1, page3, page2, page4 }
    local tabs = {}
    local TAB_LABELS = { { "Myš", 70 }, { "Klávesnice", 110 }, { "Ukazatele", 105 }, { "Vzhled", 85 } }
    local function showPage(n)
        for i, p in ipairs(pages) do p:SetShown(i == n) end
        for i, tb in ipairs(tabs) do tb:SetEnabled(i ~= n) end
        if pages[n].refresh then pages[n].refresh() end
        if n == 1 then refresh() end
    end
    local prev
    for i = #TAB_LABELS, 1, -1 do
        local tb = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        tb:SetSize(TAB_LABELS[i][2], 24)
        czechButton(tb)
        tb:SetText(TAB_LABELS[i][1])
        if prev then tb:SetPoint("RIGHT", prev, "LEFT", -6, 0) else tb:SetPoint("TOPRIGHT", -34, -8) end
        tb:SetScript("OnClick", function() showPage(i) end)
        tabs[i] = tb
        prev = tb
    end
    showPage(1)

    local sub = text(page1, fontSmall, 0.75, 0.75, 0.75)
    sub:SetPoint("TOPLEFT", 14, -40)
    sub:SetText("Přetáhni kouzlo ze spellbooku (P) na políčko. Každé povolání má vlastní nastavení.")

    for c, col in ipairs(COLUMNS) do
        local fs = text(page1, fontNormal, 1, 0.82, 0)
        fs:SetPoint("BOTTOM", win, "TOPLEFT", LEFT + (c - 1) * (CELL_W + GAP) + CELL_W / 2, -TOP + 4)
        fs:SetText(col.label)
    end
    for r, row in ipairs(ROWS) do
        local fs = text(page1, fontNormal, 1, 0.82, 0)
        fs:SetPoint("RIGHT", win, "TOPLEFT", LEFT - 8, -TOP - (r - 1) * (CELL_H + GAP) - CELL_H / 2)
        fs:SetText(row.label)
        for c, col in ipairs(COLUMNS) do
            local key = row.mod .. col.btn
            local cell = createCell(page1, key)
            cell.label = (row.mod == "" and "" or (row.label .. " + ")) .. col.label .. " tlačítko"
            cell:SetPoint("TOPLEFT", win, "TOPLEFT", LEFT + (c - 1) * (CELL_W + GAP), -TOP - (r - 1) * (CELL_H + GAP))
            cells[key] = cell
        end
    end

    local legend = text(page1, fontSmall, 0.7, 0.7, 0.7)
    legend:SetPoint("BOTTOMLEFT", 14, 44)
    legend:SetText("Zlatý rámeček = nastavil sis sám, šedý = výchozí. Šedé kouzlo = zatím ho neumíš.\nPravé tlačítko = smazat, levé = další možnosti. Změny v boji se projeví po boji.")
    legend:SetJustifyH("LEFT")

    local reset = CreateFrame("Button", nil, page1, "UIPanelButtonTemplate")
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
