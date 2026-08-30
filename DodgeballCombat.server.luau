
-- This is the main dodgeball server script.

local players = game:GetService("players")
local replicatedStorage = game:GetService("replicatedStorage")
local serverStorage = game:GetService("serverStorage")
local runService = game:GetService("runService")
local tweenService = game:GetService("tweenService")
local debris = game:GetService("debris")
local character = script.Parent
local humanoid: Humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local ballsFolder = workspace:WaitForChild("Balls")
local applyBallSkin = require(replicatedStorage.applyBallSkin)
local plr = players:GetPlayerFromCharacter(character)
local animationName = plr.stats:WaitForChild("animation")
local perk = plr.stats.perk.Value
local overcharge = perk == "overcharge"
local animations = replicatedStorage.shopItems.animations
local animationPack = animations:FindFirstChild(animationName.Value)
if animationPack then
	for i, v in pairs(animationPack.ball:GetChildren()) do
		v:Clone().Parent = script
	end
end
local ragdoll = require(replicatedStorage.ragdoll)
local oldFightEvent = character:FindFirstChild("FightEvent")
if oldFightEvent then
	oldFightEvent:Destroy()
end
local speedTag = Instance.new("NumberValue")
speedTag.Parent = character
speedTag.Value = 30
speedTag.Name = "speedTag"
local remote = Instance.new("RemoteEvent")
remote.Name = "FightEvent"
remote.Parent = character
local getMouse = Instance.new("RemoteFunction")
getMouse.Name = "MouseRemote"
getMouse.Parent = character
local chargeMeterEvent =
	replicatedStorage:FindFirstChild("ChargeMeterEvent")
if not chargeMeterEvent then
	chargeMeterEvent = Instance.new("RemoteEvent")
	chargeMeterEvent.Name = "ChargeMeterEvent"
	chargeMeterEvent.Parent = replicatedStorage
end
local meterClientReady = false
local grab = script:WaitForChild("PickUp"):Clone()
grab.Parent = rootPart
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end
local hold = animator:LoadAnimation(
	script:WaitForChild("HoldAnim")
)
local charge = animator:LoadAnimation(
	script:WaitForChild("ChargeAnim")
)
local throw = animator:LoadAnimation(
	script:WaitForChild("ThrowAnim")
)
local overchargeAnim = animator:LoadAnimation(
	script:WaitForChild("overcharge")
)
hold.Priority = Enum.AnimationPriority.Action2
charge.Priority = Enum.AnimationPriority.Action2
throw.Priority = Enum.AnimationPriority.Action2
local hitbox = serverStorage:WaitForChild("Hitbox"):Clone()
hitbox.Parent = character
hitbox.Position = rootPart.Position
local hitboxWeld = Instance.new("WeldConstraint")
hitboxWeld.Part0 = hitbox
hitboxWeld.Part1 = rootPart
hitboxWeld.Parent = hitbox
local shotSound = script:WaitForChild("Shot"):Clone()
local powerShotSound = script:WaitForChild("PowerShot"):Clone()
shotSound.Parent = rootPart
powerShotSound.Parent = rootPart
local holdCharge = 0
local charging = false
local chargeSlowdown = 0
local chargeStartedAt = 0
local overchargeTimer = time()
local overchargeStarted = false
local chargeDelay = 0.5
local chargeTime = 2.5
if perk then
	if perk == "overcharge" then
		chargeTime =  3.125
	end
end
local meterUpdateRate = 1 / 20
local lastMeterUpdate = 0
local redFireAdded = false
local blueFireAdded = false
local minimumThrowSpeed = 150
local maximumThrowSpeed = 300
local minimumPlayerDamage = 5
local maximumPlayerDamage = 55
local minimumNpcDamage = 25
local maximumNpcDamage = 75
local impactEffectLifetime = 2
local function prepareStarPart(starPart)
	starPart.Anchored = false
	starPart.CanCollide = false
	starPart.CanTouch = false
	starPart.CanQuery = false
	starPart.Massless = true
end
local function spawnShotStar(ball, throwCharge)
	if not ball then
		return nil
	end
	local templateName = nil
	if overcharge then
		if throwCharge >= 1 then
			templateName = "GreenStar"
		elseif throwCharge >= 0.8 then
			templateName = "BlueStar"
		elseif throwCharge >= 0.4 then
			templateName = "RedStar"
		else
			return nil
		end
	else
		if throwCharge >= 1 then
			templateName = "BlueStar"
		elseif throwCharge >= 0.5 then
			templateName = "RedStar"
		else
			return nil
		end
	end
	local template = replicatedStorage:FindFirstChild(templateName)
	if not template then
		warn(templateName .. " is missing from replicatedStorage")
		return nil
	end
	local star = template:Clone()
	star.Name = templateName .. "ShotEffect"
	if star:IsA("Attachment") then
		star.Parent = ball
	elseif star:IsA("ParticleEmitter") then
		local attachment = Instance.new("Attachment")
		attachment.Name = templateName .. "ShotAttachment"
		attachment.Parent = ball
		star.Parent = attachment
		star:Emit(math.max(star:GetAttribute("EmitCount") or 12, 1))
		return attachment
	elseif star:IsA("BasePart") then
		prepareStarPart(star)
		star.CFrame = ball.CFrame
		star.Parent = workspace
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ball
		weld.Part1 = star
		weld.Parent = star
	elseif star:IsA("Model") then
		star.Parent = workspace
		star:PivotTo(ball.CFrame)
		for _, object in ipairs(star:GetDescendants()) do
			if object:IsA("BasePart") then
				prepareStarPart(object)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = ball
				weld.Part1 = object
				weld.Parent = object
			end
		end
	else
		star.Parent = ball
	end
	for _, object in ipairs(star:GetDescendants()) do
		if object:IsA("ParticleEmitter") then
			local emitCount = object:GetAttribute("EmitCount")
			if emitCount then
				object:Emit(math.max(emitCount, 1))
			end
		end
	end
	return star
end
local function getOwner()
	return players:GetPlayerFromCharacter(character)
end
local function getHeldBall()
	local ball = character:FindFirstChild("Ball")
	if ball and ball:IsA("BasePart") then
		return ball
	end
	return nil
end
local function sendMeter(player, action, value)
	if not meterClientReady then
		return
	end
	if not player or player.Parent ~= players then
		return
	end
	chargeMeterEvent:FireClient(
		player,
		action,
		value
	)
end
chargeMeterEvent.OnServerEvent:Connect(function(player, action)
	if player.Character ~= character then
		return
	end
	if action == "Ready" then
		meterClientReady = true
		chargeMeterEvent:FireClient(player, "ReadyAck", true)
		if charging then
			chargeMeterEvent:FireClient(player, "Start", holdCharge)
			chargeMeterEvent:FireClient(player, "Update", holdCharge)
		end
	end
end)
local function collectFadeObjects(container)
	local objects = {}
	for _, object in ipairs(container:GetDescendants()) do
		if object:IsA("ParticleEmitter") then
			table.insert(objects, {
				object = object,
				property = "Rate",
				value = object.Rate
			})
		elseif object:IsA("Fire") then
			table.insert(objects, {
				object = object,
				property = "Size",
				value = object.Size
			})
			table.insert(objects, {
				object = object,
				property = "Heat",
				value = object.Heat
			})
		elseif object:IsA("PointLight")
			or object:IsA("SpotLight")
			or object:IsA("SurfaceLight") then
			table.insert(objects, {
				object = object,
				property = "Brightness",
				value = object.Brightness
			})
		end
	end
	if container:IsA("ParticleEmitter") then
		table.insert(objects, {
			object = container,
			property = "Rate",
			value = container.Rate
		})
	elseif container:IsA("Fire") then
		table.insert(objects, {
			object = container,
			property = "Size",
			value = container.Size
		})
		table.insert(objects, {
			object = container,
			property = "Heat",
			value = container.Heat
		})
	end
	return objects
end
local function fadeEffectIn(container, duration)
	local objects = collectFadeObjects(container)
	for _, data in ipairs(objects) do
		data.object[data.property] = 0
		tweenService:Create(
			data.object,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				[data.property] = data.value
			}
		):Play()
	end
end
local function fadeEffectOut(container, duration)
	if not container then
		return
	end
	for _, data in ipairs(collectFadeObjects(container)) do
		tweenService:Create(
			data.object,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			),
			{
				[data.property] = 0
			}
		):Play()
	end
	task.delay(duration, function()
		if container and container.Parent then
			container:Destroy()
		end
	end)
end
local function removeRedFire(ball)
	if not ball then
		return
	end
	local redFire = ball:FindFirstChild("ChargeFire")
	if redFire then
		redFire:Destroy()
	end
end
local function removeBlueFire(ball)
	if not ball then
		return
	end
	local blueFire = ball:FindFirstChild("BlueChargeFire")
	if blueFire then
		blueFire:Destroy()
	end
end
local function removeAllChargeFire(ball)
	removeRedFire(ball)
	removeBlueFire(ball)
end
local function addRedFire(ball)
	if not ball then
		return
	end
	if ball:FindFirstChild("ChargeFire") then
		return
	end
	local fireTemplate =
		replicatedStorage:FindFirstChild("Fire")
	if not fireTemplate then
		warn("Fire is missing from replicatedStorage")
		return
	end
	local redFire = fireTemplate:Clone()
	redFire.Name = "ChargeFire"
	redFire.Parent = ball
	fadeEffectIn(redFire, 0.3)
end
local function addBlueFire(ball)
	if not ball then
		return
	end
	if ball:FindFirstChild("BlueChargeFire") then
		return
	end
	local blueFireTemplate =
		replicatedStorage:FindFirstChild("BlueFire")
	if not blueFireTemplate then
		warn("BlueFire is missing from replicatedStorage")
		return
	end
	local blueFire = blueFireTemplate:Clone()
	blueFire.Name = "BlueChargeFire"
	blueFire.Parent = ball
	fadeEffectIn(blueFire, 0.35)
	local redFire = ball:FindFirstChild("ChargeFire")
	if redFire then
		fadeEffectOut(redFire, 0.35)
	end
end
local function resetCharging(player, removeFire)
	charging = false
	holdCharge = 0
	chargeStartedAt = 0
	lastMeterUpdate = 0
	redFireAdded = false
	blueFireAdded = false
	sendMeter(player, "Stop", 0)
	if removeFire then
		removeAllChargeFire(getHeldBall())
	end
end
local function releaseBall(ball)
	if not ball then
		return
	end
	local ballWeld = ball:FindFirstChild("BallWeld")
		or ball:FindFirstChildOfClass("WeldConstraint")
	if ballWeld then
		ballWeld:Destroy()
	end
	ball.Parent = ballsFolder
	ball.CanCollide = true
	ball.CanTouch = true
	ball.CanQuery = true
	local throwable = ball:FindFirstChild("Throwable")
	if throwable then
		throwable.Value = true
	end
end
humanoid.Died:Connect(function()
	local player = getOwner()
	local ball = getHeldBall()
	if ball then
		removeAllChargeFire(ball)
		releaseBall(ball)
	end
	resetCharging(player, false)
end)
local chargeRequestId = 0
local function beginCharging(player)
	if charging or humanoid.Health <= 0 then
		return false
	end
	local ball = getHeldBall()
	if not ball then
		return false
	end
	charging = true
	holdCharge = 0
	chargeStartedAt = os.clock()
	lastMeterUpdate = 0
	overchargeStarted = false
	redFireAdded = false
	blueFireAdded = false
	removeAllChargeFire(ball)
	sendMeter(player, "Start", holdCharge)
	sendMeter(player, "Update", holdCharge)
	hold:Stop()
	charge:Play()
	return true
end
local function queueChargeUntilBallIsHeld(player)
	chargeRequestId += 1
	local thisRequestId = chargeRequestId
	task.spawn(function()
		local deadline = os.clock() + 0.75
		repeat
			if thisRequestId ~= chargeRequestId then
				return
			end
			if player.Character ~= character or humanoid.Health <= 0 then
				return
			end
			if beginCharging(player) then
				return
			end
			task.wait()
		until os.clock() >= deadline
	end)
end
local function throwBall(player, val1, ve)
	chargeRequestId += 1
	local ball = getHeldBall()
	if not ball then
		resetCharging(player, false)
		return
	end
	if typeof(val1) ~= "CFrame" then
		return
	end
	local mul = (overcharge and 5 or 4) / 4
	local mul2 = 4/(overcharge and 5 or 4)
	local throwCharge = math.clamp(holdCharge * mul, 0, 1 * mul)
	charging = false
	sendMeter(player, "Stop", 0)
	hold:Stop()
	charge:Stop()
	throw:Play()
	if throwCharge >= 0.5*mul2 then
		powerShotSound:Play()
		local fovTag = Instance.new("NumberValue")
		fovTag.Name = "fovTag"
		fovTag.Value = 60
		fovTag.Parent = character
		chargeSlowdown = throwCharge*0.5
		debris:AddItem(fovTag, throwCharge*0.5)
	else
		shotSound:Play()
	end
	if ball:FindFirstChild("throwSound") then
		ball.throwSound:Play()
	end
	ball.Parent = ballsFolder
	local ballWeld = ball:FindFirstChild("BallWeld")
		or ball:FindFirstChildOfClass("WeldConstraint")
	if ballWeld then
		ballWeld:Destroy()
	end
	ball.CanCollide = true
	ball.CanTouch = true
	ball.CanQuery = true
	ball.Position = rootPart.Position
		+ Vector3.new(0, 0.5, 0)
	if ball:FindFirstChild("skin") then
		ball.skin:PivotTo(ball.CFrame)
	end
	local shotStar = spawnShotStar(ball, throwCharge)
	local throwSpeed = minimumThrowSpeed
		+ ((maximumThrowSpeed - minimumThrowSpeed) * throwCharge)
	ball.CanCollide = false
	local velocity = Instance.new("BodyVelocity")
	velocity.Name = "ThrowVelocity"
	velocity.Velocity = val1.LookVector * throwSpeed
	velocity.MaxForce = Vector3.new(100000, 100000, 100000)
	velocity.P = 100000
	velocity.Parent = ball
	pcall(function()
		ball:SetNetworkOwner(player)
	end)
	local noCollisionConstraints = {}
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart")
			and object.CanCollide then
			local constraint =
				Instance.new("NoCollisionConstraint")
			constraint.Part0 = object
			constraint.Part1 = ball
			constraint.Parent = object
			table.insert(
				noCollisionConstraints,
				constraint
			)
		end
	end
	ball.CanCollide = true
	debris:AddItem(velocity, 0.12)
	holdCharge = 0
	chargeStartedAt = 0
	lastMeterUpdate = 0
	redFireAdded = false
	blueFireAdded = false
	local hitInstance = nil
	local throwStarted = os.clock()
	local touchConnection = ball.Touched:Connect(function(touchedPart)
		if touchedPart:IsDescendantOf(character)
			or touchedPart:IsDescendantOf(ballsFolder)
			or touchedPart == ball then
			return
		end
		if touchedPart.CanQuery then
			hitInstance = touchedPart
		end
	end)
	ball.Size = Vector3.new(1.6,1.6,1.6)
	repeat
		local movement = ball.AssemblyLinearVelocity * 0.06
		if movement.Magnitude < 0.01 then
			movement = val1.LookVector * 0.1
		end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {
			character,
			ball,
			ballsFolder
		}
		local result = workspace:Spherecast(
			ball.Position,
			overcharge and throwCharge >= 1.23 and 0.5 or 1.1,
			movement,
			rayParams
		)
		if result then
			hitInstance = result.Instance
		end
		task.wait()
	until hitInstance
		or os.clock() - throwStarted >= 5
		or not ball.Parent
	if not ball.Parent then
		if shotStar and shotStar.Parent then
			shotStar:Destroy()
		end
		return
	end
	ball.Size = Vector3.new(2,2,2)
	if shotStar and shotStar.Parent then
		shotStar:Destroy()
		shotStar = nil
	end
	for _, constraint in ipairs(
		noCollisionConstraints
		) do
		constraint:Destroy()
	end
	ball.CanCollide = true
	local hit = script:WaitForChild("Hit"):Clone()
	local playerDamage = minimumPlayerDamage + ((maximumPlayerDamage - minimumPlayerDamage) * throwCharge)
	local npcDamage = minimumNpcDamage + ((maximumNpcDamage - minimumNpcDamage) * throwCharge)
	if hitInstance then
		if hitInstance:HasTag("hittable") then
			local hitEvent = hitInstance:FindFirstChildOfClass("BindableEvent")
			if hitEvent then
				if not hitInstance:GetAttribute("requirement") or hitInstance:GetAttribute("requirement") == player.stats.skin.Value then
					hitEvent:Fire(player, throwCharge)
				end
			end
		end
		local hitCharacter =
			hitInstance:FindFirstAncestorOfClass("Model")
		local hitHumanoid = hitCharacter
			and hitCharacter:FindFirstChildOfClass(
				"Humanoid"
			)
		if hitHumanoid
			and hitCharacter ~= character then
			if throwCharge >= 0.5 and not godThrow and not aimbotThrow then
				local critical =
					script:WaitForChild("Critical"):Clone()
				critical.Parent = ball
				critical:Play()
				local hitHrp = hitCharacter:FindFirstChild("HumanoidRootPart")
				if hitHrp then
					local velocity = Instance.new("BodyVelocity")
					velocity.Velocity = ball.AssemblyLinearVelocity.Unit*(80+40*throwCharge) + Vector3.new(0,40,0)
					velocity.MaxForce = Vector3.new(1,1,1) * 10000
					velocity.P = 10000
					velocity.Parent = hitHrp
					debris:AddItem(velocity, 0.12)
				end
				task.defer(function()
					ragdoll.ragdoll(hitCharacter, 0.5)
				end)
				debris:AddItem(critical, 3)
			end
			if hitCharacter:GetAttribute("vulnerable") then
				task.defer(function()
					hitCharacter:SetAttribute("cancel", true)
					ragdoll.ragdoll(hitCharacter, 1.5)
				end)
			end
			local hitPlayer =
				players:GetPlayerFromCharacter(
					hitCharacter
				)
			local throwDistance = (
				rootPart.Position - ball.Position
			).Magnitude
			if hitPlayer then
				local pvp =
					workspace:FindFirstChild("pvp")
				if pvp and pvp.Value then
					local distanceDamage = math.clamp(
						math.round(
							throwDistance * 0.75
						),
						0,
						40
					)
					hitHumanoid:TakeDamage(
						(overcharge and throwCharge >= 1.25) and
							9999
							or
							math.round(
								playerDamage
								+ distanceDamage
							)
					)
					hit:Play()
					local hits =
						player:FindFirstChild("hits")
					local score =
						player:FindFirstChild("score")
					if hits then
						hits.Value += 1
					end
					if score and hitPlayer then
						score.Value += math.round(
							throwDistance / 2
						)
					end
					local oldKillTag =
						hitCharacter:FindFirstChild(
							"killTag"
						)
					if oldKillTag then
						oldKillTag:Destroy()
					end
					local killTag =
						Instance.new("ObjectValue")
					killTag.Name = "killTag"
					killTag.Value = player
					killTag.Parent = hitCharacter
					debris:AddItem(killTag, 3)
					local hitEvent =
						replicatedStorage:FindFirstChild(
							"HitEvent"
						)
					if hitEvent then
						hitEvent:FireClient(player)
					end
				end
			else
				hitHumanoid:TakeDamage(
					(overcharge and throwCharge >= 1.25) and
						9999
						or
						math.round(npcDamage)
				)
				hit:Play()
				local hits =
					player:FindFirstChild("hits")
				local score =
					player:FindFirstChild("score")
				if hits then
					hits.Value += 1
				end
				if score then
					score.Value += math.round(
						throwDistance / 2
					)
				end
				local hitEvent =
					replicatedStorage:FindFirstChild(
						"HitEvent"
					)
				if hitEvent then
					hitEvent:FireClient(player)
				end
			end
		end
	end
	local particleTemplate =
		serverStorage:FindFirstChild("Particle")
	if particleTemplate then
		local particle = particleTemplate:Clone()
		particle.Position = ball.Position
		particle.Parent = workspace
		task.wait(0.01)
		local attachment =
			particle:FindFirstChild("Attachment")
		if attachment then
			local mul = 4/(overcharge and 5 or 4)
			if throwCharge >= 1*mul then
				local smoke =
					attachment:FindFirstChild("Smoke3")
				local circle =
					attachment:FindFirstChild("Circle3")
				local fx =
					attachment:FindFirstChild("FX3")
				if smoke then
					smoke:Emit(10)
				end
				if circle then
					circle:Emit(2)
				end
				if fx then
					fx:Emit(2)
				end
			elseif throwCharge >= 0.5*mul then
				local smoke =
					attachment:FindFirstChild("Smoke2")
				local circle =
					attachment:FindFirstChild("Circle2")
				if smoke then
					smoke:Emit(10)
				end
				if circle then
					circle:Emit(2)
				end
			else
				local smoke =
					attachment:FindFirstChild("Smoke")
				local circle =
					attachment:FindFirstChild("Circle")
				if smoke then
					smoke:Emit(10)
				end
				if circle then
					circle:Emit(2)
				end
			end
		end
		debris:AddItem(particle, impactEffectLifetime)
	end
	ball.Boing:Play()
	removeAllChargeFire(ball)
	local throwable =
		ball:FindFirstChild("Throwable")
	if throwable then
		throwable.Value = true
	end
	if touchConnection then
		touchConnection:Disconnect()
	end
	debris:AddItem(hit, 2)
end
remote.OnServerEvent:Connect(function(player, val1, ve)
	if humanoid.Health <= 0 then
		return
	end
	if player.Character ~= character then
		return
	end
	if player.Name ~= character.Name then
		return
	end
	if ve == 1 then
		if getHeldBall() then
			return
		end
		local arm = character:FindFirstChild("Right Arm")
			or character:FindFirstChild("RightHand")
		if not arm then
			return
		end
		local range = 10
		local nearestBall = nil
		for _, ball in ipairs(ballsFolder:GetChildren()) do
			if ball:IsA("BasePart") then
				local throwable =
					ball:FindFirstChild("Throwable")
				if throwable and throwable.Value then
					local distance =
						(ball.Position - arm.Position).Magnitude
					if distance < range then
						nearestBall = ball
						range = distance
					end
				end
			end
		end
		if nearestBall then
			resetCharging(player, false)
			removeAllChargeFire(nearestBall)
			nearestBall.Anchored = false
			nearestBall.CanCollide = false
			nearestBall.CanTouch = false
			grab:Play()
			hold:Play()
			nearestBall.Parent = character
			local throwable =
				nearestBall:FindFirstChild("Throwable")
			if throwable then
				throwable.Value = false
			end
			nearestBall.CFrame = CFrame.new(
				arm.Position - arm.CFrame.UpVector
			)
			local ballWeld = Instance.new("WeldConstraint")
			ballWeld.Name = "BallWeld"
			ballWeld.Part0 = nearestBall
			ballWeld.Part1 = arm
			ballWeld.Parent = nearestBall
			applyBallSkin.applyBallSkin(nearestBall, replicatedStorage.shopItems.skins:FindFirstChild(player.stats.skin.Value))
		end
	elseif ve == 2 then
		if charging then
			return
		end
		if not beginCharging(player) then
			queueChargeUntilBallIsHeld(player)
		end
	elseif ve == 3 then
		if not overcharge or holdCharge < 1 then
			throwBall(player, val1, ve)
		end
	end
end)
for _, object in ipairs(character:GetDescendants()) do
	if object:IsA("BasePart") then
		object.CollisionGroup = "Player"
		if object.Parent ~= character then
			object.CanCollide = false
			object.CanQuery = false
			object.CanTouch = false
			object.Massless = true
		end
	end
end
runService.Heartbeat:Connect(function(deltaTime)
	if overchargeStarted then
		character:SetAttribute("vulnerable", true)
		humanoid.JumpPower = 0
	else
		character:SetAttribute("vulnerable", false)
		humanoid.JumpPower = 50
	end
	if chargeSlowdown > 0 then
		chargeSlowdown -= deltaTime
		speedTag.Value = -10
	elseif charging then
		speedTag.Value = overcharge and (holdCharge >= 1 and -100 or -holdCharge*18) or -holdCharge*12
	else
		speedTag.Value = 0
	end
	if not charging then
		return
	end
	local ball = getHeldBall()
	local player = getOwner()
	if not ball or not player then
		resetCharging(player, true)
		return
	end
		sendMeter(player, "Update", 1)
		return
	end
	local heldTime = os.clock() - chargeStartedAt
	if heldTime < chargeDelay then
		return
	end
	holdCharge = math.clamp(
		holdCharge + deltaTime / chargeTime,
		0,
		1
	)
	local currentTime = os.clock()
	if currentTime - lastMeterUpdate
		>= meterUpdateRate then
		lastMeterUpdate = currentTime
		sendMeter(
			player,
			"Update",
			holdCharge
		)
	end
	if overcharge then
		if holdCharge >= 1 then
			if not overchargeStarted then
				overchargeStarted = true
				overchargeTimer = time()
				overchargeAnim:Play()
			else
				if character:GetAttribute("cancel") then
					overchargeStarted = false
					overchargeAnim:Stop()
					overchargeTimer = 0
					releaseBall()
					character:SetAttribute("cancel", false)
				end
				if time() - overchargeTimer >= 1.7 then
					local mouseLook = getMouse:InvokeClient(plr)
					if mouseLook then
						throwBall(plr, mouseLook, 3)
					end
					overchargeStarted = false
				end
			end
		end
	end
	local mul = 4/(overcharge and 5 or 4)
	if holdCharge >= 0.5*mul and not redFireAdded then
		redFireAdded = true
		addRedFire(ball)
	end
	if holdCharge >= 1*mul and not blueFireAdded then
		blueFireAdded = true
		addBlueFire(ball)
	end
end)
