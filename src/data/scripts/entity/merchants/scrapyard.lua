-- ScrapyardPlus by DNightmare and Shrooblord (C) 2017-2023
--#region setup
include ("serialize")
local modConfig = include('data/config/scrapyardplus')


-- constants
local MODULE = 'ScrapyardPlus' -- our module name
local FS = '::' -- field separator
local typeAlliance = 'ALLIANCE'
local typeSolo = 'SOLO'

-- server
local legalActions
local newsBroadcastCounter
local highTrafficSystem
local highTrafficTimer
local disasterTimer

-- client
local uiGroups = {}

-- solo licence
local currentSoloLicenseDurationLabel
local maxSoloLicenseDurationLabel
local soloLicenseDuration = 0
-- alliance licence
local currentAllianceLicenseDurationLabel
local maxAllianceLicenseDurationLabel
local allianceLicenseDuration = 0

-- solo lifetime
local soloLifetimeStatusBar
local currentSoloLevel = 0
local soloLevelStatusBar
local currentSoloExp = 0

-- alliance lifetime
local allianceLifetimeStatusBar
local currentAllianceLevel = 0
local allianceLevelStatusBar
local currentAllianceExp = 0
--#endregion

-- modded vanilla functions
function Scrapyard.onShowWindow()

    local ship = Player().craft
    if not ship then return end

    -- get the plan of the player's ship
    local plan = ship:getFullPlanCopy()
    planDisplayer.plan = plan

    if ship.isDrone then
        sellButton.active = false
        sellWarningLabel:hide()
    else
        sellButton.active = true
        sellWarningLabel:show()
    end

    uiMoneyValue = Scrapyard.getShipValue(plan)

    Scrapyard.getCurrentLevelsAndExperience()
    Scrapyard.getLicenseDuration()

    -- turrets
    inventory:fill(ship.factionIndex, InventoryItemType.Turret)

    visible = true
end
function Scrapyard.restore(data)
    -- clear earlier data
    licenses = data.licenses
    illegalActions = data.illegalActions
    legalActions = data.legalActions
    highTrafficSystem = data.highTrafficSystem
    Scrapyard.debug("Restoring data: " .. serialize(data))
end
function Scrapyard.secure()
    -- save licenses
    local data = {}
    data.licenses = licenses
    data.illegalActions = illegalActions
    data.legalActions = legalActions
    data.highTrafficSystem = highTrafficSystem
    Scrapyard.debug("Securing data: " .. serialize(data))
    return data
end
function Scrapyard.initialize()
    if onServer() then
        Scrapyard.debug("Initializing data on server")
        legalActions = {}
        newsBroadcastCounter = 0
        highTrafficSystem = nil
        highTrafficTimer = 0
        disasterTimer = 0

        Sector():registerCallback("onHullHit", "onHullHit")
        local station = Entity()
        if station.title == "" then
            station.title = "Scrapyard"%_t
        end

        -- check for lifetime reached
        local level, experience = Scrapyard.loadExperience(Faction().index)
        local lifetimeReached = (level[Faction().index] >= modConfig.lifetimeLevelRequired)
        Scrapyard.debug("Level: " .. level[Faction().index] .. "/" .. modConfig.lifetimeLevelRequired .. "; Experience til next level: " .. experience[Faction().index] .. " | Lifetime licence acquired: " .. tostring(lifetimeReached))
    end

    if onClient() then
        Scrapyard.getCurrentLevelsAndExperience()
        Scrapyard.getLicenseDuration()
        if EntityIcon().icon == "" then
            EntityIcon().icon = "data/textures/icons/pixel/scrapyard_fat.png"
            InteractionText().text = Dialog.generateStationInteractionText(Entity(), random())
        end
        invokeServerFunction("checkLifetime", Player().index)
    end
end
function Scrapyard.initUI()

    local res = getResolution()
    local size = vec2(700, 650)

    local menu = ScriptUI()
    local mainWindow = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    menu:registerWindow(mainWindow, "Scrapyard" % _t)
    mainWindow.caption = "Scrapyard" % _t
    mainWindow.showCloseButton = 1
    mainWindow.moveable = 1

    -- create a tabbed window inside the main window
    tabbedWindow = mainWindow:createTabbedWindow(Rect(vec2(10, 10), size - 10))

    -- create a "Sell" tab inside the tabbed window
    local sellTab = tabbedWindow:createTab("Sell Ship" % _t, "data/textures/icons/sell-ship.png", "Sell your ship to the scrapyard" % _t)
    size = sellTab.size

    planDisplayer = sellTab:createPlanDisplayer(Rect(0, 0, size.x - 20, size.y - 60))
    planDisplayer.showStats = 0

    sellButton = sellTab:createButton(Rect(0, size.y - 40, 150, size.y), "Sell Ship" % _t, "onSellButtonPressed")
    sellWarningLabel = sellTab:createLabel(vec2(200, size.y - 30), "Warning! You will not get refunds for crews or turrets!" % _t, 15)
    sellWarningLabel.color = ColorRGB(1, 1, 0)

    -- create a tab for dismantling turrets
    local turretTab = tabbedWindow:createTab("Turret Dismantling /*UI Tab title*/"%_t, "data/textures/icons/recycle-turret.png", "Dismantle turrets into goods"%_t)

    local vsplit = UIHorizontalSplitter(Rect(turretTab.size), 10, 0, 0.17)
    inventory = turretTab:createInventorySelection(vsplit.bottom, 10)

    inventory.onSelectedFunction = "onTurretSelected"
    inventory.onDeselectedFunction = "onTurretDeselected"

    local lister = UIVerticalLister(vsplit.top, 10, 0)
    scrapButton = turretTab:createButton(Rect(), "Dismantle"%_t, "onDismantleTurretPressed")
    lister:placeElementTop(scrapButton)
    scrapButton.active = false
    scrapButton.width = 300

    turretTab:createFrame(lister.rect)

    lister:setMargin(10, 10, 10, 10)

    local hlister = UIHorizontalLister(lister.rect, 10, 10)

    for i = 1, 10 do
        local rect = hlister:nextRect(30)
        rect.height = rect.width

        local pic = turretTab:createPicture(rect, "data/textures/icons/rocket.png")
        pic:hide()
        pic.isIcon = true

        table.insert(goodsLabels, {icon = pic})

    end

    Scrapyard.createSoloTab()

    if Player().allianceIndex then
        Scrapyard.createAllianceTab()
    end
end
function Scrapyard.updatePrice(slider)
    for i, group in pairs(uiGroups) do
        if group.durationSlider.index == slider.index then
            local buyer = Player()
            if group.type == typeAlliance then
                buyer = Alliance()
            end

            local base, reputation, bulk, levelDiscount, total = Scrapyard.getLicensePrice(buyer, slider.value, group.type)
            group.basePricelabel.caption = "$${money}" % _t % { money = createMonetaryString(base) }
            group.reputationDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(reputation) }
            group.bulkDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(bulk) }
            group.levelDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(levelDiscount) }
            group.totalPricelabel.caption = "$${money}" % _t % { money = createMonetaryString(total) }

            group.licenseDurationlabel.caption = "${time}" % _t % { time = createReadableTimeString(group.durationSlider.value * 60) }
        end
    end
end
function Scrapyard.updateClient(timeStep)
    local soloLifetime = (currentSoloLevel >= modConfig.lifetimeLevelRequired)
    local allianceLifetime
    local hasAlliance = false
    if Player().allianceIndex then
        hasAlliance = true
        allianceLifetime = (currentAllianceLevel >= modConfig.lifetimeLevelRequired)
    end

    if not soloLifetime then
        soloLicenseDuration = soloLicenseDuration - timeStep
    end
    if hasAlliance and not allianceLifetime then
        allianceLicenseDuration = allianceLicenseDuration - timeStep
    end

    if visible then
        if soloLifetime then
            currentSoloLicenseDurationLabel.caption = "Never (lifetime licence)"%_t
        else
            if soloLicenseDuration > 0 then
                currentSoloLicenseDurationLabel.caption = "${time}" % { time = createReadableTimeString(soloLicenseDuration) }
            else
                currentSoloLicenseDurationLabel.caption = "No licence found."%_t
            end
        end

        if hasAlliance then
            if allianceLifetime then
                currentAllianceLicenseDurationLabel.caption = "Never (lifetime licence)"%_t
            else
                if allianceLicenseDuration > 0 then
                    currentAllianceLicenseDurationLabel.caption = "${time}" % { time = createReadableTimeString(allianceLicenseDuration) }
                else
                    currentAllianceLicenseDurationLabel.caption = "No licence found."%_t
                end
            end
        end

        Scrapyard.getCurrentLevelsAndExperience()
        -- TODO: refactor these into one function since it's not DRY
        if soloLevelStatusBar then -- solo leveling towards next lifetime (exp til next level)
            local currentReputation = Player():getRelations(Entity().factionIndex)

            local description
            local color

            -- these could be a ternary operator
            if soloLifetime or currentReputation >= modConfig.lifetimeRepRequired  then
                description = createMonetaryString(currentSoloExp) .. '/' .. createMonetaryString(modConfig.levelExpRequired)
                color = ColorRGB(0.25, 0.25, 1)
            else
                description = createMonetaryString(currentSoloExp) .. '/' .. createMonetaryString(modConfig.levelExpRequired) .. ' [Reputation too low]'
                color = ColorRGB(0.25, 0.25, 0.25)
            end
            soloLevelStatusBar:setValue(currentSoloExp, description, color)
        end

        if soloLifetimeStatusBar then -- solo leveling towards lifetime (levels til lifetime unlock)
            local currentReputation = Player():getRelations(Entity().factionIndex)

            local description
            local color

            -- these could be a ternary operator
            if soloLifetime or currentReputation >= modConfig.lifetimeRepRequired then
                description = createMonetaryString(currentSoloLevel) .. '/' .. createMonetaryString(modConfig.lifetimeLevelRequired)
                color = ColorRGB(0.25, 1, 0.25)
            else
                description = createMonetaryString(currentSoloLevel) .. '/' .. createMonetaryString(modConfig.lifetimeLevelRequired) .. ' [Reputation too low]'
                color = ColorRGB(0.25, 0.25, 0.25)
            end
            soloLifetimeStatusBar:setValue(currentSoloLevel, description, color)
        end


        if allianceLevelStatusBar then -- alliance leveling towards lifetime (exp til next level)
            local currentReputation = Alliance():getRelations(Entity().factionIndex)

            local description
            local color

            -- these could be a ternary operator
            if allianceLifetime or currentReputation >= modConfig.lifetimeRepRequired then
                description = createMonetaryString(currentAllianceExp) .. '/' .. createMonetaryString(modConfig.levelExpRequired)
                color = ColorRGB(0.25, 0.25, 1)
            else
                description = createMonetaryString(currentAllianceExp) .. '/' .. createMonetaryString(modConfig.levelExpRequired) .. ' [Reputation too low]'
                color = ColorRGB(0.25, 0.25, 0.25)
            end
            allianceLevelStatusBar:setValue(currentAllianceExp, description, color)
        end

        if allianceLifetimeStatusBar then -- alliance leveling towards lifetime (levels til lifetime unlock)
            local currentReputation = Alliance():getRelations(Entity().factionIndex)

            local description
            local color

            -- these could be a ternary operator
            if allianceLifetime or currentReputation >= modConfig.lifetimeRepRequired then
                description = createMonetaryString(currentAllianceLevel) .. '/' .. createMonetaryString(modConfig.lifetimeLevelRequired)
                color = ColorRGB(0.25, 1, 0.25)
            else
                description = createMonetaryString(currentAllianceLevel) .. '/' .. createMonetaryString(modConfig.lifetimeLevelRequired) .. ' [Reputation too low]'
                color = ColorRGB(0.25, 0.25, 0.25)
            end
            allianceLifetimeStatusBar:setValue(currentAllianceLevel, description, color)
        end
    end
end

function Scrapyard.setLicenseDuration(soloDuration, allianceDuration)
    soloLicenseDuration = soloDuration or 0
    allianceLicenseDuration = allianceDuration or 0
end

function Scrapyard.getLicensePrice(orderingFaction, minutes, type)
    local currentLevel = 0
    local basePrice = round(minutes * modConfig.pricePerMinute * Balancing_GetSectorRichnessFactor(Sector():getCoordinates()))
    if type == typeAlliance then
        basePrice = round(modConfig.alliancePriceFactor * basePrice)
        currentLevel = currentAllianceLevel
    else
        currentLevel = currentSoloLevel
    end

    local currentReputation = orderingFaction:getRelations(Faction().index)
    local reputationDiscountFactor = math.floor(currentReputation / 10000 + 1) * 0.01
    local levelDiscount = round(basePrice * (currentLevel / modConfig.lifetimeLevelRequired) ^ modConfig.discountPerLevelPower * 0.25)

    if type == typeAlliance then
        reputationDiscountFactor = reputationDiscountFactor * 0.85 -- alliance reputation is easier to obtain so less discount
        levelDiscount = levelDiscount * 0.65 -- alliance level is easier to obtain so less discount
    end
    local reputationDiscount = round(basePrice * reputationDiscountFactor);

    local bulkDiscountFactor = 0
    if minutes > 10 then bulkDiscountFactor = 0.01 end
    if minutes > 45 then bulkDiscountFactor = 0.02 end
    if minutes > 90 then bulkDiscountFactor = 0.06 end
    if minutes > 120 then bulkDiscountFactor = 0.09 end
    local bulkDiscount = round(basePrice * bulkDiscountFactor)

    local totalPrice = round(basePrice - reputationDiscount - bulkDiscount - levelDiscount)

    return basePrice, reputationDiscount, bulkDiscount, levelDiscount, totalPrice
end

function Scrapyard.buyLicense(duration, type)
    local buyer = Player(callingPlayer)
    local player = Player(callingPlayer)
    local ship

    if type == typeAlliance and player.allianceIndex then
        buyer = Alliance(player.allianceIndex)
    end

    if not buyer then return end
    local station = Entity()

    -- check if this buyer already has a lifetime licence
    if modConfig.allowLifetime then
        local level, experience = Scrapyard.loadExperience(buyer.index)
        local lifetimeReached
        local facId = Faction().index

        if facId and level[facId] then
            print("level: " .. level[facId])
            lifetimeReached = (level[facId] >= modConfig.lifetimeLevelRequired)
            print ("lifetimeReached: " .. tostring(lifetimeReached))
        end

        if lifetimeReached then
            Scrapyard.notifyFaction(buyer.index, 0, string.format("Your lifetime licence with us allows you to salvage here for free!"), station.title)
            return
        end
    end

    local maxDuration = Scrapyard.getMaxLicenseDuration(player)
    local currentDuration = licenses[buyer.index] or 0

    -- check if we would go beyond maximum for current reputation level
    if ((currentDuration + duration) > maxDuration) then
        Scrapyard.notifyFaction(buyer.index, 0, string.format("Transaction would exceed maximum duration. Adjusting your order."), station.title)
        duration = round(maxDuration - currentDuration)
        -- minimum transaction = 5 minutes
        if (duration < 300) then duration = 300 end
    end

    local base, reputation, bulk, levelDiscount, total = Scrapyard.getLicensePrice(buyer, duration / 60, type) -- minutes!

    local canPay, msg, args = buyer:canPay(total)
    if not canPay then
        Scrapyard.notifyFaction(buyer.index, 1, string.format(msg, unpack(args)), station.title)
        return
    end

    buyer:pay(total)

    -- sanity check
    if not licenses[buyer.index] then licenses[buyer.index] = 0 end

    -- register player's licence
    if (licenses[buyer.index] + duration > maxDuration) then
        -- cap at maximum duration
        licenses[buyer.index] = maxDuration
    else
        licenses[buyer.index] = licenses[buyer.index] + duration
    end

    -- send a message as response
    local x,y = Sector():getCoordinates()
    local minutes = round(duration / 60)

    Scrapyard.notifyFaction(buyer.index, 0, string.format("\\s(%i:%i) You bought a %i minutes salvaging licence extension.", x, y, minutes), station.title)
    Scrapyard.notifyFaction(player.index, 0, string.format("%s cannot be held reliable for any damage to ships or deaths caused by salvaging.", Faction().name), station.title)

    Scrapyard.sendLicenseDuration()
end

function Scrapyard.sendLicenseDuration()

    local player = Player(callingPlayer)
    local alliance
    if player.allianceIndex then
        alliance = Alliance(player.allianceIndex)
    end

    local soloDuration = 0
    if player then
        soloDuration = licenses[player.index]
    end

    local allianceDuration = 0
    if alliance then
        allianceDuration = licenses[alliance.index]
    end

    invokeClientFunction(player, "setLicenseDuration", soloDuration, allianceDuration)
end

function Scrapyard.onHullHit(objectIndex, block, shootingCraftIndex, damage, position)
    local object = Entity(objectIndex)
    if object and object.isWreckage then
        local shooter = Entity(shootingCraftIndex)
        if shooter then
            local faction = Faction(shooter.factionIndex)
            if faction and not faction.isAIFaction then
                local pilot
                --print("no AI pilot shooter")
                if faction.isAlliance then
                    for _, playerIndex in pairs({shooter:getPilotIndices()}) do
                        local player = Player(playerIndex)
                        if player then
                            pilot = player
                            break -- we only need the main pilot of this ship
                        end
                    end
                elseif faction.isPlayer then
                    pilot = Player(faction.index)
                end

                if pilot and
                        licenses[faction.index] == nil and  -- check alliance licence
                        licenses[pilot.index] == nil        -- check private licence
                then
                    Scrapyard.unallowedDamaging(shooter, faction, damage)
                else
                    -- grant experience
                    --print("grant XP")
                    Scrapyard.allowedDamaging(faction)
                end
            end
        end
    end
end

function Scrapyard.updateServer(timeStep)

    local station = Entity();

    if highTrafficSystem == nil then
        Scrapyard.debug("Checking if isHighTraffic-System")
        local isHighTraffic = math.random()
        if isHighTraffic <= modConfig.highTrafficChance then
            Scrapyard.debug(isHighTraffic .. " <= " .. modConfig.highTrafficChance .. " -> HighTrafficSystem found!")
            station.title = "High Traffic Scrapyard"%_t
            highTrafficSystem = true
        else
            Scrapyard.debug(isHighTraffic .. " > " .. modConfig.highTrafficChance .. " -> Normal System.")
            highTrafficSystem = false
        end
    end

    -- local advertisement
    newsBroadcastCounter = newsBroadcastCounter + timeStep
    if newsBroadcastCounter > modConfig.advertisementTimer then
        Sector():broadcastChatMessage(station.title, 0, "Get a salvaging licence now and try your luck with the wreckages!"%_t)
        newsBroadcastCounter = 0
    end

    -- we need more minerals
    if highTrafficSystem and modConfig.enableRegen then
        highTrafficTimer = highTrafficTimer + timeStep
        if highTrafficTimer >= modConfig.regenSpawntime * 60 then
            Scrapyard.debug("Time is up, creating new event for high-traffic system")
            -- spawn new ship
            if station then
                station:addScript('data/scripts/events/scrapyardplus', 'high-traffic')
            end
            highTrafficTimer = 0
        end
    end

    -- let's wreak some havoc
    if modConfig.enableDisasters then 
        disasterTimer = disasterTimer + timeStep
        if disasterTimer >= modConfig.disasterSpawnTime * 60 then
            Scrapyard.debug("Time is up, checking for a possible disaster")
            local areWeInTrouble = math.random()
            -- maybe?!
            if station and areWeInTrouble <= modConfig.disasterChance then
                station:addScript('data/scripts/events/scrapyardplus', 'disaster')
            end
            disasterTimer = 0
        end
    end

    if not illegalActions then illegalActions = {} end
    for factionIndex, actions in pairs(illegalActions) do

        actions = actions - 1

        if actions <= 0 then
            illegalActions[factionIndex] = nil
        else
            illegalActions[factionIndex] = actions
        end
    end

    if legalActions == nil then
        legalActions = {}
    end

    if not licenses then licenses = {} end
    for factionIndex, time in pairs(licenses) do
        local faction = Faction(factionIndex)
        if not faction then return end

        -- check for lifetime reached
        local level, experience = Scrapyard.loadExperience(factionIndex)
        local lifetimeReached
        if level[factionIndex] then
            lifetimeReached = (level[factionIndex] >= modConfig.lifetimeLevelRequired)
        end

        if lifetimeReached then
            if time < 3600 then -- lock time at 1 hr as 'lifetime'
                time = 3600
            end
        else
            time = time - timeStep
        end

        local here = false
        local licenseType

        if faction.isAlliance then
            faction = Alliance(factionIndex)
            licenseType = 'alliance'
        elseif faction.isPlayer then
            faction = Player(factionIndex)
            licenseType = 'personal'

            local px, py = faction:getSectorCoordinates()
            local sx, sy = Sector():getCoordinates()

            here = (px == sx and py == sy)
        end

        local doubleSend = false
        local msg

        -- warn player / alliance if time is running out
        if time + 1 > modConfig.expirationTimeFinal and time <= modConfig.expirationTimeFinal then
            if here then
                msg = "Your %s salvaging licence will run out in %s."%_t
            else
                msg = "Your %s salvaging licence in %s will run out in %s."%_t
            end
            doubleSend = true
        end

        if time + 1 > modConfig.expirationTimeCritical and time <= modConfig.expirationTimeCritical then
            if here then
                msg = "Your %s salvaging licence will run out in %s. Renew it NOW and save yourself some trouble!"%_t
            else
                msg = "Your %s salvaging licence in %s will run out in %s. Renew it NOW and save yourself some trouble!"%_t
            end
        end

        if time + 1 > modConfig.expirationTimeWarning and time <= modConfig.expirationTimeWarning then
            if here then
                msg = "Your %s salvaging licence will run out in %s. Renew it immediately and save yourself some trouble!"%_t
            else
                msg = "Your %s salvaging licence in %s will run out in %s. Renew it immediately and save yourself some trouble!"%_t
            end
        end

        if time + 1 > modConfig.expirationTimeNotice and time <= modConfig.expirationTimeNotice then
            if here then
                msg = "Your %s salvaging licence will run out in %s. Don't forget to renew it in time!"%_t
            else
                msg = "Your %s salvaging licence in %s will run out in %s. Don't forget to renew it in time!"%_t
            end
        end

        if time < 0 then
            licenses[factionIndex] = nil

            if here then
                msg = "Your %s salvaging licence expired. You may no longer salvage in this area."%_t
            else
                msg = "Your %s salvaging licence in %s expired. You may no longer salvage in this area."%_t
            end
        else
            licenses[factionIndex] = time
        end

        if msg then
            local coordinates
            local remaining
            local x, y = Sector():getCoordinates()
            coordinates = "${x}:${y}" % {x = x, y = y }
            remaining = round(time)

            if here then
                faction:sendChatMessage(station.title, 0, msg, licenseType, createReadableTimeString(remaining))
                if doubleSend then
                    faction:sendChatMessage(station.title, 2, msg, licenseType, createReadableTimeString(remaining))
                end
            else
                faction:sendChatMessage(station.title, 0, msg, licenseType, coordinates, createReadableTimeString(remaining))
                if doubleSend then
                    faction:sendChatMessage(station.title, 2, msg, licenseType, coordinates, createReadableTimeString(remaining))
                end
            end

        end
    end

end

-- ScrapyardPlus new functions
--- createSoloTab
-- Create all relevant UIElements for the solo-licence tab
function Scrapyard.createSoloTab()
    -- create a second tab
    local licenseTab = tabbedWindow:createTab("Private /*UI Tab title*/" % _t, "data/textures/icons/scrapyardplus-license-solo.png", "Buy a personal salvaging licence" % _t)
    local size = licenseTab.size -- not really required, all tabs have the same size

    local fontSize = 18
    local textField = licenseTab:createTextField(Rect(0, 0, size.x, 50), "You can buy a temporary salvaging licence here. This licence makes it legal to damage or mine wreckages in this sector." % _t)
    textField.padding = 7

    -- Duration
    licenseTab:createLabel(vec2(15, 65), "Duration" % _t, fontSize)
    local durationSlider = licenseTab:createSlider(Rect(125, 65, size.x - 15, 90), 5, 180, 35, "", "updatePrice");
    local licenseDurationlabel = licenseTab:createLabel(vec2(125, 65), "" % _t, fontSize)

    -- Price
    licenseTab:createLabel(vec2(15, 115), "Baseprice", fontSize)
    local basePricelabel = licenseTab:createLabel(vec2(size.x - 260, 115), "", fontSize)

    licenseTab:createLabel(vec2(15, 150), "Reputation Discount", fontSize)
    local reputationDiscountlabel = licenseTab:createLabel(vec2(size.x - 260, 150), "", fontSize)

    licenseTab:createLabel(vec2(15, 185), "Bulk Discount", fontSize)
    local bulkDiscountlabel = licenseTab:createLabel(vec2(size.x - 260, 185), "", fontSize)

    licenseTab:createLabel(vec2(15, 220), "Level Discount", fontSize)
    local levelDiscountlabel = licenseTab:createLabel(vec2(size.x - 260, 220), "", fontSize)

    licenseTab:createLine(vec2(0, 260), vec2(size.x, 260))

    licenseTab:createLabel(vec2(15, 265), "Total", fontSize)
    local totalPricelabel = licenseTab:createLabel(vec2(size.x - 260, 265), "", fontSize)

    -- Buy Now!
    local buyButton = licenseTab:createButton(Rect(size.x - 210, 295, size.x - 10, 355), "Buy licence" % _t, "onBuyLicenseButtonPressed")

    -- lifetime licence (can be disabled in options)
    if modConfig.allowLifetime then
        licenseTab:createLabel(vec2(15, size.y - 130), "Progress towards lifetime licence:", fontSize)
        soloLevelStatusBar = licenseTab:createStatisticsBar(Rect(15, size.y - 100, size.x - 40, size.y - 85), ColorRGB(1, 1, 1))
        licenseTab:createLabel(vec2(size.x - 35, size.y - 105), "XP", fontSize)
        soloLifetimeStatusBar = licenseTab:createStatisticsBar(Rect(15, size.y - 80, size.x - 40, size.y - 65), ColorRGB(1, 1, 1))
        licenseTab:createLabel(vec2(size.x - 35, size.y - 85), "Lvl", fontSize)
    end

    -- licence Status
    licenseTab:createLine(vec2(0, size.y - 55), vec2(size.x, size.y - 55))
    licenseTab:createLabel(vec2(15, size.y - 45), "Current licence expires in:", fontSize)
    currentSoloLicenseDurationLabel = licenseTab:createLabel(vec2(size.x - 360, size.y - 45), "", fontSize)
    licenseTab:createLabel(vec2(15, size.y - 20), "Maximum allowed duration:", fontSize)
    maxSoloLicenseDurationLabel = licenseTab:createLabel(vec2(size.x - 360, size.y - 20), "", fontSize)

    -- the magic of by-reference to the rescue :-)
    Scrapyard.initSoloTab(
        durationSlider,
        licenseDurationlabel,
        basePricelabel,
        reputationDiscountlabel,
        bulkDiscountlabel,
        levelDiscountlabel,
        totalPricelabel,
        soloLevelStatusBar,
        soloLifetimeStatusBar,
        size
    )

    -- Save UIGroup
    table.insert(uiGroups, {
        type = typeSolo,
        durationSlider = durationSlider,
        licenseDurationlabel = licenseDurationlabel,
        basePricelabel = basePricelabel,
        reputationDiscountlabel = reputationDiscountlabel,
        bulkDiscountlabel = bulkDiscountlabel,
        levelDiscountlabel = levelDiscountlabel,
        totalPricelabel = totalPricelabel,
        levelStatusBar = soloLevelStatusBar,
        lifetimeStatusBar = soloLifetimeStatusBar,
        buyButton = buyButton
    })
end

--- initSoloTab
-- Initialize the solo-licence tab with default values
function Scrapyard.initSoloTab(durationSlider, licenseDurationlabel, basePricelabel, reputationDiscountlabel, bulkDiscountlabel, levelDiscountlabel, totalPricelabel, levelStatusBar, lifetimeStatusBar, size)
    -- Init values & properties
    durationSlider.value = 5
    durationSlider.showValue = false

    licenseDurationlabel.caption = "${time}" % _t % { time = createReadableTimeString(durationSlider.value * 60) }
    licenseDurationlabel.width = size.x - 140
    licenseDurationlabel.centered = true

    local base, reputation, bulk, levelDiscount, total = Scrapyard.getLicensePrice(Player(), durationSlider.value)

    basePricelabel.setTopRightAligned(basePricelabel)
    basePricelabel.width = 250
    basePricelabel.caption = "$${money}" % _t % { money = createMonetaryString(base) }

    reputationDiscountlabel.setTopRightAligned(reputationDiscountlabel)
    reputationDiscountlabel.width = 250
    reputationDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(reputation) }

    bulkDiscountlabel.setTopRightAligned(bulkDiscountlabel)
    bulkDiscountlabel.width = 250
    bulkDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(bulk) }

    levelDiscountlabel.setTopRightAligned(levelDiscountlabel)
    levelDiscountlabel.width = 250
    levelDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(levelDiscount) }

    totalPricelabel.setTopRightAligned(totalPricelabel)
    totalPricelabel.width = 250
    totalPricelabel.caption = "$${money}" % _t % { money = createMonetaryString(total) }

    currentSoloLicenseDurationLabel.setTopRightAligned(currentSoloLicenseDurationLabel)
    currentSoloLicenseDurationLabel.width = 350

    maxSoloLicenseDurationLabel.caption = createReadableTimeString(Scrapyard.getMaxLicenseDuration(Player()))
    maxSoloLicenseDurationLabel.setTopRightAligned(maxSoloLicenseDurationLabel)
    maxSoloLicenseDurationLabel.width = 350

    if levelStatusBar then
        levelStatusBar:setRange(0, modConfig.levelExpRequired)
    end
    if lifetimeStatusBar then
        lifetimeStatusBar:setRange(0, modConfig.lifetimeLevelRequired)
    end
end

--- createAllianceTab
-- Create all relevant UIElements for the alliance-licence tab
function Scrapyard.createAllianceTab()
    local allianceTab = tabbedWindow:createTab("Alliance /*UI Tab title*/" % _t, "data/textures/icons/scrapyardplus-license-alliance.png", "Buy a salvaging licence for your alliance" % _t)
    local size = allianceTab.size -- not really required, all tabs have the same size

    local fontSize = 18
    local textField = allianceTab:createTextField(Rect(0, 0, size.x, 50), "You can buy a temporary salvaging licence for your whole alliance here. This licence makes it legal to damage or mine wreckages in this sector." % _t)
    textField.padding = 7

    -- Duration
    allianceTab:createLabel(vec2(15, 65), "Duration" % _t, fontSize)
    local durationSlider = allianceTab:createSlider(Rect(125, 65, size.x - 15, 90), 5, 180, 35, "", "updatePrice");
    local licenseDurationlabel = allianceTab:createLabel(vec2(125, 65), "" % _t, fontSize)

    -- Price
    allianceTab:createLabel(vec2(15, 115), "Baseprice", fontSize)
    local basePricelabel = allianceTab:createLabel(vec2(size.x - 260, 115), "", fontSize)

    allianceTab:createLabel(vec2(15, 150), "Reputation Discount", fontSize)
    local reputationDiscountlabel = allianceTab:createLabel(vec2(size.x - 260, 150), "", fontSize)

    allianceTab:createLabel(vec2(15, 185), "Bulk Discount", fontSize)
    local bulkDiscountlabel = allianceTab:createLabel(vec2(size.x - 260, 185), "", fontSize)

    allianceTab:createLabel(vec2(15, 220), "Level Discount", fontSize)
    local levelDiscountlabel = allianceTab:createLabel(vec2(size.x - 260, 220), "", fontSize)

    allianceTab:createLine(vec2(0, 260), vec2(size.x, 260))

    allianceTab:createLabel(vec2(15, 265), "Total", fontSize)
    local totalPricelabel = allianceTab:createLabel(vec2(size.x - 260, 265), "", fontSize)

    -- Buy Now!
    local buyButton = allianceTab:createButton(Rect(size.x - 210, 295, size.x - 10, 355), "Buy licence" % _t, "onBuyLicenseButtonPressed")

    -- lifetime licence (can be disabled in options)
    if modConfig.allowLifetime then
        allianceTab:createLabel(vec2(15, size.y - 130), "Progress towards lifetime licence:", fontSize)
        allianceLevelStatusBar = allianceTab:createStatisticsBar(Rect(15, size.y - 100, size.x - 40, size.y - 85), ColorRGB(1, 1, 1))
        allianceTab:createLabel(vec2(size.x - 35, size.y - 105), "XP", fontSize)
        allianceLifetimeStatusBar = allianceTab:createStatisticsBar(Rect(15, size.y - 80, size.x - 40, size.y - 65), ColorRGB(1, 1, 1))
        allianceTab:createLabel(vec2(size.x - 35, size.y - 85), "Lvl", fontSize)
    end

    -- licence Status
    allianceTab:createLine(vec2(0, size.y - 55), vec2(size.x, size.y - 55))

    allianceTab:createLabel(vec2(15, size.y - 45), "Current licence expires in:", fontSize)
    currentAllianceLicenseDurationLabel = allianceTab:createLabel(vec2(size.x - 360, size.y - 45), "", fontSize)

    allianceTab:createLabel(vec2(15, size.y - 20), "Maximum allowed duration:", fontSize)
    maxAllianceLicenseDurationLabel = allianceTab:createLabel(vec2(size.x - 360, size.y - 20), "", fontSize)

    Scrapyard.initAllianceTab(durationSlider, licenseDurationlabel, basePricelabel, reputationDiscountlabel, bulkDiscountlabel, levelDiscountlabel, totalPricelabel, allianceLifetimeStatusBar, size)

    -- Save UIGroup
    table.insert(uiGroups, {
        type = typeAlliance,
        durationSlider = durationSlider,
        licenseDurationlabel = licenseDurationlabel,
        basePricelabel = basePricelabel,
        reputationDiscountlabel = reputationDiscountlabel,
        bulkDiscountlabel = bulkDiscountlabel,
        levelDiscountlabel = levelDiscountlabel,
        totalPricelabel = totalPricelabel,
        levelStatusBar = allianceLevelStatusBar,
        lifetimeStatusBar = allianceLifetimeStatusBar,
        buyButton = buyButton
    })
end

--- initAllianceTab
-- Initialize the alliance-licence tab with default values
function Scrapyard.initAllianceTab(durationSlider, licenseDurationlabel, basePricelabel, reputationDiscountlabel, bulkDiscountlabel, levelDiscountlabel, totalPricelabel, levelStatusBar, lifetimeStatusBar, size)
    durationSlider.value = 5
    durationSlider.showValue = false

    licenseDurationlabel.caption = "${time}" % _t % { time = createReadableTimeString(durationSlider.value * 60) }
    licenseDurationlabel.width = size.x - 140
    licenseDurationlabel.centered = true

    local base, reputation, bulk, levelDiscount, total = Scrapyard.getLicensePrice(Player(), durationSlider.value, typeAlliance)

    basePricelabel.setTopRightAligned(basePricelabel)
    basePricelabel.width = 250
    basePricelabel.caption = "$${money}" % _t % { money = createMonetaryString(base) }

    reputationDiscountlabel.setTopRightAligned(reputationDiscountlabel)
    reputationDiscountlabel.width = 250
    reputationDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(reputation) }

    bulkDiscountlabel.setTopRightAligned(bulkDiscountlabel)
    bulkDiscountlabel.width = 250
    bulkDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(bulk) }

    levelDiscountlabel.setTopRightAligned(levelDiscountlabel)
    levelDiscountlabel.width = 250
    levelDiscountlabel.caption = "$${money}" % _t % { money = createMonetaryString(levelDiscount) }

    totalPricelabel.setTopRightAligned(totalPricelabel)
    totalPricelabel.width = 250
    totalPricelabel.caption = "$${money}" % _t % { money = createMonetaryString(total) }

    currentAllianceLicenseDurationLabel.setTopRightAligned(currentAllianceLicenseDurationLabel)
    currentAllianceLicenseDurationLabel.width = 350

    maxAllianceLicenseDurationLabel.caption = createReadableTimeString(Scrapyard.getMaxLicenseDuration(Player()))
    maxAllianceLicenseDurationLabel.setTopRightAligned(maxAllianceLicenseDurationLabel)
    maxAllianceLicenseDurationLabel.width = 350

    if levelStatusBar then
        levelStatusBar:setRange(0, modConfig.levelExpRequired)
    end
    if lifetimeStatusBar then
        lifetimeStatusBar:setRange(0, modConfig.lifetimeLevelRequired)
    end
end

--- onBuyLicenseButtonPressed
-- Register a new licence with the correct faction (player/alliance)
function Scrapyard.onBuyLicenseButtonPressed(button)
    for _, group in pairs(uiGroups) do
        -- find which button got pressed
        if group.buyButton.index == button.index then
            local player = Player()
            local alliance = player.allianceIndex
            invokeServerFunction("buyLicense", 60 * group.durationSlider.value, group.type)
        end
    end
end

--- checkLifetime
-- Load a player and see if he already earned a lifetime licence for personal or alliance use
function Scrapyard.checkLifetime(playerIndex)
    local player = Player(playerIndex)
    local soloLevel = Scrapyard.loadExperience(playerIndex)
    local facId = Faction().index
    if not facId then return end

    if player and soloLevel[facId] and soloLevel[facId] >= modConfig.lifetimeLevelRequired then
        licenses[playerIndex] = 3600
    end

    local alliance = player.allianceIndex
    if alliance then
        local allianceLevel = Scrapyard.loadExperience(alliance)
        if allianceLevel[facId] and allianceLevel[facId] >= modConfig.lifetimeLevelRequired then
            licenses[alliance] = 3600
        end
    end
end
callable(Scrapyard, "checkLifetime")

--- getMaxLicenseDuration
-- Based on current reputation return the current maximum duration a player can accumulate
function Scrapyard.getMaxLicenseDuration(player)
    local currentReputation = player:getRelations(Faction().index)
    local reputationBonusFactor = math.floor(currentReputation / 10000)
    -- every 'level' gets us 30 minutes more max on top of our 3hrs base duration up to a total of 8hrs

    return (180 + (reputationBonusFactor * 30)) * 60
end

--- notifyFaction
-- Helper to notify all online players of given faction
function Scrapyard.notifyFaction(factionIndex, channel,  message, sender)

    local faction = Faction(factionIndex)
    if faction.isPlayer then
        Player(factionIndex):sendChatMessage(sender, channel, message);
    else
        local onlinePlayers = {Server():getOnlinePlayers() }
        for _,player in pairs(onlinePlayers) do
            if player.allianceIndex == factionIndex then
                player:sendChatMessage(sender, channel, message);
            end
        end
    end
end

--- calculateNewExperience
-- Based on the current experience return how much a player/alliance will earn;
-- somewhat exponential growth to simulate increasing difficulty as you near the next level,
-- and actual exponential growth per level
function Scrapyard.calculateNewExperience(currentLevel)
    return (modConfig.lifetimeExpBaseline * modConfig.lifetimeExpFactor) ^ ((1 + modConfig.lifeTimeExpLevelPower * currentLevel) * -1)
end

--- getCurrentLevelsAndExperience
-- Trigger the server to send the current experience to the client
function Scrapyard.getCurrentLevelsAndExperience()
    invokeServerFunction('sendCurrentLevelsAndExperience')
end

--- sendCurrentLevelsAndExperience
-- Send the current experience to the client
function Scrapyard.sendCurrentLevelsAndExperience()
    local player = Player(callingPlayer)
    if not player then return end

    local alliance
    if player.allianceIndex then
        alliance = Alliance(player.allianceIndex)
    end

    local playerLevel, playerExperience = Scrapyard.loadExperience(player.index)

    local allianceLevel, allianceExperience
    local facId = Faction().index

    if alliance then
        allianceLevel, allianceExperience = Scrapyard.loadExperience(alliance.index)
    else
        allianceLevel = {}
        allianceLevel[facId] = 0

        allianceExperience = {}
        allianceExperience[facId] = 0
    end

    invokeClientFunction(player, "setCurrentLevelsAndExperience", playerLevel[facId], playerExperience[facId], allianceLevel[facId], allianceExperience[facId])
end
callable(Scrapyard, "sendCurrentLevelsAndExperience")

--- loadExperience
-- Deserialize load and sanity-check current experience and levels from given faction
function Scrapyard.loadExperience(factionIndex)
    local faction = Faction(factionIndex)
    if not faction then return end

    local serializedLevel = faction:getValue(MODULE .. FS .. 'level')
    local serializedExp = faction:getValue(MODULE .. FS .. 'experience')
    local level, experience

    if serializedExp ~= nil then
        experience = loadstring(serializedExp)()
        if type(experience) ~= 'table' then
            experience = {}
        end
    else
        experience = {}
    end

    if serializedLevel ~= nil then
        level = loadstring(serializedLevel)()
        if type(level) ~= 'table' then
            level = {}
        end
    else
        level = {}
    end

    if experience[factionIndex] == nil then
        experience[factionIndex] = 0
    end
    if level[factionIndex] == nil then
        level[factionIndex] = 0
    end

    return level, experience
end

--- setCurrentLevelsAndExperience
-- Store the received experience from the server at the client
function Scrapyard.setCurrentLevelsAndExperience(soloLevel, soloExp, allianceLevel, allianceExp)
    currentSoloExp = soloExp or 0
    currentSoloLevel = soloLevel or 0
    currentAllianceExp = allianceExp or 0
    currentAllianceLevel = allianceLevel or 0
end

--- allowedDamaging
-- Called when a player/alliance is salvaging with a valid licence
function Scrapyard.allowedDamaging(faction)
    if not faction then return end
    local scrapyardFaction = Faction()
    if not scrapyardFaction then return end

    local actions = legalActions[faction.index]
    if actions == nil then
        actions = 0
    end
--print(actions)
    actions = actions + 1
    if actions >= modConfig.levelExpTicks then
        local reputation = faction:getRelations(scrapyardFaction.index)
        if reputation >= modConfig.lifetimeRepRequired then
            local levelTbl, expTbl = Scrapyard.loadExperience(faction.index)
            local currentLevel = levelTbl[scrapyardFaction.index]

            -- wasn't initialised properly
            if not currentLevel then
                levelTbl[scrapyardFaction.index] = 0
                expTbl[scrapyardFaction.index] = 0

                faction:setValue(MODULE .. FS .. 'level', serialize(levelTbl))
                faction:setValue(MODULE .. FS .. 'experience', serialize(expTbl))

                goto continue
            end

            if currentLevel and currentLevel < modConfig.lifetimeLevelRequired then
                local currentExp = expTbl[scrapyardFaction.index]
                local newExp = Scrapyard.calculateNewExperience(currentLevel)
                if faction.isAlliance then
                    newExp =  math.max(math.floor(newExp * modConfig.lifetimeAllianceFactor), 1)
                end
                --print("gained " .. newExp .. "experience")

                -- Level up!
                if currentExp and currentExp + newExp >= modConfig.levelExpRequired then
                    expTbl[scrapyardFaction.index] = 0
                    currentLevel = currentLevel + 1
                    levelTbl[scrapyardFaction.index] = currentLevel
                    if currentLevel >= modConfig.lifetimeLevelRequired then
                        levelTbl[scrapyardFaction.index] = modConfig.lifetimeLevelRequired
        
                        local scrapper
                        if faction.isAlliance then
                            scrapper = Alliance(faction.index)
                        else
                            scrapper = Player(faction.index)
                        end
                        if scrapper then
                            scrapper:sendChatMessage(Entity().title, 0, 'Congratulations! You reached lifetime status with our faction!')
                            scrapper:sendChatMessage(Entity().title, 2, 'Lifetime licence activated!')
                        end
                    end
                else
                    expTbl[scrapyardFaction.index] = currentExp + newExp
                end
                faction:setValue(MODULE .. FS .. 'level', serialize(levelTbl))
                faction:setValue(MODULE .. FS .. 'experience', serialize(expTbl))
            end
        end

        ::continue::
        actions = 0

    end
    legalActions[faction.index] = actions
end

function Scrapyard.debug(message)
    if modConfig.enableDebug == true then
        print(MODULE .. FS .. "DEBUG: " .. message)
    end
end

function Scrapyard.getData(playerIndex)
    local player = Player(playerIndex)
    if not player then return end
    local alliance = player.allianceIndex
    local facId = Faction().index
    data = {
        license = {
            player = licenses[player] or 0,
            alliance = licenses[alliance] or 0,
            lifetime = (level[facId] >= modConfig.lifetimeLevelRequired)
        },
        level = {
            level[facId],
            modConfig.lifetimeLevelRequired
        },
        experience = {
            experience[facId],
            modConfig.levelExpRequired
        }
    }
    return data
end
callable(Scrapyard, "getData")