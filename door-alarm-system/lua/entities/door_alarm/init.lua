AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

util.AddNetworkString("alarmMenu")

function ENT:Initialize()
	self:SetModel("models/props_lab/reciever01d.mdl")
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	self:SetMoveType(SOLID_VPHYSICS)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)
	
	self:SetNWBool("alarm_status", "")
	self:SetMaxHealth(alarm_system.settings.health.base)
	self:SetHealth(alarm_system.settings.health.base)
	
	self.alarmUpgrades = {}
	
	local phys = self:GetPhysicsObject()
	
	if phys:IsValid() then
	    phys:Wake()
	end
end

function ENT:StartTouch(ent)
    if ent:GetClass() == "prop_door_rotating" and not ent.actAlarm and ent:isMasterOwner(self:Getowning_ent()) then
		local ang = ent:GetAngles()
		local pos = ent:GetPos()
		
		if math.abs(ent:WorldToLocalAngles(self:GetAngles()).y) > 90 then
		    ang:RotateAroundAxis(ang:Up(), 180)
			self:SetPos(pos +ang:Right() * 40 +ang:Up() * 1 +ang:Forward() * -1.5)
		else
		    self:SetPos(pos +ang:Right() * -40 +ang:Up() * 1 +ang:Forward() * -1.5)
		end

		self:SetAngles(ang)
		self:SetParent(ent)
		self:EmitSound("npc/dog/dog_servo12.wav")
		
		ent.actAlarm = self
		ent.nextUse = CurTime()
	end
end

function ENT:Use(caller)
    local door = self:GetParent()
	
	if door:IsValid() and self:Getowning_ent() == caller then
		net.Start("alarmMenu")
	        net.WriteEntity(self)
		net.Send(caller)
	end
end

function ENT:OnRemove() --protection against admins removing attached door alarms.
    if self:GetParent():IsValid() then
	    self:GetParent().actAlarm = nil
	end
end

function ENT:OnTakeDamage(dmg)
	local amount = dmg:GetDamage()
	
	if table.HasValue(self.alarmUpgrades, "upgrade_armor") then
	    amount = amount *alarm_system.settings.health.armor
	end
	
	self:SetHealth(self:Health() -amount)
	
	if self:Health() <= 0 then
		local pos = self:GetPos()
        local effect = EffectData()
    
		effect:SetOrigin(pos)
        util.Effect("Explosion", effect)
	
		if self.alarmSiren then
		    self.alarmSiren:Stop()
		end
	
	    self:GetParent().actAlarm = nil
		self:Remove()
	elseif self:GetNWString("alarm_status") ~= "" then
	    self:alarmTrigger(dmg:GetAttacker())
	end
end

function ENT:alarmOff()
    if self.alarmSiren then
		self.alarmSiren:Stop()
		self.alarmSiren = nil
	end

	self:SetNWString("alarm_status", "")
	self:EmitSound("buttons/combine_button2.wav")
end

function ENT:alarmDetach()
    self:EmitSound("weapons/stunstick/alyx_stunner1.wav")
	self:SetNWString("alarm_status", "")
	self:GetParent().actAlarm = nil
	self:SetParent(nil)
	self:alarmOff()
end

function ENT:alarmTrigger(intruder)
    if intruder then
	    if intruder == self:Getowning_ent() then return end -- Prevents people setting off their own alarms.

		if table.HasValue( self.alarmUpgrades, "upgrade_tower" ) and intruder:getDarkRPVar("wanted") ~= true then
			local doorName = self:GetParent():getDoorData().title
			
			if doorName then
				reason = "Attempting to invade private property ('"..doorName.."')."
			else
				reason = "Attempting to invade private property."
			end
			
			if SpectralRP.base then
				SpectralRP.wanted(intruder, "Door Alarm System", reason)
			else
				intruder:wanted(nil, reason)
			end
	    end
	end
	
	if not self.alarmSiren then
	    self.alarmSiren = CreateSound(self, "ambient/alarms/alarm1.wav")
	    self.alarmSiren:Play()
		
        self:SetNWString("alarm_status", "Alert")
		
		local name = self:GetParent():getDoorData().title
		
		if name then
	        DarkRP.notify(self:Getowning_ent(), 1, 5, "Your alarm at '"..name.."' has been triggered!")
		else
			DarkRP.notify(self:Getowning_ent(), 1, 5, "One of your door alarms has been triggered!")
	    end
		

		
	end
end

hook.Add("PlayerDisconnected", "alarm_disconnect_explode", function(ply)
    for k, v in pairs(ents.FindByClass("door_alarm")) do
	    if v:Getowning_ent() == ply then
		    v:TakeDamage(v:Health())
		end
	end
end)

hook.Add("onDoorRamUsed", "alarm_react_ram", function(sucess, ply, tr)
    local alarm = tr.Entity.actAlarm
	
	if sucess and alarm and alarm:GetNWString("alarm_status") ~= "" then
	    alarm:alarmTrigger()
	end
end)

hook.Add("lockpickStarted", "alarm_react_lockpicking", function(ply, ent)
    local alarm = ent.actAlarm
	
	if alarm and alarm:GetNWString("alarm_status") ~= "" then
	    alarm:alarmTrigger(ply)
	end
end)

hook.Add("TFADoorShot", "alarm_react_tfa", function(ply, ent)
    local alarm = ent.actAlarm
	
	if alarm and alarm:GetNWString("alarm_status") ~= "" then
	    alarm:alarmTrigger(ply)
	end
end)

hook.Add("playerSellDoor", "alarm_sell_detach", function(ply, ent)
    if ent.actAlarm then
	    ent.actAlarm:alarmDetach()
	end
end)

hook.Add("canPocket", "alarm_disable_pickup", function(ply, ent)
    return not ent:GetClass() == "door_alarm", "You can't put this on your pocket!"
end)

net.Receive("alarmMenu", function(len, ply)
    local option = net.ReadInt(32)
	local alarm = net.ReadEntity()
	
	if alarm and alarm:Getowning_ent() == ply then
		if option == 1 then
	        alarm:alarmDetach()
	    elseif option == 2 then
		    if alarm:GetNWString("alarm_status") ~= "" then
			    alarm:alarmOff()
			else
			    alarm:SetNWString("alarm_status", "Online")
				alarm:EmitSound("buttons/combine_button1.wav")
			end 
		else
		    local calc_price = math.ceil(alarm_system.settings.price *(alarm:GetMaxHealth() -alarm:Health()))
		
		    if calc_price > 0 then
		        if ply:canAfford(calc_price) then
					ply:addMoney(-calc_price)
		            alarm:SetHealth(alarm:GetMaxHealth())
				    DarkRP.notify(ply, 0, 10, "You fixed this alarm for "..DarkRP.formatMoney(calc_price)..".")
			    else
			        DarkRP.notify(ply, 1, 5, "You can't afford to fix this alarm!")
			    end
			else
			    DarkRP.notify(ply, 1, 5, "This alarm is already at max health!")
			end
		end
	end
end)