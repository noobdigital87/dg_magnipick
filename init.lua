local mod_storage = core.get_mod_storage()
local mod_name = core.get_current_modname()

local settings = {
	enable_pickup = core.settings:get_bool(mod_name .. ".enable_pickup") or true,
	enable_drop = core.settings:get_bool(mod_name .. ".enable_drop") or true,
	pickup_radius = tonumber(core.settings:get(mod_name .. ".pickup_radius")) or 1,
	item_pickup_speed = tonumber(core.settings:get(mod_name .. ".atrraction_speed")) or 10,
	sound_gain = tonumber(core.settings:get(mod_name .. ".sound_gain")) or 0.5,
	enable_command = core.settings:get_bool(mod_name .. ".enable_command") or true,
	enable_page = core.settings:get_bool(mod_name .. ".enable_page") or true,
}

local mod = {
	sfinv = core.get_modpath("sfinv") and core.global_exists("sfinv")
}

local filter_inv_names = {mod_name .. "_1", mod_name .. "_2"}
local player_page = {}

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
		if not stack:is_empty() then
			if player_inv:room_for_item("main", stack) then
				player_inv:add_item("main", stack)
				player_inv:remove_item("main", ItemStack(stack:get_name()))
				detached_inv:remove_item("main", stack)
				transferred = true
			end
		end
	end
	local name = player:get_player_name()
	if transferred then
		core.chat_send_player(name, "Cleared the filter page.")
	else
		core.chat_send_player(name, "No space in inventory, or nothing to transfer")
	end
end

local function build_filter_formspec(name, page)
	page = page or player_page[name] or 1
	local filter_mode = mod_storage:get_string("filter_mode")
	if filter_mode == "" then filter_mode = "off" end
	return
		"size[8,9]" ..
		string.format("label[0,0;Filter List Page %d/2]", page) ..
		string.format("list[detached:%s;main;0,0.5;8,4;]", filter_inv_names[page]) ..
		"button[6,4.5;2,1;toggle_mode;Filter Mode: " .. filter_mode .. "]" ..
		string.format("button[0,4.5;2,1;switch_page;Page %d]", page == 1 and 2 or 1) ..
		"button[3,4.5;2,1;quick_transfer;Clear List]" ..
		"list[current_player;main;0,5.5;8,3;]" ..
		"listring[current_player;main]"
end

local function show_formspec(player, page)
	local name = player:get_player_name()
	player_page[name] = page or player_page[name] or 1
	core.show_formspec(name, mod_name, build_filter_formspec(name, page))
end

if mod.sfinv and settings.enable_page then
	sfinv.register_page(mod_name .. ":filters", {
		title = "Magnipick",
		get = function(self, player, context)
			local name = player:get_player_name()
			local page = player_page[name] or 1
			return sfinv.make_formspec(player, context, build_filter_formspec(name, page), false)
		end,
		on_player_receive_fields = function(self, player, context, fields)
			local name = player:get_player_name()
			local page = player_page[name] or 1
			if fields.sfinv_back then
				sfinv.set_page(player, "sfinv:crafting")
				return true
			end
			if fields.switch_page then
				page = page == 1 and 2 or 1
				player_page[name] = page
				sfinv.set_page(player, mod_name .. ":filters")
				return true
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
				sfinv.set_page(player, mod_name .. ":filters")
				return true
			elseif fields.quick_transfer then
				quick_transfer(player, page)
				sfinv.set_page(player, mod_name .. ":filters")
				return true
			end
		end,
	})
end

-- Create both detached inventories with 32 slots each
core.register_on_joinplayer(function(player)
	for i, inv_name in ipairs(filter_inv_names) do
		local inv = core.create_detached_inventory(inv_name, {
			allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
				-- Only allow sorting if target is empty
				if from_list == "main" and to_list == "main" then
					if inv:get_stack(to_list, to_index):is_empty() then
						return count
					else
						return 0
					end
				end
				return 0
			end,
			allow_put = function(inv, listname, index, stack, player)
				if stack:is_empty() then return 0 end
				local item_name = stack:get_name()

				-- Uniqueness for both pages
				for _, inv_name2 in ipairs(filter_inv_names) do
					local other_inv = core.get_inventory({type="detached", name=inv_name2})
					if other_inv then
						local list = other_inv:get_list("main")
						for _, s in ipairs(list) do
							if not s:is_empty() and s:get_name() == item_name then
								return 0
							end
						end
					end
				end
				if not inv:get_stack(listname, index):is_empty() then
					return 0
				end
				return 1
			end,
			allow_take = function(inv, listname, index, stack, player)
				return 0 -- prevent taking items out of the form
			end,
			on_put = function(inv, listname, index, stack, player)
				update_filter_storage()
				if player and player:is_player() then
					player:get_inventory():add_item("main", ItemStack(stack:get_name()))
				end
			end,
			on_take = function(inv, listname, index, stack, player)
				update_filter_storage()
				if player and player:is_player() then
					player:get_inventory():remove_item("main", ItemStack(stack:get_name()))
				end
			end,
		})
		inv:set_size("main", 32)
	end
	restore_filter_lists()
end)

if settings.enable_command then
	core.register_chatcommand("magnipick", {
		description = "Opens the filter form",
		func = function(name)
			local player = core.get_player_by_name(name)
			if player then
				local page = player_page[name] or 1
				show_formspec(player, page)
			end
		end,
	})
end

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
				spawned_item:set_velocity(velocity)
			end
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

local function play_pickup_sound(player_name)
	if not active_pickup_sounds[player_name] then
		local sound_duration = 0.3
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
			-- Pickup sound cooldowns
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
