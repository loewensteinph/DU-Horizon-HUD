-- Script is laid out variables, functions, control, control (the Hud proper) starts around line 4000
Nav = Navigator.new(system, core, unit)

script = {}  -- wrappable container for all the code. Different than normal DU Lua in that things are not seperated out.

-- Edit LUA Variable user settings.  Must be global to work with databank system as set up due to using _G assignment
yawSpeedFactor = 1 -- export: (Default: 1) For keyboard control
torqueFactor = 2 -- export: (Default: 2) Force factor applied to reach rotationSpeed<br>(higher value may be unstable)<br>Valid values: Superior or equal to 0.01
brakeSpeedFactor = 3 -- export: (Default: 3) When braking, this factor will increase the brake force by brakeSpeedFactor * velocity<br>Valid values: Superior or equal to 0.01
brakeFlatFactor = 1 -- export: (Default: 1) When braking, this factor will increase the brake force by a flat brakeFlatFactor * velocity direction><br>(higher value may be unstable)<br>Valid values: Superior or equal to 0.01
pitchSpeedFactor = 0.8 -- export: (Default: 0.8) For keyboard control
pitchSpeedFactor = 0.8 -- export: (Default: 0.8) For keyboard control
rollSpeedFactor = 1.5 -- export: (Default: 1.5) This factor will increase/decrease the player input along the roll axis<br>(higher value may be unstable)<br>Valid values: Superior or equal to 0.01
statAtmosphericFuelTankHandling = 2 --export Piloting -> Atmospheric Flight Technician -> Atmospheric Fuel-Tank Handling
statSpaceFuelTankHandling = 0 --export Piloting -> Atmospheric Engine Technician -> Space Fuel-Tank Handling
statRocketFuelTankHandling = 0 --export (0-5) Enter the LEVEL OF YOUR PLACED FUEL ROCKET TANKS (from the builders talent "Piloting -> Rocket Scientist -> Rocket Booster Fuel Tank Handling")
statContainerOptimization = 0 --export Stock Control -> Container Optimization
statFuelTankOptimization = 0 --export Mining and Inventory -> Stock Control -> Fuel Tank Optimization

-- VARIABLES TO BE SAVED GO HERE, SAVEABLE are Edit LUA Parameter settable, AUTO are ship status saves that occur over get up and sit down.
local saveableVariables = { "yawSpeedFactor", "torqueFactor", "brakeSpeedFactor",
                        "brakeFlatFactor", "pitchSpeedFactor","rollSpeedFactor","dampingMultiplier","statAtmosphericFuelTankHandling",
                    "statSpaceFuelTankHandling","statRocketFuelTankHandling","statContainerOptimization","statFuelTankOptimization"}
-- Edit LUA Variable user settings.  Must be global to work with databank system as set up due to using _G assignment
-- Auto Variable declarations that store status of ship. Must be global because they get saved/read to Databank due to using _G assignment
local pitchInput = 0
local pitchInput2 = 0
local rollInput = 0
local yawInput = 0
local yawInput2 = 0
local rollInput2 = 0
local brakeInput = 0
local brakeInput2 = 0
local Kinematic = nil
local hSpd = 0
local vSpd = 0
local targetVelocity = 0
local vTargetSpeed = 0
local up_down_switch = 0
local teledown = 0
altDiff = 0
currentAltitude = 0
speed_increment = 0
throttle_increment = 0
throttle_input = 0
throttle_in = 0
initialAlt = core.getAltitude()
targetAltitude = core.getAltitude()
currentAltitude = core.getAltitude()
worldVertical = vec3(core.getWorldVertical()) -- along gravity
constructUp = vec3(core.getConstructWorldOrientationUp())
constructForward = vec3(core.getConstructWorldOrientationForward())
constructRight = vec3(core.getConstructWorldOrientationRight())
constructVelocity = vec3(core.getWorldVelocity())
-- container stuff
typeElements = {}
fuelAtmosphericTanks = {}
fuelSpaceTanks = {}
fuelRocketTanks = {}
-- hud container stuff
fuelTanksDisplay = {}
--statics
weightAtmosphericFuel = 4
weightSpaceFuel = 6
weightRocketFuel = 0.8

-- Testing Purpose
debug = false
apActive = false

-- function localizations for improved performance when used frequently or in loops.
local atmosphere = unit.getAtmosphereDensity
local constructMass = core.getConstructMass

-- AP Stuff
targetPos = vec3()
currentPos = vec3()
lockBrake = false 
brakeDistance = 0
vMaxSpeed = 0
hMaxSpeed = 0
previousYawAmount = 0
previousPitchAmount = 0
pitchAmount = 0
local autopilotStrength = 0.2 -- How strongly autopilot tries to point at a target
local alignmentTolerance = 0.05 -- How closely it must align to a planet before accelerating to it
local minimumRateOfChange = math.cos(30*constants.deg2rad) -- Adjust 30 which is taken from stall angle
APTarget = nil
APisaligned = false
APthrust = 0
APspeedincrement = 0
-- flight automation options
level = true -- Alt 1 - Autolevel only allow yaw
flip = false -- not used yet
autoalt = true -- Alt 2 - Reach set target alt
finalBrakeInput = 0
upAmount = 0

-- todo make freeze configurable
if 1 == 1 then
    system.freeze(1)
    system.lockView(1)
end

-- contaienr info
function setContainerInfo()
    typeElements = {}
    fuelAtmosphericTanks = {}
    fuelSpaceTanks = {}
    fuelRocketTanks = {}
    elementsIdList = core.getElementIdList()
    elementCounter = 0
    fuelAtmosphericCurrent = 0
    fuelAtmosphericTotal = 0
    fuelSpaceCurrent = 0
    fuelSpaceTotal = 0
    fuelRocketCurrent = 0
    fuelRocketTotal = 0

    for i, id in pairs(elementsIdList) do
        elementCounter = elementCounter + 1
        local idType = core.getElementTypeById(id)
        if idType == "Atmospheric Fuel Tank" or idType == "Space Fuel Tank" or idType == "Rocket Fuel Tank" then
            --system.print(id)
            table.insert(typeElements, id)
        --id)
        end
    end
    for i, id in ipairs(typeElements) do
        local idName = core.getElementNameById(id) or ""
        local idType = core.getElementTypeById(id) or ""
        -- local idTypeClean = idType:gsub("[%s%-]+", ""):lower()
        local idPos = core.getElementPositionById(id) or 0
        local idHP = core.getElementHitPointsById(id) or 0
        local idMaxHP = core.getElementMaxHitPointsById(id) or 0
        local idMass = core.getElementMassById(id) or 0
        local baseSize = ""
        local baseVol = 0
        local baseMass = 0
        local cMass = 0
        local cVol = 0
        if idType == "Atmospheric Fuel Tank" then
            if idMaxHP > 10000 then
                baseSize = "L"
                baseMass = 5480
                baseVol = 12800
            elseif idMaxHP > 1300 then
                baseSize = "M"
                baseMass = 988.67
                baseVol = 1600
            elseif idMaxHP > 150 then
                baseSize = "S"
                baseMass = 182.67
                baseVol = 400
            else
                baseSize = "XS"
                baseMass = 35.03
                baseVol = 100
            end
            if statAtmosphericFuelTankHandling > 0 then
                baseVol = 0.2 * statAtmosphericFuelTankHandling * baseVol + baseVol
            end
            cMass = idMass - baseMass
            if cMass <= 10 then
                cMass = 0
            end
            cVol = string.format("%.0f", cMass / weightAtmosphericFuel)
            cPercent = string.format("%.1f", math.floor(100 / baseVol * tonumber(cVol)))
            table.insert(
                fuelAtmosphericTanks,
                {
                    type = 1,
                    id = id,
                    name = idName,
                    maxhp = idMaxHP,
                    pos = idPos,
                    size = baseSize,
                    mass = baseMass,
                    vol = baseVol,
                    cvol = cVol,
                    percent = cPercent
                }
            )
            if idHP > 0 then
                fuelAtmosphericCurrent = fuelAtmosphericCurrent + cVol
            end
            fuelAtmosphericTotal = fuelAtmosphericTotal + baseVol
        elseif idType == "Space Fuel Tank" then
            if idMaxHP > 10000 then
                baseSize = "L"
                baseMass = 5480
                baseVol = 12800
            elseif idMaxHP > 1300 then
                baseSize = "M"
                baseMass = 988.67
                baseVol = 1600
            else
                baseSize = "S"
                baseMass = 182.67
                baseVol = 400
            end
            if statSpaceFuelTankHandling > 0 then
                baseVol = 0.2 * statSpaceFuelTankHandling * baseVol + baseVol
            end
            cMass = idMass - baseMass
            if cMass <= 10 then
                cMass = 0
            end
            cVol = string.format("%.0f", cMass / weightSpaceFuel)
            cPercent = string.format("%.1f", (100 / baseVol * tonumber(cVol)))
            table.insert(
                fuelSpaceTanks,
                {
                    type = 2,
                    id = id,
                    name = idName,
                    maxhp = idMaxHP,
                    pos = idPos,
                    size = baseSize,
                    mass = baseMass,
                    vol = baseVol,
                    cvol = cVol,
                    percent = cPercent
                }
            )
            if idHP > 0 then
                fuelSpaceCurrent = fuelSpaceCurrent + cVol
            end
            fuelSpaceTotal = fuelSpaceTotal + baseVol
        elseif idType == "Rocket Fuel Tank" then
            if idMaxHP > 65000 then
                baseSize = "L"
                baseMass = 25740
                baseVol = 50000
            elseif idMaxHP > 6000 then
                baseSize = "M"
                baseMass = 4720
                baseVol = 6400
            elseif idMaxHP > 700 then
                baseSize = "S"
                baseMass = 886.72
                baseVol = 800
            else
                baseSize = "XS"
                baseMass = 173.42
                baseVol = 400
            end
            if statRocketFuelTankHandling > 0 then
                baseVol = 0.2 * statRocketFuelTankHandling * baseVol + baseVol
            end
            cMass = idMass - baseMass
            if cMass <= 10 then
                cMass = 0
            end
            cVol = string.format("%.0f", cMass / weightRocketFuel)
            cPercent = string.format("%.1f", (100 / baseVol * tonumber(cVol)))
            table.insert(
                fuelRocketTanks,
                {
                    type = 3,
                    id = id,
                    name = idName,
                    maxhp = idMaxHP,
                    pos = idPos,
                    size = baseSize,
                    mass = baseMass,
                    vol = baseVol,
                    cvol = cVol,
                    percent = cPercent
                }
            )
            if idHP > 0 then
                fuelRocketCurrent = fuelRocketCurrent + cVol
            end
            fuelRocketTotal = fuelRocketTotal + baseVol
        end
    end
end           

function setContainerDisplayInfo()
    fuelTanksDisplay = {}

    for _,v in ipairs(fuelAtmosphericTanks) do
        table.insert(fuelTanksDisplay, v)
    end
    for _,v in ipairs(fuelSpaceTanks) do
        table.insert(fuelTanksDisplay, v)
    end
    for _,v in ipairs(fuelRocketTanks) do
        table.insert(fuelTanksDisplay, v)
    end
    table.sort(fuelTanksDisplay, function(a,b) return a.type<b.type or (a.type == b.type and a.id<b.id) end)
end    

function lockBrakeToggle()
    -- Toggle brakes
    lockBrake = not lockBrake
    if lockBrake then
    end
end
-- Planet Info - https://gitlab.com/JayleBreak/dualuniverse/-/tree/master/DUflightfiles/autoconf/custom with minor modifications
function Atlas()
    return {
        [0] = {
            [0] = {
                GM = 0,
                bodyId = 0,
                center = {
                    x = 0,
                    y = 0,
                    z = 0
                },
                name = 'Space',
                planetarySystemId = 0,
                radius = 0,
                atmos = false,
                gravity = 0
            },
            [1] = {
                GM = 6930729684,
                bodyId = 1,
                center = {
                    x = 17465536.000,
                    y = 22665536.000,
                    z = -34464.000
                },
                name = 'Madis',
                planetarySystemId = 0,
                radius = 44300,
                atmos = true,
                gravity = 0.36
            },
            [2] = {
                GM = 157470826617,
                bodyId = 2,
                center = {
                    x = -8.000,
                    y = -8.000,
                    z = -126303.000
                },
                name = 'Alioth',
                planetarySystemId = 0,
                radius = 126068,
                atmos = true,
                gravity = 1.01
            },
            [3] = {
                GM = 11776905000,
                bodyId = 3,
                center = {
                    x = 29165536.000,
                    y = 10865536.000,
                    z = 65536.000
                },
                name = 'Thades',
                planetarySystemId = 0,
                radius = 49000,
                atmos = true,
                gravity = 0.50
            },
            [4] = {
                GM = 14893847582,
                bodyId = 4,
                center = {
                    x = -13234464.000,
                    y = 55765536.000,
                    z = 465536.000
                },
                name = 'Talemai',
                planetarySystemId = 0,
                radius = 57450,
                atmos = true,
                gravity = 0.46                    
            },
            [5] = {
                GM = 16951680000,
                bodyId = 5,
                center = {
                    x = -43534464.000,
                    y = 22565536.000,
                    z = -48934464.000
                },
                name = 'Feli',
                planetarySystemId = 0,
                radius = 60000,
                atmos = true,
                gravity = 0.48                    
            },
            [6] = {
                GM = 10502547741,
                bodyId = 6,
                center = {
                    x = 52765536.000,
                    y = 27165538.000,
                    z = 52065535.000
                },
                name = 'Sicari',
                planetarySystemId = 0,
                radius = 51100,
                atmos = true,
                gravity = 0.41                    
            },
            [7] = {
                GM = 13033380591,
                bodyId = 7,
                center = {
                    x = 58665538.000,
                    y = 29665535.000,
                    z = 58165535.000
                },
                name = 'Sinnen',
                planetarySystemId = 0,
                radius = 54950,
                atmos = true,
                gravity = 0.44                    
            },
            [8] = {
                GM = 18477723600,
                bodyId = 8,
                center = {
                    x = 80865538.000,
                    y = 54665536.000,
                    z = -934463.940
                },
                name = 'Teoma',
                planetarySystemId = 0,
                radius = 62000,
                atmos = true,
                gravity = 0.49
            },
            [9] = {
                GM = 18606274330,
                bodyId = 9,
                center = {
                    x = -94134462.000,
                    y = 12765534.000,
                    z = -3634464.000
                },
                name = 'Jago',
                planetarySystemId = 0,
                radius = 61590,
                atmos = true,
                gravity = 0.50
            },
            [10] = {
                GM = 78480000,
                bodyId = 10,
                center = {
                    x = 17448118.224,
                    y = 22966846.286,
                    z = 143078.820
                },
                name = 'Madis Moon 1',
                planetarySystemId = 0,
                radius = 10000,
                atmos = false,
                gravity = 0.08
            },
            [11] = {
                GM = 237402000,
                bodyId = 11,
                center = {
                    x = 17194626.000,
                    y = 22243633.880,
                    z = -214962.810
                },
                name = 'Madis Moon 2',
                planetarySystemId = 0,
                radius = 11000,
                atmos = false,
                gravity = 0.10
            },
            [12] = {
                GM = 265046609,
                bodyId = 12,
                center = {
                    x = 17520614.000,
                    y = 22184730.000,
                    z = -309989.990
                },
                name = 'Madis Moon 3',
                planetarySystemId = 0,
                radius = 15005,
                atmos = false,
                gravity = 0.12
            },
            [21] = {
                GM = 2118960000,
                bodyId = 21,
                center = {
                    x = 457933.000,
                    y = -1509011.000,
                    z = 115524.000
                },
                name = 'Alioth Moon 1',
                planetarySystemId = 0,
                radius = 30000,
                atmos = false,
                gravity = 0.24
            },
            [22] = {
                GM = 2165833514,
                bodyId = 22,
                center = {
                    x = -1692694.000,
                    y = 729681.000,
                    z = -411464.000
                },
                name = 'Alioth Moon 4',
                planetarySystemId = 0,
                radius = 30330,
                atmos = false,
                gravity = 0.24
            },
            [26] = {
                GM = 68234043600,
                bodyId = 26,
                center = {
                    x = -1404835.000,
                    y = 562655.000,
                    z = -285074.000
                },
                name = 'Sanctuary',
                planetarySystemId = 0,
                radius = 83400,
                atmos = true,
                gravity = 1.00
            },
            [30] = {
                GM = 211564034,
                bodyId = 30,
                center = {
                    x = 29214402.000,
                    y = 10907080.695,
                    z = 433858.200
                },
                name = 'Thades Moon 1',
                planetarySystemId = 0,
                radius = 14002,
                atmos = false,
                gravity = 0.11
            },
            [31] = {
                GM = 264870000,
                bodyId = 31,
                center = {
                    x = 29404193.000,
                    y = 10432768.000,
                    z = 19554.131
                },
                name = 'Thades Moon 2',
                planetarySystemId = 0,
                radius = 15000,
                atmos = false,
                gravity = 0.12
            },
            [40] = {
                GM = 141264000,
                bodyId = 40,
                center = {
                    x = -13503090.000,
                    y = 55594325.000,
                    z = 769838.640
                },
                name = 'Talemai Moon 2',
                planetarySystemId = 0,
                radius = 12000,
                atmos = false,
                gravity = 0.10
            },
            [41] = {
                GM = 106830900,
                bodyId = 41,
                center = {
                    x = -12800515.000,
                    y = 55700259.000,
                    z = 325207.840
                },
                name = 'Talemai Moon 3',
                planetarySystemId = 0,
                radius = 11000,
                atmos = false,
                gravity = 0.09
            },
            [42] = {
                GM = 264870000,
                bodyId = 42,
                center = {
                    x = -13058408.000,
                    y = 55781856.000,
                    z = 740177.760
                },
                name = 'Talemai Moon 1',
                planetarySystemId = 0,
                radius = 15000,
                atmos = false,
                gravity = 0.12
            },
            [50] = {
                GM = 499917600,
                bodyId = 50,
                center = {
                    x = -43902841.780,
                    y = 22261034.700,
                    z = -48862386.000
                },
                name = 'Feli Moon 1',
                planetarySystemId = 0,
                radius = 14000,
                atmos = false,
                gravity = 0.11
            },
            [70] = {
                GM = 396912600,
                bodyId = 70,
                center = {
                    x = 58969616.000,
                    y = 29797945.000,
                    z = 57969449.000
                },
                name = 'Sinnen Moon 1',
                planetarySystemId = 0,
                radius = 17000,
                atmos = false,
                gravity = 0.14
            },
            [100] = {
                GM = 13975172474,
                bodyId = 100,
                center = {
                    x = 98865536.000,
                    y = -13534464.000,
                    z = -934461.990
                },
                name = 'Lacobus',
                planetarySystemId = 0,
                radius = 55650,
                atmos = true,
                gravity = 0.46
            },
            [101] = {
                GM = 264870000,
                bodyId = 101,
                center = {
                    x = 98905288.170,
                    y = -13950921.100,
                    z = -647589.530
                },
                name = 'Lacobus Moon 3',
                planetarySystemId = 0,
                radius = 15000,
                atmos = false,
                gravity = 0.12
            },
            [102] = {
                GM = 444981600,
                bodyId = 102,
                center = {
                    x = 99180968.000,
                    y = -13783862.000,
                    z = -926156.400
                },
                name = 'Lacobus Moon 1',
                planetarySystemId = 0,
                radius = 18000,
                atmos = false,
                gravity = 0.14
            },
            [103] = {
                GM = 211503600,
                bodyId = 103,
                center = {
                    x = 99250052.000,
                    y = -13629215.000,
                    z = -1059341.400
                },
                name = 'Lacobus Moon 2',
                planetarySystemId = 0,
                radius = 14000,
                atmos = false,
                gravity = 0.11
            },
            [110] = {
                GM = 9204742375,
                bodyId = 110,
                center = {
                    x = 14165536.000,
                    y = -85634465.000,
                    z = -934464.300
                },
                name = 'Symeon',
                planetarySystemId = 0,
                radius = 49050,
                atmos = true,
                gravity = 0.39
            },
            [120] = {
                GM = 7135606629,
                bodyId = 120,
                center = {
                    x = 2865536.700,
                    y = -99034464.000,
                    z = -934462.020
                },
                name = 'Ion',
                planetarySystemId = 0,
                radius = 44950,
                atmos = true,
                gravity = 0.36
            },
            [121] = {
                GM = 106830900,
                bodyId = 121,
                center = {
                    x = 2472916.800,
                    y = -99133747.000,
                    z = -1133582.800
                },
                name = 'Ion Moon 1',
                planetarySystemId = 0,
                radius = 11000,
                atmos = false,
                gravity = 0.09
            },
            [122] = {
                GM = 176580000,
                bodyId = 122,
                center = {
                    x = 2995424.500,
                    y = -99275010.000,
                    z = -1378480.700
                },
                name = 'Ion Moon 2',
                planetarySystemId = 0,
                radius = 15000,
                atmos = false,
                gravity = 0.12
            },
        }
    }
end

atlas = Atlas()

setContainerInfo()
setContainerDisplayInfo()

-- Function Definitions
function getMagnitudeInDirection(vector, direction)
    vector = vec3(vector)
    direction = vec3(direction):normalize()
    local result = vector * direction -- To preserve sign, just add them I guess   
    return result.x + result.y + result.z
end     

function convertToWorldCoordinates(pos) -- Many thanks to SilverZero for this.
    local num  = ' *([+-]?%d+%.?%d*e?[+-]?%d*)'
    local posPattern = '::pos{' .. num .. ',' .. num .. ',' ..  num .. ',' .. num ..  ',' .. num .. '}'    
    local systemId, bodyId, latitude, longitude, altitude = string.match(pos, posPattern)
    if (systemId == "0" and bodyId == "0") then
        return vec3(tonumber(latitude),
                    tonumber(longitude),
                    tonumber(altitude))
    end
    longitude = math.rad(longitude)
    latitude = math.rad(latitude)
    local planet = atlas[tonumber(systemId)][tonumber(bodyId)]  
    local xproj = math.cos(latitude);   
    local planetxyz = vec3(xproj*math.cos(longitude),
                          xproj*math.sin(longitude),
                             math.sin(latitude));
    return planet.center + (planet.radius + altitude) * planetxyz
end

function alignToWorldVector(vector, tolerance)
    -- Sets inputs to attempt to point at the autopilot target
    -- Meant to be called from Update or Tick repeatedly
    --if rateOfChange > (minimumRateOfChange+0.08) then
        if tolerance == nil then
            tolerance = alignmentTolerance
        end
        
        local APTargetReleativePos = (APTarget - vec3(core.getConstructWorldPos()))
        local APTargetYaw = APTargetReleativePos:project_on_plane(constructUp)
        local APTargetAngle = APTargetYaw:angle_between(constructForward)
        local rightAngle = APTargetYaw:angle_between(constructRight)
        if (rightAngle * constants.rad2deg) < 90 then
            APTargetAngle = -APTargetAngle
        end

            local APYawPID = pid.new(1, 0, 5)
            APYawPID:inject(APTargetAngle)
            yawInput2 = APYawPID:get()
         --yawInput2 = - yawAmount
        
         if not APisaligned then

         end
        --system.print("yawInput2"..yawInput2)
        --system.print("previousYawAmount"..previousYawAmount)
        -- Return true or false depending on whether or not we're aligned
        if math.abs(APTargetAngle) * constants.rad2deg < math.min(tolerance,alignmentTolerance) then--math.abs(yawdiff)<math.min(tolerance,alignmentTolerance) then --and math.abs(pitchAmount) < tolerance then
            APisaligned = true
            yawInput2 = 0
            return true           
        else 
            --system.print("AP is aligning...")
            --system.print("APTargetAngle..." .. APTargetAngle * constants.rad2deg)
            APisaligned = false
        return false
        end
end

function ternary(cond, T, F)
    if cond then
        return T
    else
        return F
    end
end
function round(num, numDecimalPlaces)
    if num == nil then num = 0 
        return 0
    end
    local mult = 10 ^ (numDecimalPlaces or 0)
    if numDecimalPlaces ~= nil then
        return math.floor(num * mult + 0.5) / mult
    else
        return math.floor((num * mult + 0.5) / mult)
    end
end
function Kinematics()
    local Kinematic = {} -- just a namespace
    local C = 30000000 / 3600
    local C2 = C * C
    local ITERATIONS = 100 -- iterations over engine "warm-up" period
    local function lorentz(v)
        return 1 / math.sqrt(1 - v * v / C2)
    end

    function Kinematic.computeAccelerationTime(initial, acceleration, final)
        -- The low speed limit of following is: t=(vf-vi)/a (from: vf=vi+at)
        local k1 = C * math.asin(initial / C)
        return (C * math.asin(final / C) - k1) / acceleration
    end

    function Kinematic.computeDistanceAndTime(initial, final, restMass, thrust, t50, brakeThrust)
        t50 = t50 or 0
        brakeThrust = brakeThrust or 0 -- usually zero when accelerating
        local speedUp = initial <= final
        local a0 = thrust * (speedUp and 1 or -1) / restMass
        local b0 = -brakeThrust / restMass
        local totA = a0 + b0
        if speedUp and totA <= 0 or not speedUp and totA >= 0 then
            return -1, -1 -- no solution
        end
        local distanceToMax, timeToMax = 0, 0

        if a0 ~= 0 and t50 > 0 then
            local k1 = math.asin(initial / C)
            local c1 = math.pi * (a0 / 2 + b0)
            local c2 = a0 * t50
            local c3 = C * math.pi
            local v = function(t)
                local w = (c1 * t - c2 * math.sin(math.pi * t / 2 / t50) + c3 * k1) / c3
                local tan = math.tan(w)
                return C * tan / math.sqrt(tan * tan + 1)
            end
            local speedchk = speedUp and function(s)
                    return s >= final
                end or function(s)
                    return s <= final
                end
            timeToMax = 2 * t50
            if speedchk(v(timeToMax)) then
                local lasttime = 0
                while math.abs(timeToMax - lasttime) > 0.5 do
                    local t = (timeToMax + lasttime) / 2
                    if speedchk(v(t)) then
                        timeToMax = t
                    else
                        lasttime = t
                    end
                end
            end
            -- There is no closed form solution for distance in this case.
            -- Numerically integrate for time t=0 to t=2*T50 (or less)
            local lastv = initial
            local tinc = timeToMax / ITERATIONS
            for step = 1, ITERATIONS do
                local speed = v(step * tinc)
                distanceToMax = distanceToMax + (speed + lastv) * tinc / 2
                lastv = speed
            end
            if timeToMax < 2 * t50 then
                return distanceToMax, timeToMax
            end
            initial = lastv
        end

        local k1 = C * math.asin(initial / C)
        local time = (C * math.asin(final / C) - k1) / totA
        local k2 = C2 * math.cos(k1 / C) / totA
        local distance = k2 - C2 * math.cos((totA * time + k1) / C) / totA
        return distance + distanceToMax, time + timeToMax
    end

    function Kinematic.computeTravelTime(initial, acceleration, distance)
        -- The low speed limit of following is: t=(sqrt(2ad+v^2)-v)/a
        -- (from: d=vt+at^2/2)
        if distance == 0 then
            return 0
        end
        if acceleration > 0 then
            local k1 = C * math.asin(initial / C)
            local k2 = C2 * math.cos(k1 / C) / acceleration
            return (C * math.acos(acceleration * (k2 - distance) / C2) - k1) / acceleration
        end
        assert(initial > 0, "Acceleration and initial speed are both zero.")
        return distance / initial
    end

    function Kinematic.lorentz(v)
        return lorentz(v)
    end
    return Kinematic
end



if debug then
    --local input = "::pos{0,2,44.7416,98.8891,296.1514}"
    --local input = "::pos{0,2,44.7194,98.8856,311.8763}"
    local input = "::pos{0,2,44.7129,98.8818,276.8629}"
    i = string.find(input, "::")
    local pos = string.sub(input, i)
    local num = " *([+-]?%d+%.?%d*e?[+-]?%d*)"
    local posPattern = "::pos{" .. num .. "," .. num .. "," .. num .. "," .. num .. "," .. num .. "}"
    local systemId, bodyId, latitude, longitude, altitude = string.match(pos, posPattern)
    local planet = atlas[tonumber(systemId)][tonumber(bodyId)].name
    targetPos = vec3(convertToWorldCoordinates(pos))
    currentPos = vec3(core.getConstructWorldPos())
    APTarget = targetPos
    apActive = true
end

function script.onStart()
    VERSION_NUMBER = 0.002
    unit.setTimer("tenthSecond", 1/10)
    unit.setTimer("oneSecond", 1)
end
function script.onFlush()

    rateOfChange = vec3(core.getConstructWorldOrientationForward()):dot(vec3(core.getWorldVelocity()):normalize())
    inAtmo = (atmosphere() > 0)

    LastMaxBrake = 0
    local torqueFactor = 2 -- Force factor applied to reach rotationSpeed<br>(higher value may be unstable)<br>Valid values: Superior or equal to 0.01
    -- validate params
    yawSpeedFactor = math.max(yawSpeedFactor, 0.01)
    torqueFactor = math.max(torqueFactor, 0.01)
    brakeSpeedFactor = math.max(brakeSpeedFactor, 0.01)
    brakeFlatFactor = math.max(brakeFlatFactor, 0.01)
    stabilization = 0

    currentAltitude = core.getAltitude()
    if currentAltitude == nil then
        currentAltitude = 0
    end
    -- final inputs
    local finalPitchInput = utils.clamp(pitchInput + pitchInput2 + system.getControlDeviceForwardInput(),-1,1)
    local finalRollInput = utils.clamp(rollInput + rollInput2 + system.getControlDeviceYawInput(),-1,1)
    local finalYawInput = utils.clamp((yawInput + yawInput2) - system.getControlDeviceLeftRightInput(),-1,1)
    -- Axis
    worldVertical = vec3(core.getWorldVertical()) -- along gravity
    constructUp = vec3(core.getConstructWorldOrientationUp())
    constructForward = vec3(core.getConstructWorldOrientationForward())
    constructRight = vec3(core.getConstructWorldOrientationRight())
    constructVelocity = vec3(core.getWorldVelocity())
    local constructVelocityDir = vec3(core.getWorldVelocity()):normalize()
    local currentRollDeg = getRoll(worldVertical, constructForward, constructRight)
    local currentRollDegAbs = math.abs(currentRollDeg)
    local currentRollDegSign = utils.sign(currentRollDeg)
    local atmosphere = atmosphere()

    -- Rotation
    local constructAngularVelocity = vec3(core.getWorldAngularVelocity())
    local targetAngularVelocity =
        finalPitchInput * pitchSpeedFactor * constructRight + finalRollInput * rollSpeedFactor * constructForward +
            finalYawInput * yawSpeedFactor * constructUp

    if not level then
        targetAngularVelocity =
        finalPitchInput * pitchSpeedFactor * constructRight + finalRollInput * rollSpeedFactor * constructForward +
        finalYawInput * yawSpeedFactor * constructUp
    end

    if autoalt then
        Kinematic = Kinematics()
        local maxBrake = json.decode(unit.getData()).maxBrake
        if maxBrake ~= nil then
            LastMaxBrake = maxBrake
        end

        vSpeed = constructVelocity:project_on(worldVertical):len()
        vSpeedSigned = vSpeed * -utils.sign(constructVelocity:dot(worldVertical))

        brakeDistance = 0

        if LastMaxBrake ~= nil then
            brakeDistance, _ =
                Kinematic.computeDistanceAndTime(
                vSpeed,
                0,
                core.getConstructIMass(),
                0,
                0,
                LastMaxBrake - (core.g() * core.getConstructIMass()) * utils.sign(vSpeedSigned)
            )
        end

        --system.print("brakeDistance: " .. brakeDistance)

        --startup = json.decode(db.getStringValue("startlocation"))
        --startorientation = vec3(startup.x, startup.y, startup.z)

        --vecDiff = vec3(core.getConstructWorldPos()) - vec3(startorientation)

         --initialAlt + vecDiff:project_on(constructUp):len() * utils.sign(vecDiff:dot(constructUp))
         
        diff = targetAltitude - currentAltitude

        if atmosphere > 0.2 then
            vMaxSpeed,hMaxSpeed = 1100
        else
            vMaxSpeed = 4000
        end

        vTargetSpeed = utils.clamp(diff, -vMaxSpeed, vMaxSpeed)

        if
                math.abs(Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal)) < 0.1 and atmosphere > 0 and
                math.abs((targetAltitude - currentAltitude)) < 25 and
                math.abs((targetAltitude - currentAltitude)) > 5
         then
                finalBrakeInput = 1
        elseif
                math.abs(Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal)) < 0.1 and atmosphere > 0 and
                targetAltitude < currentAltitude and
                math.abs(vSpeed) > 25 and
                brakeDistance > math.abs((targetAltitude - currentAltitude))
         then 
            finalBrakeInput = 1
        elseif teledown > 0 and targetAltitude < currentAltitude and math.abs(vSpeed) > 10 then
            finalBrakeInput = 1
            vTargetSpeed = 10
        else
            finalBrakeInput = brakeInput
        end

        local power = 3
        local up_down_switch = 0

        --system.print(vTargetSpeed)

        if currentAltitude < targetAltitude then
            up_down_switch = -1
            targetVelocity = (up_down_switch * vTargetSpeed / 3.6) * worldVertical
            stabilization = power * (targetVelocity - vec3(core.getWorldVelocity()))
            Nav:setEngineCommand("vertical, brake", stabilization - vec3(core.getWorldGravity()), vec3(), false)
        end

        if currentAltitude > targetAltitude then
            up_down_switch = 1
            targetVelocity = (up_down_switch * math.abs(vTargetSpeed) / 3.6) * worldVertical
            stabilization = power * (targetVelocity - vec3(core.getWorldVelocity()))
            Nav:setEngineCommand("vertical, brake", stabilization - vec3(core.getWorldGravity()), vec3(), false)
        end
    end
    if level then
        local currentPitchDeg = getRoll(worldVertical, constructRight, -constructForward)
        local currentPitchDegAbs = math.abs(currentPitchDeg)
        local currentPitchDegSign = utils.sign(currentPitchDeg)
        local currentYawDeg = constructRight:dot(constructForward) * 180
        local currentYawDegAbs = math.abs(currentYawDeg)
        local currentYawDegSign = utils.sign(currentYawDeg)
        local threshold = 0.001

        local autoRollFactor = 4
        if currentPitchDegAbs > threshold then
            local targetPitchDeg = utils.clamp(0, currentPitchDegAbs - 30, currentPitchDegAbs + 30) -- we go back to 0 within a certain limit
            if (PitchPID == nil) then
                PitchPID = pid.new(autoRollFactor * 0.01, 0, autoRollFactor * 0.1) -- magic number tweaked to have a default factor in the 1-10 range
            end
            PitchPID:inject(targetPitchDeg - currentPitchDeg)
            local autoPitchInput = PitchPID:get()
            targetAngularVelocity = targetAngularVelocity + autoPitchInput * constructRight
        end

        if currentRollDegAbs > threshold then
            local targetRollDeg = utils.clamp(0, currentRollDegAbs - 30, currentRollDegAbs + 30) -- we go back to 0 within a certain limit
            if (rollPID == nil) then
                rollPID = pid.new(autoRollFactor * 0.01, 0, autoRollFactor * 0.1) -- magic number tweaked to have a default factor in the 1-10 range
            end
            rollPID:inject(targetRollDeg - currentRollDeg)
            local autoRollInput = rollPID:get()
            targetAngularVelocity = targetAngularVelocity + autoRollInput * constructForward
        end
    end

    -- Engine commands
    local keepCollinearity = 1 -- for easier reading
    local dontKeepCollinearity = 0 -- for easier reading
    local tolerancePercentToSkipOtherPriorities = 1 -- if we are within this tolerance (in%), we don't go to the next priorities


    -- Rotation
    local angularAcceleration = torqueFactor * (targetAngularVelocity - constructAngularVelocity)
    local airAcceleration = vec3(core.getWorldAirFrictionAngularAcceleration())
    angularAcceleration = angularAcceleration - airAcceleration -- Try to compensate air friction
    Nav:setEngineTorqueCommand(
        "torque",
        angularAcceleration,
        keepCollinearity,
        "airfoil",
        "",
        "",
        tolerancePercentToSkipOtherPriorities
    )

    finalBrakeInput = brakeInput + brakeInput2

    -- Brakes
    local brakeAcceleration =
        -finalBrakeInput * (brakeSpeedFactor * constructVelocity + brakeFlatFactor * constructVelocityDir)
    Nav:setEngineForceCommand("brake", brakeAcceleration)

    -- Longitudinal Translation
    local longitudinalEngineTags = "thrust analog longitudinal"
    local longitudinalCommandType = Nav.axisCommandManager:getAxisCommandType(axisCommandId.longitudinal)
    if (longitudinalCommandType == axisCommandType.byThrottle) then
        local longitudinalAcceleration =
            Nav.axisCommandManager:composeAxisAccelerationFromThrottle(
            longitudinalEngineTags,
            axisCommandId.longitudinal
        )
        Nav:setEngineForceCommand(longitudinalEngineTags, longitudinalAcceleration, keepCollinearity)
    end

    -- Lateral Translation
    local lateralStrafeEngineTags = "thrust analog lateral"
    local lateralCommandType = Nav.axisCommandManager:getAxisCommandType(axisCommandId.lateral)
    if (lateralCommandType == axisCommandType.byThrottle) then
        local lateralStrafeAcceleration =
            Nav.axisCommandManager:composeAxisAccelerationFromThrottle(lateralStrafeEngineTags, axisCommandId.lateral)
        Nav:setEngineForceCommand(lateralStrafeEngineTags, lateralStrafeAcceleration, keepCollinearity)
    elseif (lateralCommandType == axisCommandType.byvTargetSpeed) then
        local lateralAcceleration = Nav.axisCommandManager:composeAxisAccelerationFromvTargetSpeed(axisCommandId.lateral)
        autoNavigationEngineTags = autoNavigationEngineTags .. " , " .. lateralStrafeEngineTags
        autoNavigationAcceleration = autoNavigationAcceleration + lateralAcceleration
    end

    -- Vertical Translation
    if not autoalt then
        local verticalStrafeEngineTags = "thrust analog vertical"
        local verticalCommandType = Nav.axisCommandManager:getAxisCommandType(axisCommandId.vertical)
        if (verticalCommandType == axisCommandType.byThrottle) then
            local verticalStrafeAcceleration =
                Nav.axisCommandManager:composeAxisAccelerationFromThrottle(
                verticalStrafeEngineTags,
                axisCommandId.vertical
            )
            Nav:setEngineForceCommand(
                verticalStrafeEngineTags,
                verticalStrafeAcceleration,
                keepCollinearity,
                "airfoil",
                "ground",
                "",
                tolerancePercentToSkipOtherPriorities
            )
        end
    end
    -- Rockets
    Nav:setBoosterCommand("rocket_engine")
end
function script.onTick(timerId)
    if timerId == "tenthSecond" then

        if lockBrake then
            brakeInput2 = 1
        else brakeInput2 = 0                     
        end

        local up = vec3(core.getWorldVertical()) * -1
        local velocity = vec3(core.getWorldVelocity())
        local vSpd = (velocity.x * up.x) + (velocity.y * up.y) + (velocity.z * up.z)
        hSpd = velocity:len() - math.abs(vSpd)
        local airFriction = vec3(core.getWorldAirFrictionAcceleration()) -- Maybe includes lift?
        -- todo LastMaxBrake
        brakeDistance, brakeTime = Kinematic.computeDistanceAndTime(hSpd, 0, constructMass(), 0, 0,
        LastMaxBrake + vec3(core.getWorldAirFrictionAcceleration()):len() *
            constructMass())      

        if not apActive then 
            yawInput2 = 0
            pitchInput2 = 0
            lockBrake = false    
            speedincrement = 0
            APthrust = 0
        end


        --system.print("brakeInput: " .. brakeInput) 
        --system.print("brakeInput2: " .. brakeInput2) 
        --system.print("lockBrake:" ..(lockBrake and 'true' or 'false') )
        
        if debug then
        end
        

        if APTarget ~= nil then
            distance3d = (vec3(core.getConstructWorldPos()) - APTarget):len()            
            local cwg = vec3(core.getConstructWorldPos())

           local APTargetReleativePos = (APTarget - vec3(core.getConstructWorldPos()))
           APTargetYaw = APTargetReleativePos:project_on_plane(constructUp)
           APTargetAngle= APTargetYaw:angle_between(constructForward)
           local rightAngle= APTargetYaw:angle_between(constructRight)
           if (rightAngle * constants.rad2deg) < 90 then
            APTargetAngle = -APTargetAngle
            end

            local horizonForward = APTarget:project_on_plane(cwg)
            distance = horizonForward:len()
           -- distance = (vec3(core.getConstructWorldPos()) - APTarget):project_on(vec3(core.getConstructWorldOrientationUp())):len()

            local targetVector = (vec3(core.getConstructWorldPos()) - APTarget)
            altDiff = (APTarget - vec3(core.getConstructWorldPos())):project_on(vec3(core.getConstructWorldOrientationUp())):len()
            

           -- local distance = targetVector:len() - verticalAmount

            --horizonUp = APTarget:project_on_plane(constructUp)
            --system.print("angle:" .. APTargetAngle * constants.rad2deg) --* constants.rad2deg)
        end

        if APTarget ~= nil and apActive  then

            system.print("altDiff"..altDiff)
            system.print("targetAltitude" .. targetAltitude)
            targetAltitude = currentAltitude + altDiff

            if currentAltitude == nil then
                currentAltitude = core.getAltitude()
            end

             if distance > 1 then
                x = alignToWorldVector(APTarget)
             end
             
             if (brakeDistance * 2.5 > distance) then 
                lockBrake = true    
                APspeedincrement = 0
                Nav.axisCommandManager:setThrottleCommand(axisCommandId.longitudinal, 0)
            else
                  lockBrake = false    
            end

             if not APisaligned then
                lockBrake = true                 
             else
                lockBrake = false
             end

               if targetAltitude < 1100 and distance > 1100 then
                   targetAltitude = 1100
               end

               if targetAltitude < 1100 and distance < 1100 then
                --targetAltitude = utils.clamp(targetAltitude, lowAlt,highAlt)
              end

               hTargetSpeed = utils.clamp(distance, -1000,1000)
  
               if (hSpd * 3.6 < hTargetSpeed) and APisaligned then
                    APspeedincrement = APspeedincrement + 0.01
                    local APthrust = APthrust + APspeedincrement
                   Nav.axisCommandManager:setThrottleCommand(axisCommandId.longitudinal, APthrust)
               else
                   Nav.axisCommandManager:setThrottleCommand(axisCommandId.longitudinal, 0)
               end
               system.print("Distance...".. distance)
               if distance < 5 and hSpd < 1 then
    
                lockBrake = true  
                targetAltitude = currentAltitude + altDiff
                 
                APspeedincrement = 0
                APthrust = 0
                yawInput2 = 0

              end
           end
       end
       if timerId == "oneSecond" then
        setContainerInfo()
        setContainerDisplayInfo()                     
       end
   
end

function script.onUpdate()

    if vSpeedSigned == nil then
        vSpeed_hud = 0
    else
        vSpeed_hud = round(vSpeedSigned * 3.6, 0)
    end

    hSpd_hud = round(hSpd * 3.6, 0)

    local currentvert = round(Nav.axisCommandManager:getThrottleCommand(axisCommandId.vertical) * 100, 2)--round(vert_engine.getThrust() / currentvert_max, 2) * 100
    local currentthrust = round(Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal) * 100, 2)
    local thrustbarneg = false

    if currentthrust < 0 then
        thrustbarneg = true
    end

    if currentAltitude == nil then
        currentAltitude = 0
    end
    if currentAltitude == nil then
        targetAltitude = 0
    end    

    local currentAltitude_hud = round(currentAltitude, 2)
    local targetAltitude_hud = round(targetAltitude, 2)
    local initialAlt_hud = round(initialAlt, 2)
    local distance_hud = round(distance,2)

    deltaheight =
        round(
        math.min(math.abs(currentAltitude_hud), math.abs(targetAltitude_hud)) /
            math.max(math.abs(currentAltitude_hud), math.abs(targetAltitude_hud)),
        2
    ) * 100

    local teledown = round(tele_down.getDistance(), 0)

    if startPositionAngle == nil then
        startPositionAngle = 0
    end

    local braketoggle = brakeInput + brakeInput2  > 0

    local autolevel = ternary(level, '<div class="on"></div>', '<div class="off"></div>')
    local isflipped = ternary(flip, '<div class="on"></div>', '<div class="off"></div>')
    local isautoalt = ternary(autoalt, '<div class="on"></div>', '<div class="off"></div>')
    local isaligned = ternary(APisaligned, '<div class="on"></div>', '<div class="off"></div>')
    local apActive_hud = ternary(apActive, '<div class="on"></div>', '<div class="off"></div>')
    local brakeInput_hud = ternary(braketoggle, '<div class="on"></div>', '<div class="off"></div>')   
    local braketoggle_hud = ternary(lockBrake, '<div class="on"></div>', '<div class="off"></div>')  

    local htmlTankInfo = ""
    local cssTankInfo = ""
    for key,value in pairs(fuelTanksDisplay) do 
        local tank = value
        local tankPercent = 0
        local tankColor = ""
        local fuelType = ""

        if tank.type == 1 then
            tankColor = "LightSkyBlue"
            fuelType = "Atmo " .. tank.size
        elseif tank.type == 2 then
            tankColor = "Crimson"
            fuelType = "Space " .. tank.size
        elseif tank.type == 3 then
            tankColor = "BlueViolet"
            fuelType = "Rocket " .. tank.size
        end
        if tank.percent == nil then
            tankPercent = 0
        else
            tankPercent = tank.percent
        end
        local htmlSegment = [[<p>]]..fuelType..[[</p>
         <div id="fuel_]]..key..[[">
         <div><p>]] ..
         tankPercent ..
            [[</p>
         </div>
      </div> ]] 
      htmlTankInfo = htmlTankInfo .. htmlSegment
      local cssSegment = [[#fuel_]]..key..[[ {
        background-color: #20201F;
        border-radius: 20px; /* (heightOfInnerDiv / 2) + padding */
        padding: 4px;
        }
        #fuel_]]..key..[[>div {
        background-color: ]] .. tankColor .. [[;    
        width: ]] ..
        tankPercent ..
        [[%; 
        height: 24px;
        border-radius: 10px;
        }]]
        cssTankInfo = cssTankInfo .. cssSegment
    end

    local thrustbarcolor = "#2cb6d1"
    if thrustbarneg then
        thrustbarcolor = "#F7901E"
    else
    end
    local css = [[
        <style>
        body {
        }
        .row {
            display: flex;
            justify-content: space-between;
            padding: 10px;
            flex-direction: row;
        }
         .column {
           width: 30%;
           padding: 10px;
         }
        .controls-hud {
        display: flex;
        flex-direction: column;
        border-color: #333333;
        border-radius: 12px;
        width: 35%;
        padding: 1% 1.5%;
        overflow: none;
        }
        .controls-hud-right {
            display: flex;
            flex-direction: column;
            border-color: #333333;
            border-radius: 12px;
            width: 35%;
            padding: 1% 1.5%;
            overflow: none;
            padding-top: 50%
            }
        p {
        font-size: 20px;  
        font-weight: 300;
        color: white;
        }
        .control-container {
        display: flex;
        justify-content: space-between;
        padding: 1%;
        background-color: #20201F;
        opacity:0.6;
        }
        .on {
        background-color: #2cb6d1;
        margin-left: 10px;
        border-radius: 50%;
        width: 20px;
        height: 20px;
        border: 2px solid black;
        }
        .off {
        background-color: #F7901E;
        margin-left: 10px;
        border-radius: 50%;
        width: 20px;
        height: 20px;
        border: 2px solid black;
        }
        #horizontal {
        background-color: #20201F;
        border-radius: 20px; /* (heightOfInnerDiv / 2) + padding */
        padding: 4px;
        }
        #horizontal>div {
        background-color: ]] ..
        thrustbarcolor ..
        [[;    
        width: ]] ..
        math.abs(currentthrust) ..
        [[%; 
        height: 20px;
        border-radius: 10px;
        }]]
        .. cssTankInfo ..
        [[
        #vertical {
        background-color: #20201F;
        border-radius: 20px; /* (heightOfInnerDiv / 2) + padding */
        padding: 4px;
        }
        #vertical>div {
        background-color: #2cb6d1;
        width: ]] ..
        currentvert ..
        [[%; 
        height: 16px;
        border-radius: 10px;
        }
        #alt_diff {
        background-color:#20201F;
        border-radius: 20px; /* (heightOfInnerDiv / 2) + padding */
        padding: 4px;
        width: 24px;
        height: 200px;
        }
        #alt_diff>div {
        background-color: #2cb6d1;
        height: ]] ..
        deltaheight ..
        [[%;  
        width: 16px;
        border-radius: 10px;
        position: relative;
        top: ]] ..
        100 - deltaheight ..
        [[%; 
        }
     </style>]]

     local html = [[        
<div class="row">
<div class="column">
   <h2>Basic</h2>
   <div class="controls-hud">
      <div class="control-container">
         <p>Vertical Speed</p>
         ]] ..
         vSpeed_hud ..
         [[ km/h
      </div>
      <div class="control-container">
         <p>Horizontal Speed</p>
         ]] ..
         hSpd_hud ..
         [[ km/h
      </div>
      <div class="control-container">
         <p>Braking</p>
         ]] ..
         brakeInput_hud ..
         [[
      </div>
      <div class="control-container">
         <p>Auto Level</p>
         ]] ..
         autolevel ..
         [[
      </div>
      <div class="control-container">
         <p>Auto Altitude</p>
         ]] ..
         isautoalt ..
         [[
      </div>
      <div class="control-container">
         <p>Current Alt</p>
         ]] ..
         currentAltitude_hud ..
         " m" ..
         [[
      </div>
      <div class="control-container">
         <p>Target Alt</p>
         ]] ..
         targetAltitude_hud ..
         " m" ..
         [[
      </div>
      <div class="control-container">
         <p>Base Alt</p>
         ]] ..
         initialAlt_hud ..
         " m" ..
         [[
      </div>
   </div>
   
   <h2>Thrust</h2>
   <div class="controls-hud">
      <p>Horizontal Thrust</p>
      <div id="horizontal">
         <div>]] ..
            currentthrust ..
            " %" ..
            [[
         </div>
      </div>
      <p>Vertical Thrust</p>
      <div id="vertical">
         <div>]] ..
            currentvert ..
            " %" ..
            [[
         </div>
      </div>
      <p>Height Reached</p>
      <div id="alt_diff">
         <div>]] ..
            deltaheight ..
            " %" ..
            [[
         </div>
      </div>
   </div>
</div>
<div class="column">
   <div class="controls-hud-right">
   <h2>Fuel</h2>
      ]] .. htmlTankInfo ..[[
   </div>
</div>
</div>
</div>]]

    html = css .. html
    system.setScreen(html)
    system.showScreen(1)
end

function script.onActionStart(action)
    if action == "brake" then
        brakeInput = brakeInput + 1
        local longitudinalCommandType = Nav.axisCommandManager:getAxisCommandType(axisCommandId.longitudinal)
        if (longitudinalCommandType == axisCommandType.byvTargetSpeed) then
            local vTargetSpeed = Nav.axisCommandManager:getvTargetSpeed(axisCommandId.longitudinal)
            if (math.abs(vTargetSpeed) > constants.epsilon) then
                Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.longitudinal, - utils.sign(vTargetSpeed))
            end
        end
    elseif action == "forward" then
        if level then
            --Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.longitudinal, 1)
        else
        pitchInput = pitchInput - 1
        end 


    elseif action == "speedup" then
        Nav.axisCommandManager:setThrottleCommand(axisCommandId.longitudinal, 0)
        throttle_increment = 0
    elseif action == "backward" then
        if level then
            --Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.longitudinal, -1)
        else
        pitchInput = pitchInput + 1
        end    
    elseif action == "left" then
        if level then
            Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, -1.0)
        else    
        rollInput = rollInput - 1
        end
    elseif action == "right" then
        if level then
            Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, 1.0)
        else    
        rollInput = rollInput + 1
        end
    elseif action == "yawright" then
        yawInput = yawInput - 1
    elseif action == "yawleft" then
        yawInput = yawInput + 1
    elseif action == "straferight" then
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, 1.0)
    elseif action == "strafeleft" then
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, -1.0)
    elseif action == "speedup" then
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.longitudinal, 5.0)
    elseif action == "speeddown" then
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.longitudinal, -5.0)                
    elseif action == "up" then
        if autoalt then
            increment = 0.125    
        else   
        Nav.axisCommandManager:deactivateGroundEngineAltitudeStabilization()
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.vertical, 1.0)
        end
    elseif action == "down" then
        if autoalt then
            increment = 0.125
        else   
        Nav.axisCommandManager:deactivateGroundEngineAltitudeStabilization()
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.vertical, -1.0)
        end
    elseif action == "option1" then
        level = not level
    elseif action == "option2" then
        autoalt = not autoalt
    elseif action == "option4" then
        --apActive = not apActive
        --if lockBrake then 
        --    lockBrake  = false 
        --    brakeInput = 0
        --end
       end
end

function script.onActionStop(action)
    if action == "brake" then
        brakeInput = brakeInput - 1
    elseif action == "forward" then
        if level then
        else
        pitchInput = pitchInput + 1
        end
    elseif action == "backward" then
        if level then
        else
        pitchInput = pitchInput - 1
        end    
    elseif action == "left" then
        if level then
            Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, 1.0)
        else    
        rollInput = rollInput + 1
        end
    elseif action == "right" then
        if level then
            Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, -1.0)
        else    
        rollInput = rollInput - 1
        end
    elseif action == "yawright" then
        yawInput = yawInput + 1
    elseif action == "yawleft" then
        yawInput = yawInput - 1
    elseif action == "straferight" then
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.lateral, -1.0)
    elseif action == "strafeleft" then
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.lateral, 1.0)
    elseif action == "up" then
        if autoalt then
            increment = 0.125
        else   
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.vertical, -1.0)
        Nav.axisCommandManager:activateGroundEngineAltitudeStabilization(currentGroundAltitudeStabilization)
        end
    elseif action == "down" then
            if autoalt then
                increment = 0.125
        else   
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.vertical, 1.0)
        Nav.axisCommandManager:activateGroundEngineAltitudeStabilization(currentGroundAltitudeStabilization)
        end
    elseif action == "option2" then
        initialAlt = core.getAltitude()
        targetAltitude = initialAlt
    end
end

function script.onActionLoop(action)
    if action == "brake" then
    elseif action == "forward" then
        if level then
            throttle_increment = throttle_increment + 0.01
            --system.print("actionLoop forward".. math.abs(throttle_input))          
            local throttle_input = throttle_input + throttle_increment
           Nav.axisCommandManager:setThrottleCommand(axisCommandId.longitudinal, throttle_input)
           
        else
        --pitchInput = pitchInput + 1
        end       
    elseif action == "backward" then
        if level then
            throttle_increment = throttle_increment - 0.01
            local throttle_input = throttle_input + throttle_increment
            Nav.axisCommandManager:setThrottleCommand(axisCommandId.longitudinal, throttle_input)
            --system.print("actionLoop backward".. math.abs(throttle_input))
        else
        --pitchInput = pitchInput - 1
        end
    elseif action == "up" then
        if autoalt then
            targetAltitude = targetAltitude + increment
            increment = increment + 0.0125
            end    
    elseif action == "down" then
            if autoalt then
                targetAltitude = targetAltitude - increment
                increment = increment + 0.0125
                end 

    end

end    
function script.onInputText(text)
    local i
    local commands = "/commands /setname /G /agg /addlocation"
    local command, arguement
    local commandhelp =
        [[Command List:\n
    /commands \n
    /althold <targetheight> - Manually set target height in meters \n
    /goto ::pos{0,2,46.4596,-155.1799,22.6572} - move to target location]]
    i = string.find(text, " ")
    if i ~= nil then
        command = string.sub(text, 0, i - 1)
        arguement = string.sub(text, i + 1)
    elseif i == nil or not string.find(commands, command) then
        for str in string.gmatch(commandhelp, "([^\n]+)") do
            system.print(str)
        end
        return
    end

    if command == "/althold" then
        if arguement == nil or arguement == "" then
            msgText = "Usage: /althold targetheight"
            system.print(msgText)
            return
        end
        if not autoalt then
            msgText = "/althold can only be used in auto altitude mode - press Alt+2 to toggle"
            system.print(msgText)
            return
        end
        arguement = tonumber(arguement)
        targetAltitude = arguement
        msgText = "Target Altitude set to: '" .. arguement .. "'"
        system.print(msgText)
    end
end
script.onStart()