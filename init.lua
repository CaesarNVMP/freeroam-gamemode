------------------------------------------------
-- Free roam server main file.
------------------------------------------------
SERVER:SetSetting("cl_disablesaving",  "1"); -- No saving in free-roam.
SERVER:SetSetting("cl_disablequests",  "1");
SERVER:SetSetting("sv_enablefactions", "1");

local core = require("util/core");

-- Game commands
require("util/commands/player");
require("util/commands/gamemaster");
require("util/commands/developer");

-- Freeroam modules
SERVER.Bases     = nil;
SERVER.Database  = nil;
SERVER.DBInfo    = nil;
SERVER.Inventory = nil;

function SERVER:Init()
	SERVER.DBInfo = require("gamemodes/freeroam/database_config"); -- See database_config.lua.example
	SERVER.Database = SERVER:CreateDatabase();
	SERVER.Database:Connect( SERVER.DBInfo.hostname, SERVER.DBInfo.port, SERVER.DBInfo.user, SERVER.DBInfo.pass ); 

	-- Connect to Victor
	if (not(SERVER.Database:IsConnected())) then
		error("Database connection failed.");
		return;
	else
		print("Remote database connected!");
	end

	SERVER.Bases = require("gamemodes/freeroam/base_manager");
	SERVER.Bases:Load( SERVER.Database );

	SERVER.Inventory = require("gamemodes/Freeroam/inventory_manager");
	SERVER.Inventory:Load( SERVER.Database );
end

function SERVER:OnPlayerJoin(player)
	-- Send base list.
	SERVER.Bases:SendBaseList( player );

	-- Send welcome message.
	local welcome_message;
	local minutes = player:GetDataNumber("game_minutes");
	local game_time = nil;
	
	if minutes ~= nil and minutes > 0 then
		welcome_message = "Welcome back, ";
		
		if (minutes < 60) then
			game_time = math.round( minutes ) .. " minutes";
		elseif (minutes < 60 * 24) then
			game_time = math.round( minutes / 60, 2) .. " hours";
		else 
			game_time = math.round( minutes  / 60 / 24, 2) .. " days";
		end
	else
		welcome_message = "Welcome to NV:MP, ";
		game_time = "0 hours";
	end


	player:SendSystemMessage("--" .. welcome_message .. player:GetName() .. "!");

	if game_time ~= nil then
		player:SendSystemMessage("---Current gametime is " .. game_time);
	end
end

function SERVER:OnPlayerLeave(player)
	if (player:GetDataNumber("ForumID") == nil) then
		return;
	end

	SERVER.Inventory:SaveUserInventory( player );
end

function SERVER:SendPlayerToDefaultSpawn( player )
	player:SetExteriorCell( core.WORLDSPACE_WASTELANDNV, -17, 0,  -67833.554688, 3067.737793, 8355.847656 );
end

function SERVER:SendPlayerToSpawn( player )
	-- Send to faction spawn or default spawn.
	local fid        = player:GetDataNumber("ForumID");
	local faction_id = player:GetDataNumber("FactionID");
	
	-- Send to goodsprings.
	if (faction_id == 0) then
		self:SendPlayerToDefaultSpawn( player );
		return;
	end

	-- Load faction spawn point
	local base = SERVER.Bases:GetFactionSpawnBase(faction_id);
	print("Loading faction base spawn point...");

	if (base == nil) then
		warn("No bases found for faction, sending to default spawn.");
		self:SendPlayerToDefaultSpawn( player );
		return;
	end

	local spawn_cell = base:GetSpawnCell();
	local spawn_zone, world_x, world_y, spawn_x, spawn_y, spawn_z = base:GetSpawnPos();

	if (spawn_cell:len() ~= 0) then
		print("Moving to interior cell...");
		player:SetInteriorCell(spawn_cell, spawn_x, spawn_y, spawn_z);				
	else
		print("Moving to eterior cell...");
		player:SetExteriorCell(spawn_zone, world_x, world_y, spawn_x, spawn_y, spawn_z);
	end
end

function SERVER:OnPlayerRequestSpawn(player)
	print("OnPlayerRequestSpawn called (freshie/respawned).");

	-- Load temporary backpack they used on the server.
		-- if this is their first load, or they were dead (bug, TODO), load the starting backpack.
	SERVER.Inventory:LoadUserKit( player );

	--for k, v in pairs( server_backpack ) do
	--	player:GiveItem( k, v["count"] ); -- , v["health"] -- TODO
	--
	--	if (v["equipped"]) then
	--		player:EquipItem( k );
	--	end
	--end

	self:SendPlayerToSpawn( player );
end

function SERVER:OnPlayerSpawn(player)
	print("OnPlayerSpawn called (load db).");

	-- Load inventory data.
	SERVER.Inventory:LoadUserInventory( player );

	-- Load positional data.
	local exterior_x = player:GetDataNumber("exteriorx");
	local exterior_y = player:GetDataNumber("exteriory");
	local exterior_z = player:GetDataNumber("exteriorz");
	local cellid = player:GetDataString("cellid");

	local pos_x = player:GetDataNumber("posx");
	local pos_y = player:GetDataNumber("posy");
	local pos_z = player:GetDataNumber("posz");

	local is_in_exterior = (exterior_z ~= 0);
	local send_to_spawn = false;

	-- Make sure the exterior/interior data is valid, else
	-- send them to spawn.
	if (not is_in_exterior) then
		if (cellid == nil or cellid:len() == 0) then
			warn("Player interior cell is blank.");
			send_to_spawn = true;
		end
	end

	-- Send them to spawn if something broke.
	if (send_to_spawn) then
		player:SendSystemMessage("Sorry, your location data seems to be corrupt. We're sending you to your spawn location to fix this. ");
		self:SendPlayerToSpawn( player );
		return;
	end

	-- Put them back where they last logged off.
	if (is_in_exterior) then
		player:SetExteriorCell( exterior_z, exterior_x, exterior_y, 
			pos_x, pos_y, pos_z );
	else
		player:SetInteriorCell( cellid, pos_x, pos_y, pos_z );
	end
end