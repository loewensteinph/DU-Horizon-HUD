-- Script is laid out variables, functions, control, control (the Hud proper) starts around line 4000
Nav = Navigator.new(system, core, unit)

script = {}  -- wrappable container for all the code. Different than normal DU Lua in that things are not seperated out.

-- Edit LUA Variable user settings.  Must be global to work with databank system as set up due to using _G assignment
-- Auto Variable declarations that store status of ship. Must be global because they get saved/read to Databank due to using _G assignment
local pitchInput = 0
local rollInput = 0
local yawInput = 0
local brakeInput = 0
local Kinematic = nil

targetAltitude = 0
increment = 0.125
finalBrakeInput = 0
level = true
autoalt = true
braking = false
startPosition = vec3(core.getConstructWorldPos())
initialAlt = core.getAltitude()
targetAltitude = initialAlt
-- Function Definitions
function ternary(cond, T, F)
    if cond then
        return T
    else
        return F
    end
end
function round(num, numDecimalPlaces)
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
function script.onStart()
    VERSION_NUMBER = 0.803

end
function script.onFlush()

    LastMaxBrake = 0
    local atmosphere = unit.getAtmosphereDensity()


    local torqueFactor = 2 -- Force factor applied to reach rotationSpeed<br>(higher value may be unstable)<br>Valid values: Superior or equal to 0.01

    -- validate params
    yawSpeedFactor = math.max(yawSpeedFactor, 0.01)
    torqueFactor = math.max(torqueFactor, 0.01)
    brakeSpeedFactor = math.max(brakeSpeedFactor, 0.01)
    brakeFlatFactor = math.max(brakeFlatFactor, 0.01)
    stabilization = 0

    -- final inputs
    --finalBrakeInput = brakeInput

    -- final inputs
    local finalPitchInput = pitchInput + system.getControlDeviceForwardInput()
    local finalRollInput = rollInput + system.getControlDeviceYawInput()
    local finalYawInput = yawInput - system.getControlDeviceLeftRightInput()

    -- Axis
    local worldVertical = vec3(core.getWorldVertical()) -- along gravity
    constructUp = vec3(core.getConstructWorldOrientationUp())
    constructForward = vec3(core.getConstructWorldOrientationForward())
    constructRight = vec3(core.getConstructWorldOrientationRight())
    constructVelocity = vec3(core.getWorldVelocity())
    local constructVelocityDir = vec3(core.getWorldVelocity()):normalize()
    local currentRollDeg = getRoll(worldVertical, constructForward, constructRight)
    local currentRollDegAbs = math.abs(currentRollDeg)
    local currentRollDegSign = utils.sign(currentRollDeg)

    -- Rotation
    local constructAngularVelocity = vec3(core.getWorldAngularVelocity())
    local targetAngularVelocity = finalYawInput * yawSpeedFactor * constructUp

    finalBrakeInput = brakeInput

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

        currentaltitude = core.getAltitude()
         --initialAlt + vecDiff:project_on(constructUp):len() * utils.sign(vecDiff:dot(constructUp))

        if currentaltitude == nil then
            currentaltitude = 0
        end

        diff = targetAltitude - currentaltitude

        if atmosphere > 0.2 then
            MaxSpeed = 1100
        else
            MaxSpeed = 4000
        end

        targetSpeed = utils.clamp(diff, -MaxSpeed, MaxSpeed)

        if
            math.abs(Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal)) < 0.1 and
                math.abs((targetAltitude - currentaltitude)) < 25 and
                math.abs((targetAltitude - currentaltitude)) > 5
         then
            finalBrakeInput = 1
        elseif
            math.abs(Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal)) < 0.1 and atmosphere > 0 and
                targetAltitude < currentaltitude and
                math.abs(vSpeed) > 25 and
                brakeDistance > math.abs((targetAltitude - currentaltitude))
         then --math.abs(targetSpeed) < 5
            --  elseif atmosphere == 0 and alt < 6000 and  math.abs(vSpeed) > MaxSpeed / 3.6 then --math.abs(targetSpeed) < 5
            --      finalBrakeInput = 1
            finalBrakeInput = 1
        elseif teledown > 0 and targetAltitude < currentaltitude and math.abs(vSpeed) > 10 then
            finalBrakeInput = 1
            targetSpeed = 10
        else
            finalBrakeInput = brakeInput
        end

        local power = 3
        local up_down_switch = 0

        --system.print(targetSpeed)

        if currentaltitude < targetAltitude then
            up_down_switch = -1
            targetVelocity = (up_down_switch * targetSpeed / 3.6) * worldVertical
            stabilization = power * (targetVelocity - vec3(core.getWorldVelocity()))
            Nav:setEngineCommand("vertical, brake", stabilization - vec3(core.getWorldGravity()), vec3(), false)
        end

        if currentaltitude > targetAltitude then
            up_down_switch = 1
            targetVelocity = (up_down_switch * math.abs(targetSpeed) / 3.6) * worldVertical
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
    elseif (lateralCommandType == axisCommandType.byTargetSpeed) then
        local lateralAcceleration = Nav.axisCommandManager:composeAxisAccelerationFromTargetSpeed(axisCommandId.lateral)
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

function script.onUpdate()
    --system.print("hor" ..Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal))
    --system.print("vert" .. Nav.axisCommandManager:getThrottleCommand(axisCommandId.vertical))

    current_max = 0
    currentvert_max = 0

    if vSpeedSigned == nil then
        vSpeed_hud = 0
    else
        vSpeed_hud = round(vSpeedSigned * 3.6, 0)
    end

    if vert_engine.getMaxThrust() == nil then
        currentvert_max = 0
    else
        currentvert_max = vert_engine.getMaxThrust()
    end

    currentvert = round(vert_engine.getThrust() / currentvert_max, 2) * 100

    currentthrust = round(Nav.axisCommandManager:getThrottleCommand(axisCommandId.longitudinal) * 100, 2)

    local thrustbarneg = false

    if currentthrust < 0 then
        thrustbarneg = true
    end

    if currentaltitude == nil then
        currentaltitude = 0
    end

    currentaltitude = round(currentaltitude, 2)
    targetAltitude = round(targetAltitude, 2)
    initialAlt = round(initialAlt, 2)

    deltaheight =
        round(
        math.min(math.abs(currentaltitude), math.abs(targetAltitude)) /
            math.max(math.abs(currentaltitude), math.abs(targetAltitude)),
        2
    ) * 100

    teledown = round(tele_down.getDistance(), 0)

    if startPositionAngle == nil then
        startPositionAngle = 0
    end

    local autolevel = ternary(level, '<div class="on"></div>', '<div class="off"></div>')

    local isflipped = ternary(flip, '<div class="on"></div>', '<div class="off"></div>')

    local isautoalt = ternary(autoalt, '<div class="on"></div>', '<div class="off"></div>')

    local braketoggle = finalBrakeInput > 0

    local finalBrakeInputHud = ternary(braketoggle, '<div class="on"></div>', '<div class="off"></div>')

    local thrustbarcolor = "#2cb6d1"
    if thrustbarneg then
        thrustbarcolor = "#F7901E"
    else
    end

    html =
        [[
    <style>
        body {
        }
        .zen {
        display: flex;
        flex-direction: column;
        }
        .controls-hud {
        display: flex;
        flex-direction: column;
        justify-content: space-around;
        border-color: #333333;
        border-radius: 12px;
        width: 20%;
        padding: 1% 1.5%;
        overflow: none;
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
        height: 16px;
        border-radius: 10px;
        }
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

        </style>
        <div class="zen">
        <div class="controls-hud">
            <div class="control-container">
            <p>Distance to Ground</p>
            ]] ..
                                                teledown ..
                                                    [[ m
            </div>
            <div class="control-container">
            <p>Vertical Speed</p>
            ]] ..
                                                        vSpeed_hud ..
                                                            [[ km/h
            </div>

            <div class="control-container">
            <p>Braking</p>
            ]] ..
                                                                finalBrakeInputHud ..
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
                <p>Target Alt</p>
                ]] ..
                                                                                        targetAltitude ..
                                                                                            " m" ..
                                                                                                [[
            </div>
            <div class="control-container">
                <p>Current Alt</p>
                ]] ..
                                                                                                    currentaltitude ..
                                                                                                        " m" ..
                                                                                                            [[
            </div>
            <div class="control-container">
                <p>Base Alt</p>
                ]] ..
                                                                                                                initialAlt ..
                                                                                                                    " m" ..
                                                                                                                        [[
            </div>
        </div>
        </div>
        <div class="zen">
            <div class="controls-hud">
                <p>Horizontal Thrust</p>
                    <div id="horizontal">
                        <div>]] ..
                                                                                                                            currentthrust ..
                                                                                                                                " %" ..
                                                                                                                                    [[</div>
                    </div>
                <p>Vertical Thrust</p>
                    <div id="vertical">
                        <div>]] ..
                                                                                                                                        currentvert ..
                                                                                                                                            " %" ..
                                                                                                                                                [[</div>
                    </div>
                    <p>Height Reached</p>
                    <div id="alt_diff">
                <div>]] ..
                                                                                                                                                    deltaheight ..
                                                                                                                                                        " %" ..
                                                                                                                                                            [[</div>                
            </div>

        </div>  
        </div>

    ]]

    system.setScreen(html)
    system.showScreen(1)
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

    if command == "/goto" then
        if arguement == nil or arguement == "" or string.find(arguement, "::") == nil then
            msgText = "Usage: /goto ::pos{0,2,46.4596,-155.1799,22.6572}"
            return
        end
        i = string.find(arguement, "::")
        local pos = string.sub(arguement, i)
        local num = " *([+-]?%d+%.?%d*e?[+-]?%d*)"
        local posPattern = "::pos{" .. num .. "," .. num .. "," .. num .. "," .. num .. "," .. num .. "}"
        local systemId, bodyId, latitude, longitude, altitude = string.match(pos, posPattern)
        local planet = atlas[tonumber(systemId)][tonumber(bodyId)].name
        system.print("planet:" .. planet .. " lat: " .. latitude .. " lon: " .. longitude .. " alt: " .. altitude)
        targetPos = vec3(convertToWorldCoordinates(pos))
        currentPos = vec3(core.getConstructWorldPos())

        system.print(currentPos:__tostring())
        system.print(targetPos:__tostring())
        atan2 = currentPos:angle_between(targetPos)
        system.print("angle:" .. atan2)
        -- distance = (vec3(core.getConstructWorldPos()) - targetPos):len()
        distance = (vec3(core.getConstructWorldPos()) - targetPos):len()
        system.print("distance:" .. distance)
    end
end

function script.onActionStart(action)
    if action == "forward" then
        pitchInput = pitchInput - 1
    elseif action == "backward" then
        pitchInput = pitchInput + 1
    elseif action == "left" then
        rollInput = rollInput - 1
    elseif action == "right" then
        rollInput = rollInput + 1
    elseif action == "yawright" then
        yawInput = yawInput - 1
    elseif action == "yawleft" then
        yawInput = yawInput + 1
    elseif action == "straferight" then
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, 1.0)
    elseif action == "strafeleft" then
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.lateral, -1.0)
    elseif action == "up" then
        upAmount = upAmount + 1
        Nav.axisCommandManager:deactivateGroundEngineAltitudeStabilization()
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.vertical, 1.0)
    elseif action == "down" then
        upAmount = upAmount - 1
        Nav.axisCommandManager:deactivateGroundEngineAltitudeStabilization()
        Nav.axisCommandManager:updateCommandFromActionStart(axisCommandId.vertical, -1.0)
    elseif action == "option1" then
        IncrementAutopilotTargetIndex()
        toggleView = false
    elseif action == "option2" then
        DecrementAutopilotTargetIndex()
        toggleView = false
    end
end

function script.onActionStop(action)
    if action == "forward" then
        pitchInput = 0
    elseif action == "backward" then
        pitchInput = 0
    elseif action == "left" then
        rollInput = 0
    elseif action == "right" then
        rollInput = 0
    elseif action == "yawright" then
        yawInput = 0
    elseif action == "yawleft" then
        yawInput = 0
    elseif action == "straferight" then
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.lateral, -1.0)
    elseif action == "strafeleft" then
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.lateral, 1.0)
    elseif action == "up" then
        upAmount = 0
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.vertical, -1.0)
        Nav.axisCommandManager:activateGroundEngineAltitudeStabilization(currentGroundAltitudeStabilization)
        Nav:setEngineForceCommand("hover", vec3(), 1)
    elseif action == "down" then
        upAmount = 0
        Nav.axisCommandManager:updateCommandFromActionStop(axisCommandId.vertical, 1.0)
        Nav.axisCommandManager:activateGroundEngineAltitudeStabilization(currentGroundAltitudeStabilization)
        Nav:setEngineForceCommand("hover", vec3(), 1)
    end
end

script.onStart()
