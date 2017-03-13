local base_manager =
{
	_database = nil,
	_bases    = {},
};

local core = require("util/core");
local FactionBase = require("gamemodes/freeroam/class_base");

function base_manager:GetBaseList()
	self:Dump();
	return self._bases;
end

function base_manager:FixFactionSpawns( faction_id )
	local only_base = nil;

	for i,v in pairs(self._bases) do
		if (v:GetFactionOwner() == faction_id and v:HasSpawn()) then
			if (only_base == nil) then
				only_base = v;
			else
				warn("Fixed a faction (" .. faction_id .. ") base (" .. i .. ") due to multiple spawns.");
				v:DisableSpawn();
			end
		end
	end
end

function base_manager:GetFactionSpawnBase( faction_id )
	local found_base = nil;

	-- Ensure the bases owned by the factions only have
	-- one enabled spawn.
	self:FixFactionSpawns(faction_id);
	
	for i,v in pairs(self._bases) do
		if (v:GetFactionOwner() == faction_id and v:HasSpawn()) then
			found_base = v;
			break;
		end
	end

	-- Base might have been captured, check for other bases owned by 
	-- the faction and make that the spawn location.
	-- TODO: Distance based assignment.
	if (found_base == nil) then
		for i,v in pairs(self._bases) do
			if (v:GetFactionOwner() == faction_id) then
				found_base = v;

				-- Flag the base as now being the faction's spawn location.
				v:EnableSpawn();
				break;
			end
		end
	end
	
	return found_base;
end

function base_manager:GetFactionOwnedBases( faction_id )
	local bases = {};
	
	for i,v in pairs(self._bases) do
		if (v:GetFactionOwner() == faction_id and v:HasSpawn()) then
			table.insert(bases, v);
		end
	end

	return bases;
end

function base_manager:CreateBase( display_name )
	local creation_result = self._database:Query( string.format("INSERT INTO " .. SERVER.DBInfo.db .. ".game_bases (display_name) VALUES (%q)", display_name) );

	if (not(creation_result)) then
		return nil, "Database failure on creation.";
	end
	
	-- Get the last created item ID.
	local faction_id = self._database:Query( "SELECT LAST_INSERT_ID() FROM " .. SERVER.DBInfo.db .. ".game_bases LIMIT 1", true );
	if (faction_id == nil) then
		return nil, "Database failure on returning created row.";
	end

	-- Parse the result ID from the returned rows.
	faction_id = faction_id["0"]["LAST_INSERT_ID()"];
	if (faction_id == nil) then
		return nil, "Database failure on getting last ID.";
	end

	-- Finally store the new base into the base_manager.
	local data = self._database:Query(string.format("SELECT * FROM " .. SERVER.DBInfo.db .. ".game_bases WHERE id = %d", faction_id), true);
	if (data == nil or table.length(data) == 0) then
		tprint(data);
		return nil, "Database failure on data retrieval.";
	end
	
	local base = self:_LoadBase( data["0"] );
	base:SetDisplayName( display_name );
	return base;
end

function base_manager:DeleteBase( query_id )
	query_id = tonumber( query_id );

	local existing_base = self._database:Query(string.format("SELECT id FROM " .. SERVER.DBInfo.db .. ".game_bases WHERE id = %d", query_id), true);
	if (existing_base == nil or table.length(existing_base) == 0) then
		return false, string.format("Base ID %d not found", query_id);
	end
	
	self._database:Query(string.format("DELETE FROM " .. SERVER.DBInfo.db .. ".game_bases WHERE id = %d", query_id), false);
	self:_RemoveBase(query_id);
	return true;
end

function base_manager:SendBaseList( player )
	for i,v in pairs(self._bases) do
		v:SendPlayerNodes( player );
	end
end

function base_manager:_LoadBase( data_row )
	local row_id = "base_" .. tostring(data_row.id);

	self._bases[row_id] = FactionBase:Create();
	self._bases[row_id]:Load( self._database, data_row );

	return self._bases[row_id];
end

function base_manager:_GetBaseIndex( id )
	id = tonumber(id);

	for i,v in pairs(self._bases) do
		if (v:GetID() == id) then
			return i;
		end
	end

	return nil;
end

function base_manager:_RemoveBase( id )
	local idx = self:_GetBaseIndex(id);
	if (idx == nil) then
		self:Dump();
		error("Index not found.");
		return;
	end	

	self._bases[ idx ]:Unload();
	self._bases[ idx ] = nil;
	self:Dump();
	-- TODO: Unregister base from Base entity manager.
end

function base_manager:Dump()
	for i,v in pairs(self._bases) do
		print( i .. " (" .. type(i) .. ")", v:GetDisplayName() );
	end
end

function base_manager:Load( database )
	SERVER:ForceUpdateFactionData();

	self._database = database;

	-- Load all factions
	local bases = self._database:Query("SELECT * FROM " .. SERVER.DBInfo.db .. ".game_bases", true);
	
	if (bases == nil) then
		error("Initial bases query failed.");	
	end

	-- Construct faction data
	for i,v in pairs(bases) do
		local base = self:_LoadBase( v );
		print("Loaded base " .. base:GetDisplayName());
	end

	self:Dump();
end

function base_manager:GetBaseLocal( base_id )
	base_id = tonumber(base_id);
	
	local idx = self:_GetBaseIndex( base_id );
	if (idx == nil) then
		return nil, "Base not found.";
	end

	return self._bases[ idx ];
end

return base_manager;