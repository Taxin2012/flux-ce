if !Bolt then
  PLUGIN:set_global('Bolt')
end

local roles = Bolt.roles or {}
local permissions = Bolt.permissions or {}
local players = Bolt.players or {}
local bans = Bolt.bans or {}
Bolt.roles = roles
Bolt.permissions = permissions
Bolt.players = players
Bolt.bans = bans

function Bolt:get_permissions()
  return permissions
end

function Bolt:get_roles()
  return roles
end

function Bolt:get_players()
  return players
end

function Bolt:get_bans()
  return bans
end

function Bolt:create_role(id, data)
  if !isstring(id) then return end

  data.id = id

  if data.base then
    local parent = roles[data.base]

    if parent then
      local copy = table.Copy(parent)

      table.safe_merge(copy.permissions, data.permissions)

      data.permissions = copy.permissions

      for k, v in pairs(copy) do
        if k == 'permissions' then continue end

        if !data[k] then
          data[k] = v
        end
      end
    end
  end

  if !roles[id] then
    roles[id] = data
  end
end

function Bolt:add_permission(id, category, data, force)
  if !id then return end

  category = category or 'general'
  data.id = id
  permissions[category] = permissions[category] or {}

  if !permissions[category][id] or force then
    permissions[category][id] = data
  end
end

function Bolt:register_permission(id, name, description, category)
  if !isstring(id) or id == '' then return end

  local data = {}
    data.id = id:to_id()
    data.description = description or 'No description provided.'
    data.category = category or 'general'
    data.name = name or id
  self:add_permission(id, category, data, true)
end

function Bolt:permission_from_command(cmd)
  if !cmd then return end

  self:register_permission(cmd.id, cmd.name, cmd.description, cmd.category)
end

function Bolt:can(player, action, object)
  if !IsValid(player) or player:is_root() or action == '' then
    return true
  end

  local temp_perm = player:get_temp_permission(action)

  if temp_perm then
    if time_from_timestamp(temp_perm.expires) > os.time() then
      local value = temp_perm.value

      if value == PERM_ALLOW then
        return true
      elseif value == PERM_NEVER then
        return false
      end
    else
      if CLIENT then
        cable.send('fl_delete_temp_permission', player, action)
      else
        self:delete_temp_permission(player, action)
      end
    end
  end

  local perm = player:get_permission(action)

  if perm == PERM_ALLOW then
    return true
  elseif perm == PERM_NEVER then
    return false
  end

  local role = roles[player:GetUserGroup()]

  if istable(role) and isfunction(role.can) then
    return role:can(player, action, object)
  end

  return false
end

function Bolt:find_group(id)
  if roles[id] then
    return roles[id]
  end

  return nil
end

function Bolt:group_exists(id)
  return self:find_group(id)
end

function Bolt:check_immunity(player, target, can_equal)
  if !IsValid(player) or !IsValid(target) then
    return true
  end

  local group1 = self:find_group(player:GetUserGroup())
  local group2 = self:find_group(target:GetUserGroup())

  if !isnumber(group1.immunity) or !isnumber(group2.immunity) then
    return true
  end

  if group1.immunity > group2.immunity then
    return true
  end

  if can_equal and group1.immunity == group2.immunity then
    return true
  end

  return false
end

function Bolt:include_roles(directory)
  pipeline.include_folder('role', directory)
end

if SERVER then
  function can(action, object)
    if IsValid(current_player) then
      return current_player:can(action, object)
    end

    return false
  end

  -- INTERNAL
  function Bolt:add_ban(steam_id, name, unban_time, duration, reason)
    local obj = bans[steam_id] or Ban.new()
      obj.name = name
      obj.steam_id = steam_id
      obj.reason = reason
      obj.duration = duration
      obj.unban_time = unban_time
    self:record_ban(steam_id, obj:save())
  end

  function Bolt:record_ban(id, obj)
    bans[id] = obj
  end

  function Bolt:ban(player, duration, reason, prevent_kick)
    if !isstring(player) and !IsValid(player) then return end

    duration = duration or 0
    reason = reason or 'N/A'

    local steam_id = player
    local name = steam_id

    if !isstring(player) and IsValid(player) then
      name = player:steam_name()
      steam_id = player:SteamID()

      if !prevent_kick then
        player:Kick('You have been banned: '..tostring(reason))
      end
    end

    self:add_ban(steam_id, name, os.time() + duration, duration, reason)
  end

  function Bolt:remove_ban(steam_id)
    local obj = bans[steam_id]
    if obj then
      local dump = obj:dump()
      obj:destroy()

      return true, dump
    end

    return false
  end
else
  function can(action, object)
    return fl.client:can(action, object)
  end
end

do
  -- Translations of words into seconds.
  local tokens = {
    second = 1,
    sec = 1,
    minute = 60,
    min = 60,
    hour = 60 * 60,
    day = 60 * 60 * 24,
    week = 60 * 60 * 24 * 7,
    month = 60 * 60 * 24 * 30,
    mon = 60 * 60 * 24 * 30,
    year = 60 * 60 * 24 * 365,
    yr = 60 * 60 * 24 * 365,
    permanently = 0,
    perma = 0,
    perm = 0,
    pb = 0,
    forever = 0,
    moment = 1
  }

  local num_tokens = {
    one = 1,
    two = 2,
    three = 3,
    four = 4,
    five = 5,
    six = 6,
    seven = 7,
    eight = 8,
    nine = 9,
    ten = 10,
    few = 5,
    couple = 2,
    bunch = 120,
    lot = 1000000,
    dozen = 12,
    noscope = 420
  }

  function Bolt:interpret_ban_time(str)
    if isnumber(str) then return str * 60 end
    if !isstring(str) then return false end

    str = str:trim_end(' ')
    str = str:trim_start(' ')
    str = str:Replace("'", '')
    str = str:lower()

    -- A regular number was entered?
    if tonumber(str) then
      return tonumber(str) * 60
    end

    str = str:Replace('-', '')

    local pieces = str:split(' ')
    local result = 0
    local token, num = '', 0

    for k, v in ipairs(pieces) do
      local n = tonumber(v)

      if isstring(v) then
        v = v:trim_end('s')
      end

      if !n and !tokens[v] and !num_tokens[v] then continue end

      if n then
        num = n
      elseif isstring(v) then
        v = v:trim_end('s')

        local ntok = num_tokens[v]

        if ntok then
          num = ntok

          continue
        end

        local tok = tokens[v]

        if tok then
          if tok == 0 then
            return 0
          else
            result = result + (tok * num)
          end
        end

        token, num = '', 0
      else
        token, num = '', 0
      end
    end

    return result
  end
end

do
  Bolt:register_permission('physgun', 'Access Physgun', 'Grants access to the physics gun.', 'categories.tools')
  Bolt:register_permission('toolgun', 'Access Tool Gun', 'Grants access to the tool gun.', 'categories.tools')
  Bolt:register_permission('physgun_freeze', 'Freeze Protected Entities', 'Grants access to freeze protected entities.', 'categories.tools')
  Bolt:register_permission('physgun_pickup', 'Unlimited Physgun', 'Grants access to pick up any entity with the physics gun.', 'categories.tools')

  Bolt:register_permission('spawn_props', 'Spawn Props', 'Grants access to spawn props.', 'categories.spawn')
  Bolt:register_permission('spawn_chairs', 'Spawn Chairs', 'Grants access to spawn chairs.', 'categories.spawn')
  Bolt:register_permission('spawn_vehicles', 'Spawn Vehicles', 'Grants access to spawn vehicles.', 'categories.spawn')
  Bolt:register_permission('spawn_entities', 'Spawn All Entities', 'Grants access to spawn any entity.', 'categories.spawn')
  Bolt:register_permission('spawn_npcs', 'Spawn NPCs', 'Grants access to spawn NPCs.', 'categories.spawn')
  Bolt:register_permission('spawn_ragdolls', 'Spawn Ragdolls', 'Grants access to spawn ragdolls.', 'categories.spawn')
  Bolt:register_permission('spawn_sweps', 'Spawn SWEPs', 'Grants access to spawn scripted weapons.', 'categories.spawn')

  Bolt:register_permission('voice', 'Voice chat access', 'Grants access to voice chat.', 'categories.general')
  Bolt:register_permission('context_menu', 'Access Context Menu', 'Grants access to the context menu.', 'categories.general')
end

pipeline.register('role', function(id, file_name, pipe)
  ROLE = Role.new(id)

  util.include(file_name)

  ROLE:register()
  ROLE = nil
end)
