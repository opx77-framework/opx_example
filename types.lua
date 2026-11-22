---@meta

-- opx_example: LuaLS annotations (not loaded by the manifest). A reference resource: nothing here is a
-- contract other resources should build on. It lists what opx_example registers ELSEWHERE and the exports
-- that only exist so OPX can call it back. Every export below is SYNCHRONOUS on our side (nothing waits).

-- Registered on its own start and again when the holder restarts (onResourceStart):
--   opx_core      RegisterJob(Config.job.name, { label, type = 'leo', defaultDuty, data = { bossGrade }, grades })
--                 RegisterCallback('opx_example:lookupPlate', 'exampleLookupPlate')
--   inventory     RegisterItem(Config.item.name, { label, description, weightG, unique, usable = true })
--                 (provider from opx_core GetProvider('inventory'); nothing registered when there is none)
--                 RegisterUsable(Config.item.name, 'exampleUseBadge')
--   opx_admin     AddAction({ id = 'example.badge', event = 'opx_example:adminGiveBadge', target = true, ... })
--                 when opx_admin runs and Config.adminAction (ACL right command.opx_admin.example.badge)
--   target (client) addPlayer({ name = 'opx_example_check_id', canInteract = 'exampleCanCheckId',
--                 serverEvent = 'opx_example:checkId' }), again when the target provider restarts.
-- Optional members called under pcall with a fallback: opx_core NotifyLocale (fallback: own relay event
-- opx_example:notify), GetPlayersByJobType (fallback: GetPlayersByJob), client OPX.HasJob / OPX.OnJobChanged
-- (fallback: PlayerData), inventory client HasItem (fallback: server decides).

---@class OpxExamplePlateResult
---@field plate string upper-case
---@field owner string "Firstname Lastname"
---@field record string TweakDB record the car was given with

---@alias OpxExamplePlateError
---| 'not_on_duty' the caller is not on duty in Config.job.name
---| 'invalid_plate' not a string of 1..10 letters, digits, spaces or dashes
---| 'not_found' no owned car with that plate (or its owner is unknown)

---@class OpxExampleServerExports
local server = {}

--- Server callback export (opx_core calls it for OPX.AwaitCallback('opx_example:lookupPlate', plate)).
--- `source` is set by opx_core. A refusal is `false, reason`; the client reads `nil, reason` when the callback
--- itself failed ('timeout', 'rate_limited', 'unknown_callback', 'callback_failed', 'send_failed').
---@param source integer
---@param plate string
---@return OpxExamplePlateResult|false result
---@return OpxExamplePlateError|nil reason
function server.exampleLookupPlate(source, plate) end

--- Usable handler (the inventory calls it when a player uses Config.item.name). Shows the badge to the loaded
--- players within Config.showDistance in the same bucket. Returns false: the badge is not consumed.
---@param source integer
---@param item string
---@param instanceId? string
---@param meta? { name?: string, number?: string }
---@return boolean consumed
function server.exampleUseBadge(source, item, instanceId, meta) end

---@class OpxExampleClientExports
local client = {}

--- canInteract of the "Check ID" eye option: true when the local character is on duty in Config.job.name.
---@return boolean
function client.exampleCanCheckId() end

-- Host event (server, AddEventHandler), raised after a successful "Check ID":
--   opx:example:idChecked (officerSource: integer, targetSource: integer)
-- Host event handled (never a net event): opx_example:adminGiveBadge (staff, actionId, targetId), raised by
-- opx_admin after its ACL check; re-checked with exports.opx_admin:CanUse.

-- Net events (internal, listed for reviewers). Every client request is rate limited (Config.rateLimitMs) and
-- checked on the server (source, character, job, duty, distance, bucket, life state, item).
-- client -> server: opx_example:open (), opx_example:duty (wanted: boolean), opx_example:takeBadge (),
--                   opx_example:showBadge (), opx_example:locker (), opx_example:addNote (text: string),
--                   opx_example:notes (), opx_example:checkId (targetId, info) — the eye option's serverEvent
-- server -> client: opx_example:open ({ officer, onDuty, officers, price, item }),
--                   opx_example:notes ({ note, ago }[]), opx_example:notify (key, kind, params) — fallback relay

-- Table (MySQL, CREATE TABLE IF NOT EXISTS at start): opx_example_notes (id, citizen_id, note, created_at unix).
-- Config.notes.perCharacter newest rows kept per character; rows purged on opx:characterDeleted.
-- Metadata written: exampleBadgeAt (unix seconds of the last badge taken, for Config.badgeCooldownSeconds).
-- Log lines (logs provider, category 'example'): plate, check_id, duty, badge, locker, admin_badge.
