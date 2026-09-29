-- Medic: rámečky skupiny a raidu s léčením na kliknutí myši
--  * rámečky dělá bezpečná hlavička hry (SecureGroupHeaderTemplate) – funguje i v boji
--  * kouzla na tlačítka myši (s Shift/Ctrl/Alt) přes atributy bezpečných tlačítek
--  * debuffy, které umíš odstranit, příchozí léčení, aggro, chybějící buff
-- Texty do chatu jsou bez háčků: písmo chatu neumí č/ř/ů.

local ADDON = ...
local M = {}
local FONT = "Interface\\AddOns\\Medic\\Fonts\\cz.ttf"   -- herní písmo neumí č/ř/ů
_G.Medic = M

-------------------------------------------------------------------------------
-- Výchozí kouzla podle povolání. Každé tlačítko má seznam kandidátů – použije se
-- první, které postava umí (nízká úroveň = ještě nemá Flash of Light apod.).
-- Klíč: [modifikátor-]tlačítko (1 levé, 2 pravé, 3 prostřední, 4/5 boční).
-- Zvláštní akce: "target" = označit hráče, "menu" = nabídka hráče.
-------------------------------------------------------------------------------
local DEFAULT_BINDS = {
    PALADIN = {
        ["1"] = { "Flash of Light", "Holy Light" },
        ["2"] = { "Holy Light" },
        ["3"] = { "Holy Shock", "Lay on Hands" },
        ["shift-1"] = { "Cleanse", "Purify" },
        ["shift-2"] = { "Blessing of Might" },
        ["ctrl-1"] = { "target" },
        ["ctrl-2"] = { "menu" },
    },
    PRIEST = {
        ["1"] = { "Flash Heal", "Lesser Heal" },
        ["2"] = { "Greater Heal", "Heal", "Lesser Heal" },
        ["3"] = { "Renew" },
        ["shift-1"] = { "Dispel Magic" },
        ["shift-2"] = { "Power Word: Shield" },
        ["alt-1"] = { "Cure Disease", "Abolish Disease" },
        ["ctrl-1"] = { "target" },
        ["ctrl-2"] = { "menu" },
    },
    DRUID = {
        ["1"] = { "Rejuvenation" },
        ["2"] = { "Healing Touch" },
        ["3"] = { "Regrowth" },
        ["shift-1"] = { "Remove Curse" },
        ["shift-2"] = { "Abolish Poison", "Cure Poison" },
        ["ctrl-1"] = { "target" },
        ["ctrl-2"] = { "menu" },
    },
    SHAMAN = {
        ["1"] = { "Lesser Healing Wave", "Healing Wave" },
        ["2"] = { "Healing Wave" },
        ["3"] = { "Chain Heal" },
        ["shift-1"] = { "Cure Poison" },
        ["shift-2"] = { "Cure Disease" },
        ["ctrl-1"] = { "target" },
        ["ctrl-2"] = { "menu" },
    },
    DEFAULT = {
        ["1"] = { "target" },
        ["2"] = { "menu" },
    },
}

-- Buffy, které má povolání hlídat: ikonka svítí, když hráč žádný z nich nemá.
-- prefix = stačí začátek názvu (Blessing of Might / Wisdom / …), mine = jen buff ode mě
local CLASS_BUFFS = {
    PALADIN = { names = { "Blessing of ", "Greater Blessing of " }, prefix = true, mine = true, spell = "Blessing of Might" },
    PRIEST  = { names = { "Power Word: Fortitude", "Prayer of Fortitude" }, spell = "Power Word: Fortitude" },
    MAGE    = { names = { "Arcane Intellect", "Arcane Brilliance" }, spell = "Arcane Intellect" },
    DRUID   = { names = { "Mark of the Wild", "Gift of the Wild" }, spell = "Mark of the Wild" },
}

local DEFAULTS = {
    width = 90, height = 38, scale = 1,
    point = { "CENTER", -300, 0 },
    locked = false,
    classBinds = {},   -- ruční přiřazení hráče podle povolání: classBinds.DRUID["shift-1"] = "Remove Curse"
    classKeys = {},    -- klávesy při najetí na rámeček: classKeys.DRUID["SHIFT-Q"] = "Rejuvenation" (false = klávesa bez kouzla)
    showSolo = true,
    buffs = true,        -- hlídat chybějící buff
    buffOOC = false,     -- ikonku buffu ukazovat jen mimo boj
    buffMode = "missing", -- "missing" = ikonka svítí, když buff chybí; "present" = svítí, dokud ho hráč má
    buffNames = {},      -- vlastní hlídané buffy podle povolání: buffNames.PRIEST = "Power Word: Fortitude, Prayer of Fortitude"
    buffMine = {},       -- jen buff ode mě podle povolání (nil = výchozí povolání)
    debuffs = true,      -- zvýraznit debuffy, které umím odstranit
    debuffIcon = true,   -- ikonka debuffu v rohu
    debuffAll = false,   -- ukázat ikonku i u ostatních debuffů
    aggro = true,
    aggroStyle = "pruh", -- "pruh" = proužek nahoře, "ramecek" = celý rámeček červeně
    debuffBlink = true,  -- rámeček bliká, když jde debuff odstranit
    colorMode = "hp",    -- "hp" = zelená/žlutá/červená podle zdraví, "class" = barva povolání
    roleIcons = true,    -- ikonka role (tank, healer, dps)
    sortRoles = true,    -- řadit tank -> healer -> dps zleva doprava
    hots = true,         -- ikonky mých HoTů s odpočtem
    hotSize = 15,        -- velikost ikonek HoTů
    buffSize = 12,       -- velikost ikonky chybějícího buffu
    debuffSize = 14,     -- velikost ikonky debuffu
    targetHighlight = true, -- bílý rámeček kolem hráče, kterého mám v cíli
    powerBar = true,     -- pruh many dole
    powerHealersOnly = false, -- pruh many jen u healerů
    powerHeight = 4,
    absorbs = true,      -- štíty (absorpce) jako světlý pruh za zdravím
    rezIcon = true,      -- ikonka, když mrtvého někdo oživuje
    targetOf = true,     -- lebka u hráče, na kterého útočí můj nepřátelský cíl
    orientation = "horizontal", -- "horizontal" = vedle sebe, "vertical" = pod sebou
    perRow = 5,          -- hráčů v jedné řadě / sloupci
    spacing = 2,         -- mezera mezi rámečky
}

-- HoTy a štíty, které se ukazují v rámečku (když hra názvy aur neskrývá; jinak všechny krátké moje buffy)
local HOTS = {
    ["Rejuvenation"] = true, ["Regrowth"] = true, ["Lifebloom"] = true, ["Wild Growth"] = true,
    ["Renew"] = true, ["Power Word: Shield"] = true, ["Prayer of Mending"] = true,
    ["Earth Shield"] = true, ["Riptide"] = true, ["Healing Stream"] = true,
    ["Beacon of Light"] = true, ["Sacred Shield"] = true,
}

local MODS = { "", "alt-", "ctrl-", "shift-", "alt-ctrl-", "alt-shift-", "ctrl-shift-", "alt-ctrl-shift-" }
local MOD_NAMES = { alt = "Alt", ctrl = "Ctrl", shift = "Shift" }
local BUTTON_NAMES = { ["1"] = "leve", ["2"] = "prave", ["3"] = "prostredni", ["4"] = "bocni 4", ["5"] = "bocni 5" }

local playerClass = select(2, UnitClass("player"))
local header, anchor
local pendingApply = false

local function msg(text) print("|cff33ff99Medic:|r " .. text) end

-------------------------------------------------------------------------------
-- Pomocné funkce
-------------------------------------------------------------------------------
local function knowsSpell(name)
    if name == "target" or name == "menu" then return true end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info then return true end
    end
    if GetSpellInfo then return GetSpellInfo(name) ~= nil end
    return false
end

local function spellIcon(name)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, name)
        if ok and tex then return tex end
    end
    if GetSpellTexture then return GetSpellTexture(name) end
end

-- Projde aury jednotky (moderní i starší API)
-- fn(name, icon, dispelName, source, aura) – aura = celá tabulka (duration, expirationTime, auraInstanceID…)
local function forEachAura(unit, filter, fn)
    for i = 1, 40 do
        local name, icon, dispelName, source, aura
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not a then return end
            name, icon, dispelName, source, aura = a.name, a.icon, a.dispelName, a.sourceUnit, a
        else
            local n, ic, _, dtype, dur, exp, src = UnitAura(unit, i, filter)
            if not n then return end
            name, icon, dispelName, source = n, ic, dtype, src
            aura = { name = n, icon = ic, duration = dur, expirationTime = exp }
        end
        if fn(name, icon, dispelName, source, aura) then return end
    end
end

-- "Shift-1", "shift+1", "SHIFT-LEVE" -> "shift-1"; nil, když se to nedá přečíst
local WORD_BUTTONS = { leve = "1", prave = "2", prostredni = "3", stredni = "3" }
local function normalizeKey(key)
    key = (key or ""):lower():gsub("%+", "-")
    local mods, btn = {}, nil
    for part in key:gmatch("[^%-]+") do
        if part == "alt" or part == "ctrl" or part == "shift" then mods[part] = true
        elseif part:match("^[1-5]$") then btn = part
        elseif WORD_BUTTONS[part] then btn = WORD_BUTTONS[part]
        else return nil end
    end
    if not btn then return nil end
    return (mods.alt and "alt-" or "") .. (mods.ctrl and "ctrl-" or "") .. (mods.shift and "shift-" or "") .. btn
end

local function keyLabel(key)
    local mod, btn = key:match("^(.-)(%d)$")
    local parts = {}
    for m in mod:gmatch("(%a+)%-") do parts[#parts + 1] = MOD_NAMES[m] end
    parts[#parts + 1] = BUTTON_NAMES[btn] or btn
    return table.concat(parts, " + ")
end

-- Výsledné přiřazení: ruční nastavení hráče, jinak první známé výchozí kouzlo
local function effectiveBinds()
    local out = {}
    local defaults = DEFAULT_BINDS[playerClass] or DEFAULT_BINDS.DEFAULT
    for key, list in pairs(defaults) do
        local pick = list[1]
        for _, name in ipairs(list) do
            if knowsSpell(name) then pick = name break end
        end
        out[key] = pick
    end
    for key, action in pairs(MedicDB.classBinds[playerClass] or {}) do
        if action == false or action == "" then out[key] = nil else out[key] = action end
    end
    return out
end

-- Atributy bezpečného tlačítka pro jedno přiřazení
local function bindAttributes(key, action)
    local mod, btn = key:match("^(.-)(%d)$")
    if action == "target" then return { [mod .. "type" .. btn] = "target" } end
    if action == "menu" then return { [mod .. "type" .. btn] = "togglemenu" } end
    return { [mod .. "type" .. btn] = "spell", [mod .. "spell" .. btn] = action }
end

-------------------------------------------------------------------------------
-- Vzhled jednoho rámečku (volá se i v boji – jen nechráněné věci)
-------------------------------------------------------------------------------
local buttons = {}
local wrapKeys   -- klávesy při najetí (definováno níž)
local updateButton

local function styleButton(btn)
    if btn.medic then return end
    btn.medic = true
    buttons[#buttons + 1] = btn
    btn:RegisterForClicks("AnyUp")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)

    local hp = CreateFrame("StatusBar", nil, btn)
    hp:SetPoint("TOPLEFT", 2, -2)
    hp:SetPoint("BOTTOMRIGHT", -2, 2)
    hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    hp:SetMinMaxValues(0, 1)
    btn.hp = hp

    local hpBg = hp:CreateTexture(nil, "BACKGROUND")
    hpBg:SetAllPoints()
    hpBg:SetColorTexture(0.15, 0.15, 0.15, 1)
    btn.hpBg = hpBg

    -- příchozí léčení: světlejší pruh hned za zdravím
    -- (ukazatel, ne obrázek: hodnota může být tajná, s tou umí jen ukazatel; přesah za rámeček se ořízne)
    hp:SetClipsChildren(true)
    local heal = CreateFrame("StatusBar", nil, hp)
    heal:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    heal:SetStatusBarColor(0.3, 1, 0.3, 0.55)
    heal:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT")
    heal:SetPoint("BOTTOMLEFT", hp:GetStatusBarTexture(), "BOTTOMRIGHT")
    heal:SetWidth(1)
    heal:SetFrameLevel(hp:GetFrameLevel() + 1)
    heal:SetMinMaxValues(0, 1)
    heal:SetValue(0)

    -- štíty (absorpce): navazuje na konec příchozího léčení
    local absorb = CreateFrame("StatusBar", nil, hp)
    absorb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    absorb:SetStatusBarColor(0.85, 0.95, 1, 0.6)
    absorb:SetPoint("TOPLEFT", heal:GetStatusBarTexture(), "TOPRIGHT")
    absorb:SetPoint("BOTTOMLEFT", heal:GetStatusBarTexture(), "BOTTOMRIGHT")
    absorb:SetWidth(1)
    absorb:SetFrameLevel(hp:GetFrameLevel() + 1)
    absorb:Hide()
    btn.absorb = absorb

    -- pruh many dole
    local power = CreateFrame("StatusBar", nil, btn)
    power:SetPoint("BOTTOMLEFT", 2, 2)
    power:SetPoint("BOTTOMRIGHT", -2, 2)
    power:SetHeight(4)
    power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    power:SetStatusBarColor(0.15, 0.45, 1)
    power:Hide()
    btn.power = power
    btn.heal = heal

    local overlay = CreateFrame("Frame", nil, btn)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(hp:GetFrameLevel() + 2)

    local name = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", 4, -4)
    name:SetPoint("TOPRIGHT", -14, -4)
    name:SetFont(FONT, 11, "")
    name:SetShadowOffset(1, -1)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    btn.nameText = name

    local role = overlay:CreateTexture(nil, "OVERLAY")
    role:SetSize(12, 12)
    role:SetPoint("TOPLEFT", 3, -3)
    role:Hide()
    btn.roleIcon = role

    local info = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("RIGHT", -4, 1)
    info:SetFont(FONT, 10, "")
    info:SetShadowOffset(1, -1)
    info:SetJustifyH("RIGHT")
    btn.infoText = info

    -- aggro: červený proužek nahoře
    local aggro = overlay:CreateTexture(nil, "OVERLAY")
    aggro:SetColorTexture(1, 0.1, 0.1, 1)
    aggro:SetPoint("TOPLEFT", 0, 0)
    aggro:SetPoint("TOPRIGHT", 0, 0)
    aggro:SetHeight(3)
    aggro:Hide()
    btn.aggro = aggro

    local aggroBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    aggroBorder:SetPoint("TOPLEFT", -2, 2)
    aggroBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    aggroBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    aggroBorder:SetBackdropBorderColor(1, 0.1, 0.1, 1)
    aggroBorder:Hide()
    btn.aggroBorder = aggroBorder

    -- cíl: bílý rámeček
    local targetBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    targetBorder:SetPoint("TOPLEFT", -1, 1)
    targetBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    targetBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    targetBorder:SetBackdropBorderColor(1, 1, 1, 0.9)
    targetBorder:SetFrameLevel(btn:GetFrameLevel() + 6)
    targetBorder:Hide()
    btn.targetBorder = targetBorder

    -- oživování: ikonka uprostřed
    local rez = overlay:CreateTexture(nil, "OVERLAY")
    rez:SetSize(18, 18)
    rez:SetPoint("CENTER", 0, 0)
    rez:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    rez:Hide()
    btn.rezIcon = rez

    -- na koho útočí můj cíl: lebka nahoře uprostřed
    local skull = overlay:CreateTexture(nil, "OVERLAY")
    skull:SetSize(14, 14)
    skull:SetPoint("TOP", 0, 3)
    skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    skull:Hide()
    btn.targetOfIcon = skull

    -- debuff, který umíš odstranit: barevný rámeček (barva podle typu – magie, jed, nemoc, kletba)
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints()
    border:SetFrameLevel(overlay:GetFrameLevel() + 1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    border:Hide()
    btn.border = border

    -- blikání při debuffu: barevný závoj přes celý rámeček
    local flash = overlay:CreateTexture(nil, "ARTWORK")
    flash:SetAllPoints(hp)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetAlpha(0)
    local pulse = flash:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(0.45)
    a:SetDuration(0.45)
    btn.flash, btn.pulse = flash, pulse

    -- ikonky mých HoTů s odpočtem (vpravo dole, řadí se doleva)
    btn.hotIcons = {}
    for i = 1, 3 do
        local f = CreateFrame("Frame", nil, overlay)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cd:SetAllPoints()
        f.cd:SetReverse(true)
        f.cd:SetDrawEdge(false)
        f.time = f:CreateFontString(nil, "OVERLAY")
        f.time:SetFont(FONT, 9, "OUTLINE")
        f.time:SetPoint("CENTER", 0, 0)
        f:Hide()
        btn.hotIcons[i] = f
    end

    local debuffIcon = overlay:CreateTexture(nil, "OVERLAY")
    debuffIcon:SetSize(14, 14)
    debuffIcon:SetPoint("BOTTOMLEFT", 4, 4)
    debuffIcon:Hide()
    btn.debuffIcon = debuffIcon

    -- chybějící buff (Blessing, Fortitude…)
    local buff = overlay:CreateTexture(nil, "OVERLAY")
    buff:SetSize(12, 12)
    buff:SetPoint("TOPRIGHT", -2, -2)
    buff:Hide()
    btn.buffIcon = buff
    M.LayoutHots(btn)   -- velikosti ikonek z nastavení

    wrapKeys(btn)
    btn:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "unit" then updateButton(self) end
    end)
    btn:HookScript("OnShow", function(self) updateButton(self) end)
    btn:HookScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if not unit then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(unit)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-------------------------------------------------------------------------------
-- Hlídaný buff: vlastní seznam z nastavení, jinak výchozí podle povolání
-------------------------------------------------------------------------------
function M.BuffConfig()
    local def = CLASS_BUFFS[playerClass]
    local custom = MedicDB.buffNames[playerClass]
    local cfg
    if custom and custom:find("%S") then
        cfg = { names = {}, custom = true }
        for name in custom:gmatch("[^,]+") do
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then cfg.names[#cfg.names + 1] = name end
        end
        cfg.spell = cfg.names[1]
        cfg.mine = false
    elseif def then
        cfg = { names = def.names, prefix = def.prefix, mine = def.mine, spell = def.spell }
    else
        return nil
    end
    local mine = MedicDB.buffMine[playerClass]
    if mine ~= nil then cfg.mine = mine end
    return cfg
end
function M.BuffDefaultText()
    local def = CLASS_BUFFS[playerClass]
    if not def then return nil end
    local list = {}
    for _, n in ipairs(def.names) do list[#list + 1] = def.prefix and (n .. "…") or n end
    return table.concat(list, ", ")
end

-------------------------------------------------------------------------------
-- Aktualizace rámečku
-------------------------------------------------------------------------------
-- WoW Forever (stejně jako nový retail) vrací zdraví, dosah, aury… jako „tajné hodnoty“:
-- addon je smí jen předat ukazateli (StatusBar, SetText, SetTexture), ale nesmí s nimi počítat
-- ani je porovnávat. secret(x) = true -> s hodnotou nic nepočítat.
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function flag(v) if secret(v) then return false end return v and true or false end

-- Souřadnice ikon rolí v textuře UI-LFG-ICON-PORTRAITROLES
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

-- Barva zdraví: zelená -> žlutá -> červená. U tajných hodnot to spočítá hra sama (křivka barev),
-- když to neumí, zůstane barva povolání.
local hpCurve
local function setHealthColor(btn, unit, hp, maxHp, classColor)
    if MedicDB.colorMode == "class" then
        btn.hp:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        return
    end
    if not secret(hp) and not secret(maxHp) then
        local p = maxHp > 0 and hp / maxHp or 0
        if p >= 0.5 then btn.hp:SetStatusBarColor((1 - p) * 2, 0.85, 0.1)
        else btn.hp:SetStatusBarColor(1, p * 2 * 0.85, 0.1) end
        return
    end
    local ok = pcall(function()
        if not hpCurve then
            hpCurve = C_CurveUtil.CreateColorCurve()
            hpCurve:AddPoint(0, CreateColor(1, 0, 0.1))
            hpCurve:AddPoint(0.5, CreateColor(1, 0.85, 0.1))
            hpCurve:AddPoint(1, CreateColor(0.1, 0.85, 0.1))
        end
        local col = UnitHealthPercent(unit, false, hpCurve)
        btn.hp:GetStatusBarTexture():SetVertexColor(col:GetRGB())
    end)
    if not ok then btn.hp:SetStatusBarColor(classColor.r, classColor.g, classColor.b) end
end

-- Pruh many (jen jednotky s manou; volitelně jen healeři). Zdraví se podle něj zkrátí.
function M.UpdatePower(btn, unit)
    local show = MedicDB.powerBar
    if show then
        local pt = UnitPowerType(unit)
        show = not secret(pt) and pt == 0
        if show and MedicDB.powerHealersOnly then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            show = not secret(role) and role == "HEALER"
        end
    end
    local h = MedicDB.powerHeight or 4
    if show then
        btn.power:SetHeight(h)
        btn.power:SetMinMaxValues(0, UnitPowerMax(unit, 0))
        btn.power:SetValue(UnitPower(unit, 0))
        btn.power:Show()
    else
        btn.power:Hide()
    end
    btn.hp:SetPoint("BOTTOMRIGHT", -2, show and (3 + h) or 2)
end

function M.LayoutHots(btn)
    if btn.buffIcon then btn.buffIcon:SetSize(MedicDB.buffSize or 12, MedicDB.buffSize or 12) end
    if btn.debuffIcon then btn.debuffIcon:SetSize(MedicDB.debuffSize or 14, MedicDB.debuffSize or 14) end
    local s = MedicDB.hotSize or 15
    for i, f in ipairs(btn.hotIcons) do
        f:SetSize(s, s)
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", -3 - (i - 1) * (s + 1), 3)
        f.time:SetFont(FONT, math.max(8, math.floor(s * 0.6)), "OUTLINE")
    end
end
-- velikost ikonek: what = "hotSize" / "buffSize" / "debuffSize"
function M.SetIconSize(what, s)
    MedicDB[what] = s
    for _, btn in ipairs(buttons) do M.LayoutHots(btn) end
end

local function hotTime(f)
    if not f.expires then f.time:SetText("") return end
    local left = f.expires - GetTime()
    if left <= 0 then f.time:SetText("") return end
    f.time:SetText(left >= 10 and ("%d"):format(left) or ("%.0f"):format(left))
end

local function updateHots(btn, unit, hide)
    local n = 0
    if MedicDB.hots and not hide then
        forEachAura(unit, "HELPFUL|PLAYER", function(name, icon, _, _, a)
            -- jen HoTy/štíty: podle názvu, a když je název tajný, podle krátkého trvání
            if not secret(name) and name and not HOTS[name] then
                if secret(a.duration) or not a.duration or a.duration == 0 or a.duration > 60 then return end
            end
            if secret(name) and not secret(a.duration) and (not a.duration or a.duration == 0 or a.duration > 60) then return end
            n = n + 1
            local f = btn.hotIcons[n]
            f.icon:SetTexture(icon)
            f.expires = nil
            if not secret(a.expirationTime) and not secret(a.duration) and a.duration and a.duration > 0 then
                f.cd:SetCooldown(a.expirationTime - a.duration, a.duration)
                f.cd:SetHideCountdownNumbers(true)
                f.expires = a.expirationTime
            else
                -- tajný čas: odpočet vykreslí hra sama (čísla na cooldownu)
                f.cd:SetHideCountdownNumbers(false)
                pcall(function() f.cd:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, a.auraInstanceID)) end)
            end
            hotTime(f)
            f:Show()
            return n >= #btn.hotIcons
        end)
    end
    for i = n + 1, #btn.hotIcons do btn.hotIcons[i]:Hide(); btn.hotIcons[i].expires = nil end
end

local function updateRange(btn, unit)
    if UnitIsUnit(unit, "player") or not UnitInRange then btn:SetAlpha(1) return end
    local r, checked = UnitInRange(unit)
    if secret(r) or secret(checked) then
        if btn.SetAlphaFromBoolean then btn:SetAlphaFromBoolean(r, 1, 0.4) else btn:SetAlpha(1) end
        return
    end
    btn:SetAlpha((checked and not r) and 0.4 or 1)
end

function updateButton(btn)
    if not btn.medic then return end
    local unit = btn:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    local _, class = UnitClass(unit)
    local c = (class and not secret(class) and RAID_CLASS_COLORS[class]) or { r = 0.2, g = 0.8, b = 0.2 }
    btn.nameText:SetText(UnitName(unit) or "")
    btn.nameText:SetTextColor(1, 1, 1)

    -- role (tank, healer, dps)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if secret(role) then role = nil end
    local coords = role and ROLE_COORDS[role]
    if MedicDB.roleIcons and coords then
        btn.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        btn.roleIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        btn.roleIcon:Show()
        btn.nameText:SetPoint("TOPLEFT", 17, -4)
    else
        btn.roleIcon:Hide()
        btn.nameText:SetPoint("TOPLEFT", 4, -4)
    end

    -- zdraví: hodnoty rovnou do ukazatele (funguje i s tajnými hodnotami)
    local hp, maxHp = UnitHealth(unit), UnitHealthMax(unit)
    btn.hp:SetMinMaxValues(0, maxHp)
    btn.hp:SetValue(hp)

    local dead = flag(UnitIsDeadOrGhost(unit))
    local offline = not flag(UnitIsConnected(unit))
    btn.infoText:SetText("")
    if offline then
        btn.hp:SetStatusBarColor(0.3, 0.3, 0.3)
        btn.infoText:SetText("Offline")
        btn.infoText:SetTextColor(0.6, 0.6, 0.6)
    elseif dead then
        btn.hp:SetValue(0)
        btn.infoText:SetText("Mrtvý")
        btn.infoText:SetTextColor(0.8, 0.3, 0.3)
    else
        setHealthColor(btn, unit, hp, maxHp, c)
        -- chybějící HP jde spočítat jen u netajných hodnot
        if not secret(hp) and not secret(maxHp) then
            local deficit = maxHp - hp
            if deficit > 0 then
                btn.infoText:SetText("-" .. (deficit >= 10000 and (math.floor(deficit / 1000) .. "k") or deficit))
                btn.infoText:SetTextColor(1, 0.4, 0.4)
            end
        end
    end

    -- příchozí léčení: druhý ukazatel navazuje na konec zdraví (bez počítání, přesah se ořízne)
    local incoming = (not dead and not offline and UnitGetIncomingHeals) and UnitGetIncomingHeals(unit) or nil
    btn.heal:SetWidth(math.max(btn.hp:GetWidth(), 1))
    btn.heal:SetMinMaxValues(0, maxHp)
    btn.heal:SetValue(incoming or 0)
    btn.heal:Show()

    -- štíty
    local absorbs = (MedicDB.absorbs and not dead and not offline and UnitGetTotalAbsorbs) and UnitGetTotalAbsorbs(unit) or nil
    if absorbs ~= nil then
        btn.absorb:SetWidth(math.max(btn.hp:GetWidth(), 1))
        btn.absorb:SetMinMaxValues(0, maxHp)
        btn.absorb:SetValue(absorbs)
        btn.absorb:Show()
    else
        btn.absorb:Hide()
    end

    -- cíl
    btn.targetBorder:SetShown(MedicDB.targetHighlight and flag(UnitIsUnit(unit, "target")))
    -- na koho útočí můj nepřátelský cíl
    local targeted = MedicDB.targetOf and UnitExists("target") and flag(UnitCanAttack("player", "target"))
        and flag(UnitIsUnit(unit, "targettarget"))
    btn.targetOfIcon:SetShown(targeted and true or false)

    -- mrtvý / oživování
    if dead then
        btn.hpBg:SetColorTexture(0.25, 0.05, 0.05, 1)
        btn.nameText:SetTextColor(0.6, 0.6, 0.6)
        if flag(UnitIsGhost(unit)) then btn.infoText:SetText("Duch") end
    else
        btn.hpBg:SetColorTexture(0.15, 0.15, 0.15, 1)
    end
    btn.rezIcon:SetShown(MedicDB.rezIcon and dead and UnitHasIncomingResurrection ~= nil and flag(UnitHasIncomingResurrection(unit)))

    M.UpdatePower(btn, unit)

    -- aggro (tajnou hodnotu porovnat nejde -> nezobrazit)
    local threat = UnitThreatSituation and UnitThreatSituation(unit)
    local hasAggro = MedicDB.aggro and not secret(threat) and threat ~= nil and threat >= 2
    btn.aggro:SetShown(hasAggro and MedicDB.aggroStyle ~= "ramecek")
    btn.aggroBorder:SetShown(hasAggro and MedicDB.aggroStyle == "ramecek")

    -- debuff, který umím odstranit
    local found, dispelType, dispelIcon = false, nil, nil
    if not dead and MedicDB.debuffs then
        for _, filter in ipairs({ "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|RAID" }) do
            forEachAura(unit, filter, function(_, icon, dtype)
                found, dispelIcon = true, icon
                if not secret(dtype) then dispelType = dtype end
                return true
            end)
            if found then break end
        end
    end
    -- ostatní debuffy (nejdou odstranit): jen ikonka, bez rámečku
    local otherIcon
    if not found and not dead and MedicDB.debuffAll then
        forEachAura(unit, "HARMFUL", function(_, icon) otherIcon = icon return true end)
    end
    if found then
        local dc = (dispelType and DebuffTypeColor and DebuffTypeColor[dispelType]) or { r = 0.8, g = 0, b = 0.8 }
        btn.border:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1)
        btn.border:Show()
        if MedicDB.debuffBlink then
            btn.flash:SetVertexColor(dc.r, dc.g, dc.b)
            if not btn.pulse:IsPlaying() then btn.pulse:Play() end
        end
    else
        btn.border:Hide()
    end
    if not (found and MedicDB.debuffBlink) and btn.pulse:IsPlaying() then
        btn.pulse:Stop()
        btn.flash:SetAlpha(0)
    end

    updateHots(btn, unit, dead or offline)
    local shownIcon = (found and MedicDB.debuffIcon and dispelIcon) or otherIcon
    if shownIcon then
        btn.debuffIcon:SetTexture(shownIcon)
        btn.debuffIcon:Show()
    else
        btn.debuffIcon:Hide()
    end

    -- chybějící buff (když jsou názvy aur tajné, stav se nemění)
    local cfg = MedicDB.buffs and M.BuffConfig()
    local missing, unknown, haveIcon = false, false, nil
    if MedicDB.buffOOC and InCombatLockdown() then cfg = nil end
    if cfg and not dead and not offline and (cfg.custom or knowsSpell(cfg.spell)) then
        missing = true
        forEachAura(unit, "HELPFUL", function(name, icon, _, source)
            if secret(name) or secret(source) then unknown = true return true end
            if not name then return end
            if cfg.mine and source ~= "player" then return end
            for _, want in ipairs(cfg.names) do
                if (cfg.prefix and name:sub(1, #want) == want) or name == want then missing, haveIcon = false, icon return true end
            end
        end)
    end
    if unknown then
        -- nechat, jak bylo
    elseif MedicDB.buffMode == "present" then
        -- ikonka svítí, dokud buff má (a zmizí, když spadne)
        if cfg and haveIcon then
            btn.buffIcon:SetTexture(haveIcon)
            btn.buffIcon:Show()
        else
            btn.buffIcon:Hide()
        end
    elseif missing then
        btn.buffIcon:SetTexture(spellIcon(cfg.spell) or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.buffIcon:Show()
    else
        btn.buffIcon:Hide()
    end

    updateRange(btn, unit)
end
local function updateAll()
    for _, btn in ipairs(buttons) do
        if btn:IsVisible() then updateButton(btn) end
    end
end

M.UpdateAll = function() updateAll() end

local function updateUnit(unit)
    for _, btn in ipairs(buttons) do
        local u = btn:GetAttribute("unit")
        if u and btn:IsVisible() and (u == unit or UnitIsUnit(u, unit)) then updateButton(btn) end
    end
end

-------------------------------------------------------------------------------
-- Přiřazení kouzel (jen mimo boj – hra v boji nedovolí měnit bezpečná tlačítka)
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Klávesy při najetí na rámeček: při OnEnter si rámeček (v bezpečném kódu) přivlastní
-- klávesy jako „kliknutí“ virtuálním tlačítkem MK1, MK2… a při OnLeave je pustí.
-------------------------------------------------------------------------------
local MAX_KEYS = 24
local function keyList()
    local list = {}
    for key, action in pairs(MedicDB.classKeys[playerClass] or {}) do
        if action then list[#list + 1] = { key = key, action = action } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    while #list > MAX_KEYS do table.remove(list) end
    return list
end

local function keyAttributes(i, action)
    local b = "-MK" .. i
    if action == "target" then return { ["*type" .. b] = "target" } end
    if action == "menu" then return { ["*type" .. b] = "togglemenu" } end
    return { ["*type" .. b] = "spell", ["*spell" .. b] = action }
end

local keyHandler = CreateFrame("Frame", "MedicKeyHandler", UIParent, "SecureHandlerBaseTemplate")
local KEY_ENTER = [[
    local n = control:GetAttribute("medic-keys") or 0
    for i = 1, n do
        local k = control:GetAttribute("medic-key" .. i)
        if k then self:SetBindingClick(true, k, self, "MK" .. i) end
    end
]]
local KEY_LEAVE = [[ self:ClearBindings() ]]
local wrapped, pendingWrap = {}, {}

wrapKeys = function(btn)
    if wrapped[btn] then return end
    if InCombatLockdown() then pendingWrap[btn] = true return end
    SecureHandlerWrapScript(btn, "OnEnter", keyHandler, KEY_ENTER)
    SecureHandlerWrapScript(btn, "OnLeave", keyHandler, KEY_LEAVE)
    SecureHandlerWrapScript(btn, "OnHide", keyHandler, KEY_LEAVE)
    wrapped[btn] = true
    pendingWrap[btn] = nil
end

-- rámečky vzniklé v boji dostanou klávesy až po boji
function M.WrapPending()
    for btn in pairs(pendingWrap) do wrapKeys(btn) end
end

local function applyKeys()
    local list = keyList()
    keyHandler:SetAttribute("medic-keys", #list)
    for i = 1, MAX_KEYS do keyHandler:SetAttribute("medic-key" .. i, list[i] and list[i].key or nil) end
    for _, btn in ipairs(buttons) do
        for i = 1, MAX_KEYS do
            btn:SetAttribute("*type-MK" .. i, nil)
            btn:SetAttribute("*spell-MK" .. i, nil)
        end
        for i, kv in ipairs(list) do
            for attr, value in pairs(keyAttributes(i, kv.action)) do btn:SetAttribute(attr, value) end
        end
        wrapKeys(btn)
    end
end

local function buildSnippet(binds)
    local lines = {
        ("self:SetWidth(%d)"):format(MedicDB.width),
        ("self:SetHeight(%d)"):format(MedicDB.height),
    }
    for key, action in pairs(binds) do
        for attr, value in pairs(bindAttributes(key, action)) do
            lines[#lines + 1] = ("self:SetAttribute(%q, %q)"):format(attr, value)
        end
    end
    for i, kv in ipairs(keyList()) do
        for attr, value in pairs(keyAttributes(i, kv.action)) do
            lines[#lines + 1] = ("self:SetAttribute(%q, %q)"):format(attr, value)
        end
    end
    -- vzhled dodělá Lua (voláno i pro rámečky vytvořené v boji)
    lines[#lines + 1] = 'self:GetParent():CallMethod("MedicStyle", self:GetName())'
    return table.concat(lines, "\n")
end

function M.ApplyBindings()
    if not header then return end
    if InCombatLockdown() then pendingApply = true return end
    pendingApply = false
    local binds = effectiveBinds()
    header:SetAttribute("initialConfigFunction", buildSnippet(binds))
    for _, btn in ipairs(buttons) do
        for _, mod in ipairs(MODS) do
            for b = 1, 5 do
                btn:SetAttribute(mod .. "type" .. b, nil)
                btn:SetAttribute(mod .. "spell" .. b, nil)
            end
        end
        for key, action in pairs(binds) do
            for attr, value in pairs(bindAttributes(key, action)) do btn:SetAttribute(attr, value) end
        end
        btn:SetSize(MedicDB.width, MedicDB.height)
    end
    applyKeys()
    -- přepočítat rozložení hlavičky
    header:SetAttribute("showSolo", MedicDB.showSolo)
end

-------------------------------------------------------------------------------
-- Rozhraní pro okno nastavení (Okno.lua)
-------------------------------------------------------------------------------
-- action: název kouzla, "target", "menu"; false = nic; nil = výchozí
function M.SetBind(key, action)
    MedicDB.classBinds[playerClass] = MedicDB.classBinds[playerClass] or {}
    MedicDB.classBinds[playerClass][key] = action
    M.ApplyBindings()
end
-- klávesy: action = kouzlo / "target" / "menu"; false = klávesa zatím bez kouzla; nil = smazat
function M.SetKey(key, action)
    MedicDB.classKeys[playerClass] = MedicDB.classKeys[playerClass] or {}
    MedicDB.classKeys[playerClass][key] = action
    M.ApplyBindings()
end
function M.GetKeys()
    return MedicDB.classKeys[playerClass] or {}
end
M.MaxKeys = MAX_KEYS
function M.ResetBinds()
    MedicDB.classBinds[playerClass] = nil
    M.ApplyBindings()
end
M.GetBinds = function() return effectiveBinds() end
M.KnowsSpell = knowsSpell
M.SpellIcon = spellIcon
M.KeyLabel = keyLabel
M.Msg = msg
M.Class = playerClass
-- řazení: tank -> healer -> dps (hlavička hry řadí podle role přidělené ve skupině)
function M.ApplySort()
    if not header or InCombatLockdown() then return false end
    if MedicDB.sortRoles then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    else
        header:SetAttribute("groupBy", "GROUP")
        header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    end
    header:SetAttribute("sortMethod", "INDEX")
    return true
end

-- rozložení: vedle sebe / pod sebou, počet v řadě, mezery (jen mimo boj)
function M.ApplyGrid()
    if not header or InCombatLockdown() then return false end
    local per, sp = MedicDB.perRow or 5, MedicDB.spacing or 2
    -- staré ukotvení pryč, jinak se k němu přidá nové a rámečky „ujedou“ šikmo
    for _, btn in ipairs(buttons) do btn:ClearAllPoints() end
    if MedicDB.orientation == "vertical" then
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", -sp)
        header:SetAttribute("columnAnchorPoint", "LEFT")
        header:SetAttribute("point", "TOP")
    else
        header:SetAttribute("xOffset", sp)
        header:SetAttribute("yOffset", 0)
        header:SetAttribute("columnAnchorPoint", "TOP")
        header:SetAttribute("point", "LEFT")
    end
    header:SetAttribute("columnSpacing", sp)
    header:SetAttribute("maxColumns", math.ceil(40 / per))
    header:SetAttribute("unitsPerColumn", per)
    return true
end

-- velikost a měřítko rámečků (jen mimo boj); vrací false, když to hra teď nedovolí
function M.SetLayout(w, h, s)
    if InCombatLockdown() then return false end
    MedicDB.width, MedicDB.height, MedicDB.scale = w, h, s
    anchor:SetWidth(w)
    anchor:SetScale(s)
    M.ApplyBindings()
    return true
end
M.IsCustom = function(key)
    local t = MedicDB.classBinds[playerClass]
    return t ~= nil and t[key] ~= nil
end

-------------------------------------------------------------------------------
-- Kotva (přesouvání) a hlavička
-------------------------------------------------------------------------------
local function savePosition()
    local point, _, _, x, y = anchor:GetPoint()
    MedicDB.point = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function updateLock()
    if MedicDB.locked then anchor.handle:Hide() else anchor.handle:Show() end
end

local function createFrames()
    anchor = CreateFrame("Frame", "MedicAnchor", UIParent)
    anchor:SetSize(MedicDB.width, 14)
    anchor:SetPoint(MedicDB.point[1], UIParent, MedicDB.point[1], MedicDB.point[2], MedicDB.point[3])
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:SetScale(MedicDB.scale)

    local handle = CreateFrame("Button", nil, anchor)
    handle:SetAllPoints()
    local t = handle:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(0.1, 0.5, 0.3, 0.8)
    local label = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetFont(FONT, 10, "")
    label:SetText("Medic – táhni")
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        anchor:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        savePosition()
    end)
    anchor.handle = handle

    header = CreateFrame("Frame", "MedicHeader", anchor, "SecureGroupHeaderTemplate")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    header.MedicStyle = function(_, name)
        local btn = _G[name]
        if btn then styleButton(btn); updateButton(btn) end
    end
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("templateType", "Button")
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showSolo", MedicDB.showSolo)
    M.ApplySort()
    M.ApplyGrid()
    header:SetAttribute("initialConfigFunction", buildSnippet(effectiveBinds()))
    header:Show()

    updateLock()
end

-------------------------------------------------------------------------------
-- Příkazy /medic
-------------------------------------------------------------------------------
local function printBinds()
    local binds = effectiveBinds()
    local keys = {}
    for k in pairs(binds) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ma, ba = a:match("^(.-)(%d)$")
        local mb, bb = b:match("^(.-)(%d)$")
        if ma ~= mb then return #ma < #mb or (#ma == #mb and ma < mb) end
        return ba < bb
    end)
    msg("kouzla na mysi:")
    for _, k in ipairs(keys) do
        local a = binds[k]
        local label = a == "target" and "oznacit hrace" or a == "menu" and "nabidka hrace" or a
        local warn = (a ~= "target" and a ~= "menu" and not knowsSpell(a)) and " |cffff5555(zatim neumis)|r" or ""
        print(("   %s: |cffffff00%s|r%s"):format(keyLabel(k), label, warn))
    end
end

local HELP = {
    "/medic - okno s nastavenim kouzel (pretahni kouzlo ze spellbooku)",
    "/medic kouzla - vypise, co je na kterem tlacitku mysi",
    "/medic klik <tlacitko> <kouzlo> - napr. /medic klik shift-1 Cleanse",
    "     tlacitka: 1 leve, 2 prave, 3 prostredni, 4 a 5 bocni; pred cislo shift-, ctrl-, alt-",
    "     misto kouzla: target (oznacit), menu (nabidka), zadne (smazat), vychozi (vratit)",
    "/medic zamknout | odemknout - zamkne / ukaze tahlo pro presun",
    "/medic velikost <sirka> <vyska> - napr. /medic velikost 100 40",
    "/medic meritko <cislo> - zvetseni celeho okna, napr. 1.2",
    "/medic solo - zobrazovat i bez skupiny (zapnout/vypnout)",
    "/medic buffy - hlidani chybejicich buffu (zapnout/vypnout)",
    "/medic reset - vratit vse na vychozi",
}

local function slash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" and M.OpenOptions then M.OpenOptions() return end
    if cmd == "" or cmd == "help" or cmd == "pomoc" then
        msg("prikazy:")
        for _, l in ipairs(HELP) do print("   " .. l) end
        return
    end
    if cmd == "kouzla" or cmd == "seznam" then printBinds() return end

    local changesSecure = { klik = true, velikost = true, solo = true, reset = true }
    if changesSecure[cmd] and InCombatLockdown() then
        msg("v boji to hra nedovoli - zkus to po boji.")
        return
    end

    if cmd == "klik" then
        local keyText, action = rest:match("^(%S+)%s+(.+)$")
        local key = normalizeKey(keyText)
        if not key or not action then msg("pouziti: /medic klik shift-1 Cleanse") return end
        local low = action:lower()
        if low == "zadne" or low == "nic" or low == "-" then M.SetBind(key, false)
        elseif low == "vychozi" then M.SetBind(key, nil)
        elseif low == "target" or low == "oznacit" then M.SetBind(key, "target")
        elseif low == "menu" or low == "nabidka" then M.SetBind(key, "menu")
        else
            M.SetBind(key, action)
            if not knowsSpell(action) then msg("pozor: kouzlo '" .. action .. "' zatim neumis nebo je napsane jinak (nazev anglicky, jako ve spellbooku).") end
        end
        printBinds()
    elseif cmd == "zamknout" then
        MedicDB.locked = true; updateLock(); msg("zamceno.")
    elseif cmd == "odemknout" then
        MedicDB.locked = false; updateLock(); msg("odemceno - tahni za zelene tahlo.")
    elseif cmd == "velikost" then
        local w, h = rest:match("^(%d+)%s+(%d+)$")
        if not w then msg("pouziti: /medic velikost 90 38") return end
        MedicDB.width, MedicDB.height = tonumber(w), tonumber(h)
        anchor:SetWidth(MedicDB.width)
        M.ApplyBindings()
        msg(("velikost %dx%d."):format(MedicDB.width, MedicDB.height))
    elseif cmd == "meritko" then
        local s = tonumber((rest:gsub(",", ".")))
        if not s or s < 0.5 or s > 3 then msg("pouziti: /medic meritko 1.2 (0.5 az 3)") return end
        if InCombatLockdown() then msg("v boji to hra nedovoli - zkus to po boji.") return end
        MedicDB.scale = s
        anchor:SetScale(s)
        msg("meritko " .. s .. ".")
    elseif cmd == "solo" then
        MedicDB.showSolo = not MedicDB.showSolo
        M.ApplyBindings()
        msg("bez skupiny: " .. (MedicDB.showSolo and "zobrazovat" or "skryt"))
    elseif cmd == "buffy" then
        MedicDB.buffs = not MedicDB.buffs
        updateAll()
        msg("hlidani buffu: " .. (MedicDB.buffs and "zapnuto" or "vypnuto"))
    elseif cmd == "reset" then
        MedicDB = CopyTable(DEFAULTS)
        anchor:ClearAllPoints()
        anchor:SetPoint(MedicDB.point[1], UIParent, MedicDB.point[1], MedicDB.point[2], MedicDB.point[3])
        anchor:SetScale(1)
        anchor:SetWidth(MedicDB.width)
        updateLock()
        M.ApplyBindings()
        msg("vse vraceno na vychozi.")
    else
        msg("neznamy prikaz - napis /medic")
    end
end

SLASH_MEDIC1 = "/medic"
SlashCmdList.MEDIC = slash

-------------------------------------------------------------------------------
-- Události
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function reg(e) pcall(ev.RegisterEvent, ev, e) end   -- některé události nemusí ve Forever existovat
reg("ADDON_LOADED")
reg("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MedicDB = MedicDB or {}
        for k, v in pairs(DEFAULTS) do
            if MedicDB[k] == nil then MedicDB[k] = type(v) == "table" and CopyTable(v) or v end
        end
        -- 0.1.0 ukládala kouzla společně pro všechna povolání -> patří povolání, které je nastavilo
        if MedicDB.binds then
            if next(MedicDB.binds) and not MedicDB.classBinds[playerClass] then MedicDB.classBinds[playerClass] = MedicDB.binds end
            MedicDB.binds = nil
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        createFrames()
        for _, e in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
                            "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
                            "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
                            "SPELLS_CHANGED", "UNIT_FLAGS", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
                            "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                            "UNIT_ABSORB_AMOUNT_CHANGED", "INCOMING_RESURRECT_CHANGED", "UNIT_TARGET" }) do
            reg(e)
        end
        C_Timer.After(1, updateAll)
        msg("nacteno - napis /medic pro prikazy.")
        return
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "PLAYER_REGEN_ENABLED" and pendingApply then M.ApplyBindings() end
        if event == "PLAYER_REGEN_ENABLED" then M.ApplySort(); M.ApplyGrid(); M.WrapPending() end
        updateAll()   -- buff „jen mimo boj“
        return
    end
    if event == "SPELLS_CHANGED" then
        -- nové kouzlo (nová úroveň) -> výchozí přiřazení může použít lepší kouzlo
        M.ApplyBindings()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then updateAll() return end
    if event == "UNIT_TARGET" then
        if arg1 == "target" then updateAll() end   -- můj cíl přepnul na jiného hráče
        return
    end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        for _, btn in ipairs(buttons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() and (u == arg1 or UnitIsUnit(u, arg1)) then M.UpdatePower(btn, u) end
        end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.2, updateAll)
        return
    end
    if arg1 then updateUnit(arg1) end
end)

-- Dosah a aggro se mění bez spolehlivých událostí -> kontrola 4× za vteřinu
C_Timer.NewTicker(0.25, function()
    for _, btn in ipairs(buttons) do
        if btn:IsVisible() then
            local unit = btn:GetAttribute("unit")
            if unit and UnitExists(unit) then updateRange(btn, unit) end
            for _, f in ipairs(btn.hotIcons) do if f:IsShown() then hotTime(f) end end
        end
    end
end)
