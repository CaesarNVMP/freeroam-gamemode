local Base =
{
	_data = {},
	_database = nil
};

local core = require("util/core");
local Base = require("util/object");
Base._data     = {};
Base._database = {};
Base._nodes    = {};

function Base:GetNodes()
	return self._nodes;
end

function Base:MakeNode(parent_table)
	local node = {};
	node.label = "Default Node";
	node.x = 0.0;
	node.y = 0.0;
	node.z = 0.0;
	node.area_radius = 0;
	node.uid = string.format("{base-%s-%d}", self:GetDisplayName(), table.length(parent_table));

	node.worldspace = core.WORLDSPACE_NONE;
	parent_table[ node.uid ] = node;
	return node;
end

function Base:BroadcastRemoveNode( node )
	if (node.uid == nil) then
		error("Node removal needs a UID table entry.");
	end

	local cleanup_data = { uid = node.uid };
	RPC.BroadcastArray("node.remove", cleanup_data);
end

function Base:BroadcastNewNode( node )
	if (node.uid == nil) then
		error("Node addition needs a UID table entry.");
	end

	RPC.BroadcastArray("node.add", node);
end

function Base:UpdateNodes(hard)
	hard = hard or false;

	local node_population = {};

	local w, x, y, z, opt_cell = self:GetWorldspaceCoords();
	z = z + 150.0;

	local faction = SERVER:GetFactionByID(self:GetFactionOwner());
	if (faction == nil) then
		faction =
		{
			name    = "Unowned",
			banner  = "",

			r = 255,
			g = 255,
			b = 255
		};
	end

	-- Node for faction name at faction exterior location.
	local nametag = self:MakeNode(node_population);
	nametag.type = "zone"; -- Signify this node as a base zone point.
	nametag.label = self:GetDisplayName();

	nametag.worldspace = w;
	nametag.x = x;
	nametag.y = y;
	nametag.z = z;
	nametag.cell = opt_cell;
	nametag.radius = self:GetWorldspaceRadius();
	nametag.offset = 0;

	-- Node for current faction owner.
	local faction_owner = self:MakeNode(node_population);
	faction_owner.label = faction.name;
	faction_owner.offset = -20;
	faction_owner.scale = 0.8;
	faction_owner.worldspace, faction_owner.x, faction_owner.y, faction_owner.z = w, x, y, z;
	faction_owner.r = faction.r / 255.0;
	faction_owner.g = faction.g / 255.0;
	faction_owner.b = faction.b / 255.0;

	-- Node for current faction owner.
	local faction_tagline = self:MakeNode(node_population);
	faction_tagline.offset = 25;
	faction_tagline.scale = 0.8;
	faction_tagline.worldspace, faction_tagline.x, faction_tagline.y, faction_tagline.z = w, x, y, z;

	if (self:GetCanCapture()) then
		faction_tagline.label = ""; --"As a faction officer, use /startcapture";
	else 
		faction_tagline.label = "Capture Locked";
	end

	-- At the end compare the current nodes to the new node list.
	for i,v in pairs(self._nodes) do
		if (node_population[i] == nil or hard) then
			-- Remove a pre-existing node
			self:BroadcastRemoveNode( v );
		end
	end

	for i,v in pairs(node_population) do
		if (self._nodes[i] == nil or hard) then
			-- Add a new node.
			self:BroadcastNewNode( v );
		end
	end

	self._nodes = node_population;
end

function Base:BroadcastAllAddNodes()
	self:UpdateNodes();

	for i,v in pairs(self._nodes) do
		self:BroadcastNewNode( v )
	end
end

function Base:BroadcastAllRemoveNodes()
	self:UpdateNodes();

	for i,v in pairs(self._nodes) do
		self:BroadcastRemoveNode( v );
	end
end

function Base:SendPlayerNodes(player)
	for i,v in pairs(self._nodes) do
		RPC.SendArray(player, "node.add", v);
	end
end

----------------------------------------------------
--[  Base:_Set(property, data)                     ]
--   Internal helper function for setting property
--   data on faction entries. Should only be called
--   within faction.lua
----------------------------------------------------
function Base:_Set(_property, _data)
	property = self._database:Escape(_property);
	data = self._database:Escape(_data);

	local q = string.format("UPDATE " .. SERVER.DBInfo.db .. ".game_bases SET %s = %q WHERE id = %d", property, data, self._data.id);
	if (self._database:Query(q, false)) then
		self._data[_property] = _data;
	else
		print("Base:_Set() database failure on property " .. _property);
	end

	self:UpdateNodes(true);
end

----------------------------------------------------
--[  Base:SetDisplayName / GetDisplayName          ]
--   Modifies the base public display name.
----------------------------------------------------
function Base:GetDisplayName()
	return self._data.display_name;
end
function Base:SetDisplayName(name)
	self:_Set("display_name", string.format("%s", name));
end

----------------------------------------------------
--[  Base:SetCanCapture / GetCanCapture            ]
--   Modifies the base capture flags.
----------------------------------------------------
function Base:GetCanCapture()
	return tonumber( self._data.capture_locked ) ~= 1;
end
function Base:SetCanCapture(flag)
	self:_Set("capture_locked", tonumber(not(flag)));
end

----------------------------------------------------
--[  Base:GetID()                                  ]
--   Modifies the base internal ID.
----------------------------------------------------
function Base:GetID()
	return self._data.id;
end

----------------------------------------------------
--[  Base:SetFactionOwner / GetFactionOwner        ]
--   Modifies the associated base group that
--   owns this base.
----------------------------------------------------
function Base:GetFactionOwner()
	return self._data.faction_owner;
end
function Base:SetFactionOwner(owner)
	self:_Set("faction_owner", string.format("%d", owner));
end

-----------------------------------------------------
--[  Base:SetWorldspaceCoords / GetWorldspaceCoords ]
--   Modifies the exterior base coordinates. Pass 
--   just zero as first parameter to just set x,y,z.
-----------------------------------------------------
function Base:GetWorldspaceCoords()
	return self._data.worldspace_zone, self._data.worldspace_x, self._data.worldspace_y, self._data.worldspace_z, self._data.worldspace_cell;
end
function Base:SetWorldspaceCoords(zone, x, y, z, opt_cell)
	self:_Set("worldspace_zone", string.format("%d", zone));

	self:_Set("worldspace_x", x);
	self:_Set("worldspace_y", y);
	self:_Set("worldspace_z", z);

	if opt_cell ~= nil then
		self:_Set("worldspace_cell", opt_cell);
	end
end

-----------------------------------------------------
--[  Base:SetWorldspaceRadius / GetWorldspaceRadius ]
--   Modifies the exterior base coordinate radius,
--   controlling the distance (radius) the base 
--   is defined in. 
-----------------------------------------------------
function Base:GetWorldspaceRadius()
	return self._data.worldspace_radius;
end
function Base:SetWorldspaceRadius(distance)
	self:_Set("worldspace_radius", distance);
end

-----------------------------------------------------
--[  Base:SetSpawnPos / GetSpawnPos ]
--   Sets the base's spawn position, pass just zero
--   to set spawn's x,y,z.
-----------------------------------------------------
function Base:GetSpawnPos()
	return self._data.spawn_zone, self._data.spawn_world_x, self._data.spawn_world_y, self._data.spawn_x, self._data.spawn_y, self._data.spawn_z;
end
function Base:SetSpawnPos(zone, world_x, world_y, x, y, z)
	-- Valid zones should be checked for exterior bounds validation.
	if (zone ~= 0) then
		local dx = (self._data.worldspace_x - x);
		local dy = (self._data.worldspace_y - y);
		local dz = (self._data.worldspace_z - z);

		local distance = math.sqrt( dx * dx + dy * dy + dz * dz);

		if (distance > self._data.worldspace_radius) then
			-- Don't let the spawn position be outside of the base coordinates.
			return false, "Spawn is outside of base coordinates";
		end
	end

	self:_Set("has_spawn", 1);
	self:_Set("spawn_zone", string.format("%d", zone));
	self:_Set("spawn_cell", "");
	self:_Set("spawn_x", x);
	self:_Set("spawn_y", y);
	self:_Set("spawn_z", z);
	self:_Set("spawn_world_x", world_x);
	self:_Set("spawn_world_y", world_y);

	return true;
end

-----------------------------------------------------
--[  Base:SetSpawnCell() ]
--   Sets the spawn position to an interior cell, 
--   must have a valid owned cell.
-----------------------------------------------------
function Base:SetSpawnCell(cellID, x, y, z)
	local cells = self:GetInteriorCells();

	for i,v in pairs(cells) do
		if (v == cellID) then
			self:_Set("has_spawn", 1);
			self:_Set("spawn_cell", string.format("%s", cellID));
			self:_Set("spawn_x", x);
			self:_Set("spawn_y", y);
			self:_Set("spawn_z", z);
			return true;
		end
	end

	-- Attempted to set spawn cell to an un-owned cell.
	return false, "Cannot set cell to unowned cell"
end
function Base:GetSpawnCell() 
	return self._data.spawn_cell;
end

-----------------------------------------------------
--[  Base:HasSpawn / DisableSpawn                   ]
--   Flags for if the base has a spawn.
-----------------------------------------------------
function Base:HasSpawn()
	return self._data.has_spawn;
end
function Base:DisableSpawn()
	self:_Set("has_spawn", 0);
end
function Base:EnableSpawn()
	self:_Set("has_spawn", 1);
end

-----------------------------------------------------
--[  Base:GetInteriorCells()                        ]
--   Retreives a list of interior cells the base 
--   controls.
-----------------------------------------------------
function Base:GetInteriorCells()
	if (self._data.interior_ownerships:len() == 0) then
		return {};
	end

	local result = string.explode(self._data.interior_ownerships, ",");
	return result;
end

-----------------------------------------------------
--[  Base:AddInteriorCell(cellID)                   ]
--   Adds an interior cell to the base ownership.
-----------------------------------------------------
function Base:AddInteriorCell(cellID)
	local cells = self:GetInteriorCells();

	for i,v in pairs(cells) do
		if (v == cellID) then
			-- Don't add multiple interior cells.
			return;
		end
	end

	table.insert(cells, cellID);
	self:_Set("interior_ownerships", table.concat(cells, ","));
end

-----------------------------------------------------
--[  Base:RemoveInteriorCell(cellID)                ]
--   Removes an interior cell from the base ownership
-----------------------------------------------------
function Base:RemoveInteriorCell(cellID)
	local cells = self:GetInteriorCells();

	for i,v in pairs(cells) do
		if (v == cellID) then
			table.remove(cells, i);
			break;
		end
	end

	self:_Set("interior_ownerships", table.concat(cells, ","));
end

-----------------------------------------------------
--[  Base:Load(database, data_rows)                 ]
--   Initialisation routine for internal base data, 
--   must pass a database object that controls
--   storage for the base.
--
--   Data rows ia a list of 
--   data that has either been defaulted, or 
--   loaded from a source.
-----------------------------------------------------
function Base:Load(database, data_rows, silent)
	-- Import the data rows.
	for i,v in pairs(data_rows) do
		self._data[i] = v;
	end
	-- Create a reference to the database connection for 
	-- live data updates.
	self._database = database;
	self:UpdateNodes(true);

	-- Dont broadcast when silent.
	if silent == nil and silent ~= true then
		self:BroadcastAllAddNodes();
	end
end

function Base:Unload()
	self:BroadcastAllRemoveNodes();
	self._data = nil;
	self._database = nil;
end

return Base;