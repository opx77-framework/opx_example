-- opx_example server: everything a third-party OPX resource usually needs, one short block per feature.
-- The server decides everything; the client only asks. Every optional OPX member is called under pcall with a
-- fallback, so this file runs on an OPX without NotifyLocale / GetPlayersByJobType too.

local RESOURCE = GetCurrentResourceName()
local CORE = 'opx_core'

-- Helpers ------------------------------------------------------------------------------------------

local function warn(text) print(('[%s] %s'):format(RESOURCE, text)) end

-- A player id from anything (an integer >= 1), or nil. Natives abort the server on 0, negatives or decimals.
local function toSource(value)
	local id = tonumber(value)
	if not id or id ~= id or id < 1 or id > 0xFFFFFFFF or id % 1 ~= 0 then return nil end
	return math.tointeger(id)
end

-- Unix seconds as an integer. The server sandbox has no `os` library: Open77.time.unix() is the clock.
local function now()
	local ok, t = pcall(Open77.time.unix)
	t = ok and tonumber(t) or nil
	if not t or t ~= t or t == math.huge or t < 0 then return 0 end
	return math.tointeger(math.floor(t)) or 0
end

-- An opx_core export: its results, or nil, 'core_unavailable' when opx_core is stopped or the export is missing.
local function core(name, ...)
	local ok, a, b = pcall(Open77.exports.callSync, CORE, name, ...)
	if not ok then return nil, 'core_unavailable' end
	return a, b
end

-- The resource filling a provider slot ('inventory', 'logs'...), or nil. Never name a provider.
local function provider(slot)
	local name = core('GetProvider', slot)
	return type(name) == 'string' and name or nil
end

-- An export of a provider: called, results... (called = false when there is none or the call raised,
-- e.g. an optional member the provider does not implement).
local function callProvider(slot, name, ...)
	local res = provider(slot)
	if not res then return false, 'no_provider' end
	local ok, a, b = pcall(Open77.exports.callSync, res, name, ...)
	if not ok then return false, tostring(a) end
	return true, a, b
end

-- Rate limit: false when the player asked again too soon. GetGameTimer() is a float on the server.
local lastCall = {}
local function allow(source)
	local t = GetGameTimer()
	if lastCall[source] and t - lastCall[source] < Config.rateLimitMs then return false end
	lastCall[source] = t
	return true
end

-- Every client request: a valid source, under the rate limit, then the handler (arguments still unchecked).
local function onRequest(name, handler)
	RegisterNetEvent(name, function(...)
		local src = toSource(source)
		if not src or not allow(src) then return end
		handler(src, ...)
	end)
end

-- The loaded character of a player (opx_core PlayerData), or nil.
local function character(source)
	local data = core('GetPlayer', source)
	return type(data) == 'table' and type(data.citizenId) == 'string' and data or nil
end

local function fullName(data)
	return (('%s %s'):format(tostring(data.firstname or ''), tostring(data.lastname or ''))):sub(1, 64)
end

-- Whether the player holds this resource's job (on duty when onDutyOnly). Server truth, never the client's.
local function isOfficer(source, onDutyOnly)
	return core('HasJob', source, Config.job.name, 0, onDutyOnly == true) == true
end

-- Two players in the same routing bucket within `distance` metres (+ Config.serverSlack).
local function near(a, b, distance)
	local pa, pb = Open77.players.position(a), Open77.players.position(b)
	if type(pa) ~= 'table' or type(pb) ~= 'table' or pa.bucket ~= pb.bucket then return false end
	local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
	local reach = distance + Config.serverSlack
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

-- Notifications in the player's language ----------------------------------------------------------
-- The server cannot read locales/*.json: it sends a key, the player's client translates it with this
-- resource's own locales. opx_core NotifyLocale does the relay; an older opx_core gets our own relay event.
-- params: flat table of strings / integers (never NaN, inf or a function: they abort the server).
local function notify(source, key, kind, params)
	local ok, sent = pcall(Open77.exports.callSync, CORE, 'NotifyLocale', source, key, params, kind, nil, 'title')
	if ok and sent == true then return end
	pcall(TriggerClientEvent, 'opx_example:notify', source, key, kind or 'info', params or {})
end

-- Logs ----------------------------------------------------------------------------------------------
-- Through the `logs` provider when one runs; nothing happens without it.
local function log(action, message, source)
	callProvider('logs', 'Log', 'example', action, message, { source = source })
end

-- Job ----------------------------------------------------------------------------------------------
-- The registry lives in opx_core's memory: register on our start AND whenever opx_core (re)starts.
-- The job is dropped when this resource stops; holders keep it (available = false) until it comes back.
local function registerJob()
	local job = Config.job
	local ok, reason = core('RegisterJob', job.name, {
		label = job.label, type = job.type, defaultDuty = job.defaultDuty == true,
		data = { bossGrade = job.bossGrade }, grades = job.grades,
	})
	if not ok then warn(('job %s not registered: %s'):format(job.name, tostring(reason))) end
end

-- Officers on duty, counted by job TYPE (every 'leo' job of the server), falling back to our job name on an
-- opx_core without GetPlayersByJobType.
local function officersOnDuty()
	local list = core('GetPlayersByJobType', Config.job.type, true)
	if type(list) ~= 'table' then list = core('GetPlayersByJob', Config.job.name, true) end
	return type(list) == 'table' and #list or 0
end

-- Item and usable handler --------------------------------------------------------------------------
-- The inventory has no item config: the resource that gives an item its meaning registers it. RegisterItem
-- adds example_badge to the catalogue (owned by this resource; calling again replaces our own definition),
-- then RegisterUsable points the "Use" action at our export. Both again whenever the inventory provider
-- (re)starts. Without an inventory provider nothing happens and the badge rows stay disabled.
local itemReady = false

local function registerItem()
	itemReady = false
	local item = Config.item
	local called, ok, reason = callProvider('inventory', 'RegisterItem', item.name, {
		label = item.label, description = item.description, weightG = item.weightG,
		unique = item.unique == true, usable = true,
	})
	if not called then
		if ok ~= 'no_provider' then warn(('item %s not registered: %s'):format(item.name, tostring(ok))) end
		return
	end
	if ok ~= true then return warn(('item %s not registered: %s'):format(item.name, tostring(reason))) end
	local usable, uok, uwhy = callProvider('inventory', 'RegisterUsable', item.name, 'exampleUseBadge')
	itemReady = usable and uok == true
	if not itemReady then warn(('usable %s not registered: %s'):format(item.name, tostring(usable and uwhy or uok))) end
end

-- Shows the badge to every loaded player around `source`. Returns how many saw it.
local function showBadge(source, holderName)
	local seen = 0
	for _, id in ipairs(core('GetPlayers') or {}) do
		local other = toSource(id)
		if other and other ~= source and near(source, other, Config.showDistance) then
			notify(other, 'badge_seen', 'info', { name = holderName })
			seen = seen + 1
		end
	end
	notify(source, 'badge_shown', 'success', { count = seen })
	return seen
end

-- The inventory calls this when a player uses the item (asynchronously: it may wait). Returning true would
-- consume one: a badge is kept, so false.
exports('exampleUseBadge', function(source, item, instanceId, meta)
	local src = toSource(source)
	local data = src and character(src)
	if not data or item ~= Config.item.name then return false end
	local holder = type(meta) == 'table' and type(meta.name) == 'string' and meta.name:sub(1, 64) or fullName(data)
	showBadge(src, holder)
	return false
end)

-- Server callback ------------------------------------------------------------------------------------
-- Answered by OUR export: opx_core passes the player id it knows as `source` (a client cannot choose it).
-- Every other argument comes from a client: validate it. Answer false, reason for a refusal; the client
-- reads nil, reason when the callback itself failed (timeout, rate_limited...).
exports('exampleLookupPlate', function(source, plate)
	local src = toSource(source)
	if not src or not isOfficer(src, true) then return false, 'not_on_duty' end
	if type(plate) ~= 'string' or #plate > 10 or not plate:match('^[%w %-]+$') then return false, 'invalid_plate' end
	plate = plate:upper()
	local car = core('GetOwnedVehicle', plate)
	local owner = type(car) == 'table' and core('GetCharacterInfo', car.citizenId)
	if type(owner) ~= 'table' then return false, 'not_found' end
	log('plate', ('ran plate %s'):format(plate), src)
	return { plate = plate, owner = fullName(owner), record = tostring(car.record or '') }
end)

local function registerCallback()
	local ok, reason = core('RegisterCallback', 'opx_example:lookupPlate', 'exampleLookupPlate')
	if not ok then warn(('callback not registered: %s'):format(tostring(reason))) end
end

-- Targeting eye: "Check ID" --------------------------------------------------------------------------
-- The option's serverEvent arrives as (targetId, info). The menu was client UX only: check the source, the
-- target, the job, life state, bucket and distance again here.
onRequest('opx_example:checkId', function(src, targetId)
	local target = toSource(targetId)
	if not target or target == src then return end
	if not isOfficer(src, true) then return notify(src, 'not_on_duty', 'error') end
	if Open77.players.isDead(src) then return end
	local data = character(target)
	if not data then return notify(src, 'target_not_loaded', 'error') end
	if not near(src, target, Config.checkIdDistance) then return notify(src, 'too_far', 'error') end
	notify(src, 'id_result', 'info', { name = fullName(data), citizenId = data.citizenId,
		birthdate = tostring(data.birthdate or '?') })
	notify(target, 'id_checked', 'info')
	log('check_id', ('checked the id of %s'):format(data.citizenId), src)
	TriggerEvent('opx:example:idChecked', src, target)
end)

-- Desk menu --------------------------------------------------------------------------------------------
-- The state the client draws. It decides nothing: each row asks the server, which checks again.
local function openMenu(src)
	local data = character(src)
	if not data then return notify(src, 'not_loaded', 'error') end
	local job = type(data.job) == 'table' and data.job or {}
	pcall(TriggerClientEvent, 'opx_example:open', src, {
		officer = job.name == Config.job.name, onDuty = job.name == Config.job.name and job.onDuty == true,
		officers = officersOnDuty(), price = math.tointeger(Config.badgePrice) or 0, item = itemReady,
	})
end

onRequest('opx_example:open', openMenu)

onRequest('opx_example:duty', function(src, wanted)
	if type(wanted) ~= 'boolean' then return end
	if not isOfficer(src, false) then return notify(src, 'not_officer', 'error') end
	local ok, reason = core('SetDuty', src, wanted)
	if not ok then return notify(src, 'failed', 'error', { reason = tostring(reason) }) end
	notify(src, wanted and 'duty_on' or 'duty_off', 'success')
	log('duty', wanted and 'on duty' or 'off duty', src)
	openMenu(src)
end)

-- Buy a badge: price, cooldown in metadata, then the item. All synchronous, so nothing can interleave
-- between the checks and the gift; a refused AddItem refunds the money.
onRequest('opx_example:takeBadge', function(src)
	if not isOfficer(src, true) then return notify(src, 'not_on_duty', 'error') end
	local data = character(src)
	if not data then return end
	local at = math.tointeger(core('GetMetadata', src, 'exampleBadgeAt')) or 0
	local left = at + Config.badgeCooldownSeconds - now()
	if left > 0 then return notify(src, 'badge_cooldown', 'error', { minutes = math.ceil(left / 60) }) end

	local item, price = Config.item.name, math.tointeger(Config.badgePrice) or 0
	local called, ok, reason = callProvider('inventory', 'CanCarry', src, item, 1)
	if not called then return notify(src, 'no_inventory', 'error') end
	if not ok then return notify(src, 'failed', 'error', { reason = tostring(reason) }) end
	if price > 0 then
		ok, reason = core('RemoveMoney', src, 'money', price, 'example:badge')
		if not ok then return notify(src, reason == 'insufficient_funds' and 'no_money' or 'failed', 'error',
			{ reason = tostring(reason) }) end
	end
	called, ok, reason = callProvider('inventory', 'AddItem', src, item, 1,
		{ name = fullName(data), number = 'NCPD-' .. data.citizenId })
	if not (called and ok) then
		if price > 0 then core('AddMoney', src, 'money', price, 'example:badge (refund)') end
		return notify(src, 'failed', 'error', { reason = tostring(reason) })
	end
	core('SetMetadata', src, 'exampleBadgeAt', now())
	notify(src, 'badge_taken', 'success', { price = price })
	log('badge', ('took a badge for %d'):format(price), src)
end)

-- Show the badge from the menu: the server checks the item is really carried (the client's greyed row is UX).
onRequest('opx_example:showBadge', function(src)
	local data = character(src)
	if not data then return end
	local called, has = callProvider('inventory', 'HasItem', src, Config.item.name, 1)
	if not called or has ~= true then return notify(src, 'no_badge', 'error') end
	showBadge(src, fullName(data))
end)

-- Stash -------------------------------------------------------------------------------------------------
-- The inventory shows the stash; OUR resource decides who may open it (job, duty, place).
local function atLocker(src)
	local spot = Config.locker
	if type(spot) ~= 'table' then return true end
	local pos = Open77.players.position(src)
	if type(pos) ~= 'table' or pos.bucket ~= (spot.bucket or 0) then return false end
	local dx, dy, dz = pos.x - spot.x, pos.y - spot.y, pos.z - spot.z
	local reach = (spot.radius or 3.0) + Config.serverSlack
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

onRequest('opx_example:locker', function(src)
	if not isOfficer(src, true) then return notify(src, 'not_on_duty', 'error') end
	if not atLocker(src) then return notify(src, 'too_far', 'error') end
	local s = Config.stash
	local called, ok, reason = callProvider('inventory', 'OpenStash', src, s.name,
		{ label = s.label, slots = s.slots, capacityG = s.capacityG })
	if not called then return notify(src, 'no_inventory', 'error') end
	if not ok then return notify(src, 'failed', 'error', { reason = tostring(reason) }) end
	log('locker', 'opened the evidence locker', src)
end)

-- Your own table --------------------------------------------------------------------------------------
-- Per-character data beyond metadata: a table of our own, created at start (callback form, never yields),
-- keyed by citizen id and purged when the character is deleted. Open77.database has query / single /
-- scalar / insert / update (no `execute`); update runs CREATE / DELETE.
local dbReady = false

local SCHEMA = [[CREATE TABLE IF NOT EXISTS opx_example_notes (
	id BIGINT NOT NULL AUTO_INCREMENT,
	citizen_id VARCHAR(32) NOT NULL,
	note VARCHAR(255) NOT NULL,
	created_at BIGINT NOT NULL DEFAULT 0,
	PRIMARY KEY (id),
	KEY idx_opx_example_notes_citizen (citizen_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

CreateThread(function()
	if type(Open77.database) ~= 'table' then return warn('no database bridge: notes disabled') end
	local queued, reason = Open77.database.ready(function()
		Open77.database.update(SCHEMA, {}, function(_, failure)
			if failure then return warn(('schema failed: %s'):format(tostring(failure))) end
			dbReady = true
		end)
	end)
	if not queued then warn(('database unavailable: %s'):format(tostring(reason))) end
end)

-- One line of free text: no control characters, trimmed, at most Config.notes.maxLength bytes (UTF-8 safe).
local function toNote(value)
	if type(value) ~= 'string' then return nil end
	local text = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	local max = Config.notes.maxLength
	if #text > max then
		while max > 0 and (text:byte(max + 1) or 0) >= 0x80 and (text:byte(max + 1) or 0) < 0xC0 do max = max - 1 end
		text = text:sub(1, max)
	end
	return text ~= '' and text or nil
end

onRequest('opx_example:addNote', function(src, value)
	local data = character(src)
	if not data then return end
	if not dbReady then return notify(src, 'no_database', 'error') end
	local text = toNote(value)
	if not text then return notify(src, 'invalid_note', 'error') end
	local cid = data.citizenId
	Open77.database.insert('INSERT INTO opx_example_notes (citizen_id, note, created_at) VALUES (?, ?, ?)',
		{ cid, text, now() }, function(_, failure)
			if failure then return notify(src, 'failed', 'error', { reason = tostring(failure) }) end
			notify(src, 'note_saved', 'success')
			-- Keep the newest Config.notes.perCharacter notes of that character.
			Open77.database.update([[DELETE FROM opx_example_notes WHERE citizen_id = ? AND id NOT IN (
				SELECT id FROM (SELECT id FROM opx_example_notes WHERE citizen_id = ? ORDER BY id DESC LIMIT ?) AS keep)]],
				{ cid, cid, Config.notes.perCharacter }, function(_, why)
					if why then warn(('note pruning failed: %s'):format(tostring(why))) end
				end)
		end)
end)

onRequest('opx_example:notes', function(src)
	local data = character(src)
	if not data then return end
	if not dbReady then return notify(src, 'no_database', 'error') end
	local cid = data.citizenId
	Open77.database.query('SELECT note, created_at FROM opx_example_notes WHERE citizen_id = ? ORDER BY id DESC LIMIT ?',
		{ cid, Config.notes.shown }, function(rows, failure)
			-- The player may have left or switched character while the query ran.
			local still = character(src)
			if not still or still.citizenId ~= cid then return end
			if failure or type(rows) ~= 'table' then return notify(src, 'failed', 'error', { reason = tostring(failure) }) end
			local clock, list = now(), {}
			for _, row in ipairs(rows) do
				if type(row.note) == 'string' then
					local at = math.tointeger(tonumber(row.created_at) or 0) or 0
					list[#list + 1] = { note = row.note, ago = math.max(0, clock - at) }
				end
			end
			pcall(TriggerClientEvent, 'opx_example:notes', src, list)
		end)
end)

AddEventHandler('opx:characterDeleted', function(_, citizenId)
	if type(citizenId) ~= 'string' or not dbReady then return end
	Open77.database.update('DELETE FROM opx_example_notes WHERE citizen_id = ?', { citizenId }, function(_, failure)
		if failure then warn(('notes of %s not purged: %s'):format(citizenId, tostring(failure))) end
	end)
end)

-- Staff action (opx_admin, optional) ----------------------------------------------------------------
-- A row on each player's page of the staff menu. opx_admin raises our HOST event after its ACL check; the
-- handler checks again with CanUse (host events can be raised by any server resource). Never RegisterNetEvent it.
local ADMIN_ID = 'example.badge'
local ADMIN_EVENT = 'opx_example:adminGiveBadge'

local function registerAdminAction()
	if not Config.adminAction or GetResourceState('opx_admin') ~= 'running' then return end
	local ok, added, reason = pcall(Open77.exports.callSync, 'opx_admin', 'AddAction', {
		id = ADMIN_ID, event = ADMIN_EVENT, target = true, icon = 'shield',
		label = { en = 'Give an example badge', fr = "Donner un insigne d'exemple" },
		description = { en = 'opx_example: one badge, no charge.', fr = 'opx_example : un insigne, gratuit.' },
	})
	if not ok or added ~= true then warn(('staff row not added: %s'):format(tostring(ok and reason or added))) end
end

AddEventHandler(ADMIN_EVENT, function(staff, id, targetId)
	local src, target = toSource(staff), toSource(targetId)
	if not src or not target or id ~= ADMIN_ID then return end
	local ok, allowed = pcall(Open77.exports.callSync, 'opx_admin', 'CanUse', src, ADMIN_ID)
	if not ok or allowed ~= true then return end
	local data = character(target)
	if not data then return notify(src, 'target_not_loaded', 'error') end
	local called, added, reason = callProvider('inventory', 'AddItem', target, Config.item.name, 1,
		{ name = fullName(data), number = 'NCPD-' .. data.citizenId })
	if not (called and added) then return notify(src, 'failed', 'error', { reason = tostring(reason) }) end
	notify(src, 'admin_given', 'success', { name = fullName(data) })
	log('admin_badge', ('staff gave a badge to %s'):format(data.citizenId), src)
end)

-- Command ------------------------------------------------------------------------------------------------

if type(Config.command) == 'string' and Config.command ~= '' then
	RegisterCommand(Config.command, function(source)
		local src = toSource(source)
		if not src then return print(('[%s] use this command in game'):format(RESOURCE)) end
		if allow(src) then openMenu(src) end
	end, Config.commandRestricted == true)
end

-- Registrations ------------------------------------------------------------------------------------------
-- Exports are refused while a VM loads: register from onResourceStart (our own start included), and again
-- when the resource holding the registry restarts (its new VM starts empty). On a hot reload of this resource
-- the new VM registers before the others see the old VM stop; they drop by VM generation, so ours stays.
AddEventHandler('onResourceStart', function(name)
	if name == RESOURCE or name == CORE then
		registerJob()
		registerCallback()
	end
	if name == RESOURCE or name == 'opx_admin' then registerAdminAction() end
	if name == RESOURCE or name == provider('inventory') then
		-- Let the inventory finish its own start (its exports, its catalogue) first.
		CreateThread(function()
			Wait(1000)
			registerItem()
		end)
	end
end)

-- Cleanup ------------------------------------------------------------------------------------------------

AddEventHandler('onPlayerDisconnected', function(playerId)
	local src = toSource(playerId)
	if src then lastCall[src] = nil end
end)
