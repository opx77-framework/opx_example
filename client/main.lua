-- opx_example client: the desk menu, the targeting-eye option and the translations. It shows and asks;
-- the server decides. Every predicate here (job, item) is UX only: the server checks it again.

local OPX = assert(require('@opx_core'))
local Menu = assert(require('@opx_menu'))

local T = OPX.Locale()
local main = nil  -- the open desk menu, or nil
local badgePrice = 0 -- price of a badge, from the last state the server sent

-- Notifications ------------------------------------------------------------------------------------------
-- With NotifyLocale, opx_core's client library (running in this VM) translates the server's keys with our
-- locales by itself. This relay is the fallback for an opx_core without it.
RegisterNetEvent('opx_example:notify', function(key, kind, params)
	if type(key) ~= 'string' then return end
	OPX.Notify(T(key, type(params) == 'table' and params or {}), kind, nil, T('title'))
end)

-- Job and item predicates (UX only) ---------------------------------------------------------------------

-- Our job, on duty when onDutyOnly. OPX.HasJob (newer opx_core) or the same test on PlayerData.
local function hasJob(onDutyOnly)
	if type(OPX.HasJob) == 'function' then return OPX.HasJob(Config.job.name, 0, onDutyOnly) == true end
	local job = OPX.GetJob()
	return type(job) == 'table' and job.name == Config.job.name and job.available ~= false
		and (not onDutyOnly or job.onDuty == true)
end

-- Whether the player carries the item: true / false, or nil when the inventory cannot tell on the client
-- (no provider, or one without the client export HasItem): then the row stays enabled and the server decides.
local function carries(item)
	local inventory = OPX.GetProvider('inventory')
	if not inventory then return nil end
	local ok, has = pcall(Open77.exports.callSync, inventory, 'HasItem', item, 1)
	if not ok or type(has) ~= 'boolean' then return nil end
	return has
end

-- React to job changes: OPX.OnJobChanged (newer opx_core) or OnPlayerData('job'). The open menu follows.
local function onJobChanged()
	if main and main:isOpen() then TriggerServerEvent('opx_example:open') end
end
if type(OPX.OnJobChanged) == 'function' then
	OPX.OnJobChanged(onJobChanged)
else
	OPX.OnPlayerData(function(key) if key == 'job' then onJobChanged() end end)
end

OPX.OnPlayerUnloaded(function()
	if main then main:close() end
	main = nil
end)

-- Run a plate: form, progress bar, server callback ------------------------------------------------------

-- The progress provider's Start waits: Open77.exports.call(...):await(), from a thread. No provider = no bar.
-- The result is a client outcome, never a proof for the server.
local function progress(label, duration)
	local name = OPX.GetProvider('progress')
	if not name or duration <= 0 then return true end
	local pending = Open77.exports.call(name, 'Start', {
		label = label, duration = duration, disableMovement = true, animation = { profile = 'tablet' },
	})
	if not pending then return true end
	local ok, reason = pending:await()
	return ok == true, reason
end

-- Refusals of our export that have their own text (plate_<reason> in the locales).
local PLATE_REASONS = { not_on_duty = true, invalid_plate = true, not_found = true }

local function runPlate()
	local values = Menu.dialog({
		title = T('plate_title'), submitLabel = T('plate_run'),
		fields = { { name = 'plate', label = T('plate'), type = 'text', maxLength = 10 } },
	})
	if not values or type(values.plate) ~= 'string' then return end
	if not progress(T('plate_progress'), Config.plateProgressMs) then return end
	-- Yields until the server answers: (result) | (false, reason) refused by our export | (nil, err) failed.
	local result, reason = OPX.AwaitCallback('opx_example:lookupPlate', values.plate)
	if type(result) == 'table' then
		OPX.Notify(T('plate_result', { plate = result.plate, owner = result.owner }), 'info', nil, T('title'))
	elseif PLATE_REASONS[reason] then
		OPX.Notify(T('plate_' .. reason), 'error', nil, T('title'))
	else
		OPX.Notify(T('failed', { reason = tostring(reason) }), 'error', nil, T('title'))
	end
end

-- Notes ------------------------------------------------------------------------------------------------

local function ago(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < 60 then return T('ago_now') end
	if seconds < 3600 then return T('ago_min', { n = math.floor(seconds / 60) }) end
	if seconds < 86400 then return T('ago_hour', { n = math.floor(seconds / 3600) }) end
	return T('ago_day', { n = math.floor(seconds / 86400) })
end

local function writeNote()
	local values = Menu.dialog({
		title = T('note_add'), submitLabel = T('save'),
		fields = { { name = 'note', label = T('note'), type = 'text', maxLength = Config.notes.maxLength } },
	})
	if values and type(values.note) == 'string' then TriggerServerEvent('opx_example:addNote', values.note) end
end

RegisterNetEvent('opx_example:notes', function(list)
	if type(list) ~= 'table' or not (main and main:isOpen()) then return end
	local elements = {}
	for _, row in ipairs(list) do
		if type(row) == 'table' and type(row.note) == 'string' then
			elements[#elements + 1] = { label = row.note, value = #elements + 1, icon = 'edit', description = ago(row.ago) }
		end
	end
	if #elements == 0 then elements[1] = { label = T('notes_empty'), value = 'empty', disabled = true } end
	Menu.open({ id = 'opx_example_notes', title = T('notes'), parent = main, elements = elements })
end)

-- Desk menu ----------------------------------------------------------------------------------------------
-- onSelect runs in its own thread: Menu.confirm, Menu.dialog and OPX.AwaitCallback may wait there.

local function onSelect(element, menu)
	local action = element.value
	if action == 'duty' then
		TriggerServerEvent('opx_example:duty', not hasJob(true))
	elseif action == 'plate' then
		runPlate()
	elseif action == 'badge' then
		if Menu.confirm({ title = T('badge_take'), message = T('badge_confirm', { price = OPX.FormatMoney(badgePrice) }),
			confirmLabel = T('take'), cancelLabel = T('cancel') }) then
			TriggerServerEvent('opx_example:takeBadge')
		end
	elseif action == 'show' then
		TriggerServerEvent('opx_example:showBadge')
	elseif action == 'locker' then
		menu:close()
		TriggerServerEvent('opx_example:locker')
	elseif action == 'note_add' then
		writeNote()
	elseif action == 'notes' then
		TriggerServerEvent('opx_example:notes')
	else
		menu:close()
	end
end

RegisterNetEvent('opx_example:open', function(state)
	if type(state) ~= 'table' then return end
	local officer, onDuty = state.officer == true, state.onDuty == true
	local price = math.tointeger(tonumber(state.price) or 0) or 0
	badgePrice = price
	local hasBadge = carries(Config.item.name)
	main = Menu.open({
		id = 'opx_example', title = T('title'), subtitle = T('officers', { n = tonumber(state.officers) or 0 }),
		elements = {
			{ label = T(onDuty and 'duty_end' or 'duty_start'), value = 'duty', icon = 'shield', disabled = not officer,
				rightLabel = T(onDuty and 'on' or 'off'), description = T(officer and 'duty_desc' or 'not_officer') },
			{ label = T('plate_title'), value = 'plate', icon = 'car', disabled = not onDuty, description = T('plate_desc') },
			{ label = T('badge_take'), value = 'badge', icon = 'card', disabled = not onDuty or state.item ~= true,
				rightLabel = price > 0 and OPX.FormatMoney(price) or T('free'), description = T('badge_desc') },
			{ label = T('badge_show'), value = 'show', icon = 'eye', disabled = hasBadge == false,
				description = T(hasBadge == false and 'no_badge' or 'badge_show_desc') },
			{ label = T('locker'), value = 'locker', icon = 'box', disabled = not onDuty, description = T('locker_desc') },
			{ label = T('note_add'), value = 'note_add', icon = 'edit', description = T('note_desc') },
			{ label = T('notes'), value = 'notes', icon = 'list' },
			{ label = T('close'), value = 'close', icon = 'close' },
		},
		onSelect = onSelect,
		onClose = function(menu) if main == menu then main = nil end end,
	})
end)

-- Targeting eye ------------------------------------------------------------------------------------------
-- Through the target provider's client exports (no manifest dependency on it). The option sends
-- TriggerServerEvent('opx_example:checkId', targetId, info); canInteract names our export (exactly true shows it).
exports('exampleCanCheckId', function() return hasJob(true) == true end)

local function registerTarget()
	local target = OPX.GetProvider('target')
	if not target then return end
	local pending = Open77.exports.call(target, 'addPlayer', {
		{ name = 'opx_example_check_id', label = T('check_id'), icon = 'id', description = T('check_id_desc'),
		  distance = Config.checkIdDistance, canInteract = 'exampleCanCheckId', serverEvent = 'opx_example:checkId' },
	})
	if not pending then return end
	local id, reason = pending:await()
	if not id then print('[opx_example] eye option refused: ' .. tostring(reason)) end
end

CreateThread(registerTarget)

-- The target provider (re)started: its registry is empty, register again.
AddEventHandler('onClientResourceStart', function(name)
	CreateThread(function()
		Wait(500)
		if name == OPX.GetProvider('target') then registerTarget() end
	end)
end)
