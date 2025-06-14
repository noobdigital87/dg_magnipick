local mod_storage = core.get_mod_storage()
local mod_name = core.get_current_modname()

local settings = {
	enable_pickup = core.settings:get_bool(mod_name .. ".enable_pickup") or true,
	enable_drop = core.settings:get_bool(mod_name .. ".enable_drop") or true,
	pickup_radius = tonumber(core.settings:get(mod_name .. ".pickup_radius")) or 1,
	item_pickup_speed = tonumber(core.settings:get(mod_name .. ".atrraction_speed")) or 10,
	sound_gain = tonumber(core.settings:get(mod_name .. ".sound_gain")) or 0.5,
}


local filter_inv_names = {mod_name .. "_1", mod_name .. "_2"}
local player_page = {}

local function update_filter_storage()
    	local filters = {}
    	for i, inv_name in ipairs(filter_inv_names) do
        	local inv = core.get_inventory({ type = "detached", name = inv_name })
        	filters[i] = {}
        	if inv then
            		local list = inv:get_list("main")
            		if list then
                		for _, stack in ipairs(list) do
                    			if not stack:is_empty() then
                        			filters[i][stack:get_name()] = true
                    			end
                		end
            		end
        	end
    	end
    	mod_storage:set_string("filter_lists", core.serialize(filters))
end

local function restore_filter_lists()
    	local saved_str = mod_storage:get_string("filter_lists")
    	if saved_str and saved_str ~= "" then
        	local saved = core.deserialize(saved_str)
        	if saved then
            		for i, inv_name in ipairs(filter_inv_names) do
                		local list = {}
                		if saved[i] then
                    			for item_name, _ in pairs(saved[i]) do
                        			table.insert(list, ItemStack(item_name))
                    			end
                		end
                                for j = #list + 1, 32 do
                    			list[j] = ""
                		end
                		local inv = core.get_inventory({type = "detached", name = inv_name})
                		if inv then
                    			inv:set_list("main", list)
                		end
            		end
        	end
    	end
end

local function is_item_allowed(stack)
    	local filter_mode = mod_storage:get_string("filter_mode")
    	if filter_mode == "" then filter_mode = "off" end
    		local stored_filter_str = mod_storage:get_string("filter_lists")
    		local combined_filter = {}
    		if stored_filter_str ~= "" then
        		local lists = core.deserialize(stored_filter_str) or {}
        		for _, filter in ipairs(lists) do
            			for k, v in pairs(filter) do
                			combined_filter[k] = true
            			end
        		end
    		end
    		local item_name = stack:get_name()

    		if filter_mode == "off" then
        		return true
    		elseif filter_mode == "whitelist" then
        		return combined_filter[item_name] == true
    		elseif filter_mode == "blacklist" then
        		return not combined_filter[item_name]
    		else
        	return true
    	end
end

-- Create both detached inventories with 32 slots each
core.register_on_joinplayer(function(player)
    	for i, inv_name in ipairs(filter_inv_names) do
        	local inv = core.create_detached_inventory(inv_name, {
            			allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                		return count
            		end,
            		allow_put = function(inv, listname, index, stack, player)
                		return stack:get_count()
            		end,
            		allow_take = function(inv, listname, index, stack, player)
                		return stack:get_count()
            		end,
            		on_put = function(inv, listname, index, stack, player)
                		update_filter_storage()
            		end,
            		on_take = function(inv, listname, index, stack, player)
                		update_filter_storage()
            		end,
       		})
        	inv:set_size("main", 32)
    	end
    	restore_filter_lists()
end)

local function show_formspec(player, page)
    	local name = player:get_player_name()
    	page = page or player_page[name] or 1
    	player_page[name] = page
    	local filter_mode = mod_storage:get_string("filter_mode")
    	if filter_mode == "" then filter_mode = "off" end
    	local formspec =
        	"size[8,9]" ..
        	string.format("label[0,0;Filter List Page %d/2]", page) ..
        	string.format("list[detached:%s;main;0,0.5;8,4;]", filter_inv_names[page]) ..
        	"button[6,4.5;2,1;toggle_mode;Toggle Filter (" .. filter_mode .. ")]" ..
        	string.format("button[0,4.5;2,1;switch_page;Page %d]", page == 1 and 2 or 1) ..
        	"button[3,4.5;2,1;quick_transfer;Quick Transfer]" ..
        	"list[current_player;main;0,5.5;8,3;]" ..
        	"listring[current_player;main]"
    	core.show_formspec(name, mod_name, formspec)
end

local function quick_transfer(player, page)
    	local player_inv = player:get_inventory()
    	local detached_inv = core.get_inventory({ type = "detached", name = filter_inv_names[page] })
    	if not detached_inv then
        	return
    	end
    	local list = detached_inv:get_list("main")
    	if not list then
        	return
    	end
    	local transferred = false
    	for _, stack in ipairs(list) do
        	if not stack:is_empty() and is_item_allowed(stack) then
            		if player_inv:room_for_item("main", stack) then
                		player_inv:add_item("main", stack)
                		detached_inv:remove_item("main", stack)
                		transferred = true
            		end
        	end
    	end
    	local name = player:get_player_name()
    	if transferred then
        	core.chat_send_player(name, "Transferred items to your inventory.")
    	else
        	core.chat_send_player(name, "No space in inventory, or no allowed items to transfer.")
   	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
    	if formname == mod_name then
        	local name = player:get_player_name()
        	local page = player_page[name] or 1
        	if fields.switch_page then
            		page = page == 1 and 2 or 1
            		player_page[name] = page
            		show_formspec(player, page)
        	elseif fields.toggle_mode then
            		local current_mode = mod_storage:get_string("filter_mode")
            		if current_mode == "" then current_mode = "off" end
            			local new_mode = "off"
            			if current_mode == "off" then
                			new_mode = "whitelist"
            			elseif current_mode == "whitelist" then
                			new_mode = "blacklist"
            			elseif current_mode == "blacklist" then
                		new_mode = "off"
            		end
            		mod_storage:set_string("filter_mode", new_mode)
            		core.chat_send_player(name, "Filter mode set to " .. new_mode)
            		show_formspec(player, page)
        	elseif fields.quick_transfer then
            		quick_transfer(player, page)
            		show_formspec(player, page)
        	end
    	end
end)

core.register_chatcommand("magnipick", {
    	description = "Opens the filter form",
    	func = function(name)
        	local player = core.get_player_by_name(name)
        	if player then
            		player_page[name] = 1
            		show_formspec(player, 1)
        	end
    	end,
})

local original_handle_node_drops = core.handle_node_drops

if settings.enable_drop then
    	core.handle_node_drops = function(position, drops, digger)
		for _, drop_item in ipairs(drops) do
			local item_stack = ItemStack(drop_item)
			local drop_position = vector.add(position, {x = 0, y = 0.5, z = 0})
			local spawned_item = core.add_item(drop_position, item_stack)
			if spawned_item then
				local velocity = {
					x = math.random(-1, 1),
					y = math.random(0.5, 1),
					z = math.random(-1, 1),
				}
			end
			spawned_item:set_velocity(velocity or {x=0, y=0, z=0})
		end

		if digger and digger:is_player() then
			return
		end
		if original_handle_node_drops then
			original_handle_node_drops(position, drops, digger)
		end
        end
end

local minimum_pickup_distance = 0.35
local active_pickup_sounds = {}

-- Function to play a sound for item pickup
local function play_pickup_sound(player_name)
    	if not active_pickup_sounds[player_name] then
        	local sound_duration = 0.3 -- Duration before sound can be replayed
        	active_pickup_sounds[player_name] = {time_remaining = sound_duration}
        	core.sound_play({
            		name = mod_name.."_pickup",
            		gain = settings.sound_gain,
            		pitch = math.random(80, 120) / 100,
            		to_player = player_name,
        	})
    	end
end

core.register_globalstep(function(delta_time)
    	local players = core.get_connected_players()
    	if players then
        	for _, player in ipairs(players) do
            		for player_name, sound_data in pairs(active_pickup_sounds) do
                		sound_data.time_remaining = sound_data.time_remaining - delta_time
                		if sound_data.time_remaining <= 0 then
                    			active_pickup_sounds[player_name] = nil
                		end
            		end

            		local player_position = player:get_pos()
            		local player_name = player:get_player_name()
            		local inventory = player:get_inventory()

            		for object in core.objects_inside_radius(player_position, settings.pickup_radius) do
                		if object and not object:is_player() and object:get_luaentity() and object:get_luaentity().name == "__builtin:item" then
                    			local item_stack = ItemStack(object:get_luaentity().itemstring)
                    			local object_position = object:get_pos()

                    			if inventory:room_for_item("main", item_stack) then
                        			local direction = vector.subtract(player_position, object_position)
                        			local distance = vector.length(direction)

                        			if distance > minimum_pickup_distance and settings.enable_pickup and is_item_allowed(item_stack) then
                            				direction = vector.normalize(direction)
                            				local velocity = vector.multiply(direction, settings.item_pickup_speed)
                           	 			object:set_velocity(velocity)
                        			else
                            				if is_item_allowed(item_stack) then
                                				inventory:add_item("main", item_stack)
                                				object:remove()
                                				play_pickup_sound(player_name)
                            				end
                        			end
                    			end
                		end
            		end
        	end
	end
end)
