-- Medic: rámečky skupiny a raidu s léčením na kliknutí myši
--  * rámečky dělá bezpečná hlavička hry (SecureGroupHeaderTemplate) – funguje i v boji
--  * kouzla na tlačítka myši (s Shift/Ctrl/Alt) přes atributy bezpečných tlačítek
--  * debuffy, které umíš odstranit, příchozí léčení, aggro, chybějící buff
-- Texty do chatu jsou bez háčků: písmo chatu neumí č/ř/ů.

local ADDON = ...
local M = {}
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
    binds = {},        -- ruční přiřazení hráče (přebíjí výchozí)
    showSolo = true,
    buffs = true,
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
local function forEachAura(unit, filter, fn)
    for i = 1, 40 do
        local name, icon, dispelName, source
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not a then return end
            name, icon, dispelName, source = a.name, a.icon, a.dispelName, a.sourceUnit
        else
            local n, ic, _, dtype, _, _, src = UnitAura(unit, i, filter)
            if not n then return end
            name, icon, dispelName, source = n, ic, dtype, src
        end
        if fn(name, icon, dispelName, source) then return end
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
    for key, action in pairs(MedicDB.binds) do
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
    local heal = hp:CreateTexture(nil, "ARTWORK")
    heal:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    heal:SetVertexColor(0.3, 1, 0.3, 0.55)
    heal:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT")
    heal:SetPoint("BOTTOMLEFT", hp:GetStatusBarTexture(), "BOTTOMRIGHT")
    heal:Hide()
    btn.heal = heal

    local overlay = CreateFrame("Frame", nil, btn)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(hp:GetFrameLevel() + 2)

    local name = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", 4, -4)
    name:SetPoint("TOPRIGHT", -14, -4)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    btn.nameText = name

    local info = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("BOTTOMRIGHT", -4, 4)
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

    -- debuff, který umíš odstranit: barevný rámeček (barva podle typu – magie, jed, nemoc, kletba)
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints()
    border:SetFrameLevel(overlay:GetFrameLevel() + 1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    border:Hide()
    btn.border = border

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
-- Aktualizace rámečku
-------------------------------------------------------------------------------
local function updateRange(btn, unit)
    local inRange = true
    if not UnitIsUnit(unit, "player") and UnitInRange then
        local r, checked = UnitInRange(unit)
        if checked then inRange = r end
    end
    btn:SetAlpha(inRange and 1 or 0.4)
end

function updateButton(btn)
    if not btn.medic then return end
    local unit = btn:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS[class] or { r = 0.2, g = 0.8, b = 0.2 }
    btn.nameText:SetText(UnitName(unit) or "")
    btn.nameText:SetTextColor(1, 1, 1)

    local hp, maxHp = UnitHealth(unit), UnitHealthMax(unit)
    if maxHp <= 0 then maxHp = 1 end
    btn.hp:SetValue(hp / maxHp)

    local dead = UnitIsDeadOrGhost(unit)
    local offline = not UnitIsConnected(unit)
    if offline then
        btn.hp:SetStatusBarColor(0.3, 0.3, 0.3)
        btn.infoText:SetText("Offline")
        btn.infoText:SetTextColor(0.6, 0.6, 0.6)
    elseif dead then
        btn.hp:SetValue(0)
        btn.infoText:SetText("Mrtvy")
        btn.infoText:SetTextColor(0.8, 0.3, 0.3)
    else
        btn.hp:SetStatusBarColor(c.r, c.g, c.b)
        local deficit = maxHp - hp
        if deficit > 0 then
            btn.infoText:SetText("-" .. (deficit >= 10000 and (math.floor(deficit / 1000) .. "k") or deficit))
            btn.infoText:SetTextColor(1, 0.4, 0.4)
        else
            btn.infoText:SetText("")
        end
    end

    -- příchozí léčení
    local incoming = (not dead and not offline and UnitGetIncomingHeals) and (UnitGetIncomingHeals(unit) or 0) or 0
    if incoming > 0 and hp < maxHp then
        local w = btn.hp:GetWidth() * math.min(incoming, maxHp - hp) / maxHp
        if w >= 1 then btn.heal:SetWidth(w); btn.heal:Show() else btn.heal:Hide() end
    else
        btn.heal:Hide()
    end

    -- aggro
    local threat = UnitThreatSituation and UnitThreatSituation(unit)
    btn.aggro:SetShown(threat and threat >= 2 or false)

    -- debuff, který umím odstranit (filtr RAID = jen odstranitelné mnou)
    local dispelType, dispelIcon
    if not dead then
        forEachAura(unit, "HARMFUL|RAID", function(_, icon, dtype)
            if dtype and dtype ~= "" then dispelType, dispelIcon = dtype, icon return true end
        end)
    end
    if dispelType then
        local dc = (DebuffTypeColor and DebuffTypeColor[dispelType]) or { r = 0.8, g = 0, b = 0.8 }
        btn.border:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1)
        btn.border:Show()
        btn.debuffIcon:SetTexture(dispelIcon)
        btn.debuffIcon:Show()
    else
        btn.border:Hide()
        btn.debuffIcon:Hide()
    end

    -- chybějící buff
    local cfg = MedicDB.buffs and CLASS_BUFFS[playerClass]
    local missing = false
    if cfg and not dead and not offline and knowsSpell(cfg.spell) then
        missing = true
        forEachAura(unit, "HELPFUL", function(name, _, _, source)
            if not name then return end
            if cfg.mine and source ~= "player" then return end
            for _, want in ipairs(cfg.names) do
                if (cfg.prefix and name:sub(1, #want) == want) or name == want then missing = false return true end
            end
        end)
    end
    if missing then
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

local function updateUnit(unit)
    for _, btn in ipairs(buttons) do
        local u = btn:GetAttribute("unit")
        if u and btn:IsVisible() and (u == unit or UnitIsUnit(u, unit)) then updateButton(btn) end
    end
end

-------------------------------------------------------------------------------
-- Přiřazení kouzel (jen mimo boj – hra v boji nedovolí měnit bezpečná tlačítka)
-------------------------------------------------------------------------------
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
    -- přepočítat rozložení hlavičky
    header:SetAttribute("showSolo", MedicDB.showSolo)
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
    label:SetText("Medic - tahni")
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
    header:SetAttribute("groupBy", "GROUP")
    header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    header:SetAttribute("sortMethod", "INDEX")
    header:SetAttribute("point", "TOP")
    header:SetAttribute("yOffset", -2)
    header:SetAttribute("maxColumns", 8)
    header:SetAttribute("unitsPerColumn", 5)
    header:SetAttribute("columnSpacing", 2)
    header:SetAttribute("columnAnchorPoint", "LEFT")
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
        if low == "zadne" or low == "nic" or low == "-" then MedicDB.binds[key] = false
        elseif low == "vychozi" then MedicDB.binds[key] = nil
        elseif low == "target" or low == "oznacit" then MedicDB.binds[key] = "target"
        elseif low == "menu" or low == "nabidka" then MedicDB.binds[key] = "menu"
        else
            MedicDB.binds[key] = action
            if not knowsSpell(action) then msg("pozor: kouzlo '" .. action .. "' zatim neumis nebo je napsane jinak (nazev anglicky, jako ve spellbooku).") end
        end
        M.ApplyBindings()
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
        return
    end
    if event == "PLAYER_LOGIN" then
        createFrames()
        for _, e in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
                            "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
                            "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
                            "SPELLS_CHANGED", "UNIT_FLAGS" }) do
            reg(e)
        end
        C_Timer.After(1, updateAll)
        msg("nacteno - napis /medic pro prikazy.")
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then M.ApplyBindings() end
        return
    end
    if event == "SPELLS_CHANGED" then
        -- nové kouzlo (nová úroveň) -> výchozí přiřazení může použít lepší kouzlo
        M.ApplyBindings()
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
        end
    end
end)
