local config = {}

-- general
config.enableDebug = false -- [Default: false] Enable/Disable detailed log output
config.alliancePriceFactor = 4.5 -- [Default: 4.5] How much alliances have to pay more for a salvaging licence
config.pricePerMinute = 175 -- [Default: 175] Price per one minute of salvaging

-- timers / announcements
config.advertisementTimer = 120 -- [Default: 120] Time (in seconds) when the scrapyard will spam the system with "get a licence now"
config.expirationTimeNotice = 600 -- [Default: 600] Time (in seconds) at which the first reminder will be send to players/alliances about their licence running out
config.expirationTimeWarning = 300 -- [Default: 300] Time (in seconds) at which the second reminder will be send to players/alliances about their licence running out
config.expirationTimeCritical = 120 -- [Default: 120] Time (in seconds) at which the third reminder will be send to players/alliances about their licence running out
config.expirationTimeFinal = 30 -- [Default: 30] Time (in seconds) at which the FINAL reminder will be send to players/alliances about their licence running out

-- discounts / lifetime licence
config.allowLifetime = true -- [Default: true] Enable/Disable the ability to get lifetime salvaging licences
config.lifetimeRepRequired = 10000 -- [Default: 10000] Minimum required reputation before you start to gather experience towards levels / lifetime
config.levelExpTicks = 10 -- [Default: 10] This many ticks are required to gain one experience point towards levels / lifetime
config.levelExpRequired = 100 -- [Default: 100] Amount of experience to unlock levels towards lifetime-licence
config.lifetimeLevelRequired = 100 -- [Default: 100] Amount of levels to unlock levels towards lifetime-licence
config.lifetimeAllianceFactor = 0.5 -- [Default: 0.5] Factor to de-/increase the amount an alliance will get compared to a player
config.lifetimeExpBaseline = 700 -- [Default: 700] Base value of experience per turret per 'xp tick' (see levelExpTicks above) before any other calculations
config.lifetimeExpFactor = 0.75 -- [Default: 0.75] Factor to de-/increase the base experience calculation
config.lifeTimeExpLevelPower = 0.009 -- [Default: 0.009] Power factor to de-/increase the amount of experience required per level based on the current level of the player/alliance
config.discountPerLevelPower = 0.98 -- [Default: 0.98] Power factor to de-/increase the amount of discount per level based on the current level of the player/alliance

-- high traffic system
config.highTrafficChance = 0.3 -- [Default: 0.3] Chance that a discovered system is regenerative
config.enableRegen = true -- [Default: true] Enable/Disable the regeneration of wrecks inside a system
config.regenSpawntime = 15 -- [Default: 15] Time (in minutes) how often new event will start to spawn wrecks

-- events
config.enableDisasters = false -- [Default: true] Enable/Disable events from the (G)lobal (O)rganization of (D)isasters
config.disasterChance = 0.03 -- [Default: 0.03] Chance that something bad will happen
config.disasterSpawnTime = 20 -- [Default: 30] Time (in minutes) how often it's checked if bad things will happen

return config
