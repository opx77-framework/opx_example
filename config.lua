Config = {}

-- The job this resource registers in opx_core (RegisterJob). `type` is what other scripts count by
-- (GetPlayersByJobType('leo')): keep 'leo' for a police job. Give it with `setjob me example_leo 0`.
-- grades: contiguous from 0. bossGrade: grade from which opx_society treats a holder as the boss.
Config.job = {
	name = 'example_leo',
	label = 'NCPD (example)',
	type = 'leo',
	defaultDuty = false,
	bossGrade = 1,
	grades = {
		[0] = { name = 'cadet', label = 'Cadet', salary = 150 },
		[1] = { name = 'officer', label = 'Officer', salary = 250 },
	},
}

-- The item this resource registers in the inventory catalogue at start (RegisterItem through the
-- 'inventory' provider). It exists only while some resource registers it: there is no item config elsewhere.
-- label / description: text, or { en = '...', fr = '...' }. weightG: grams, integer.
Config.item = {
	name = 'example_badge',
	label = { en = 'NCPD badge (example)', fr = 'Insigne NCPD (exemple)' },
	description = { en = 'A badge from the example desk. Use it to show it.', fr = "Un insigne du bureau d'exemple. Utilisez-le pour le montrer." },
	weightG = 100,
	unique = true,
}

-- Price of a badge at the desk menu (cash, opx_core account `money`). 0 = free.
Config.badgePrice = 50

-- Seconds before the same character may take another badge (kept in his opx_core metadata).
Config.badgeCooldownSeconds = 300

-- Metres: players who see a badge being shown, and the reach of "Check ID" in the targeting eye.
Config.showDistance = 4.0
Config.checkIdDistance = 3.0

-- Extra metres the server accepts on top of a distance (its position snapshot can lag a tick behind).
Config.serverSlack = 1.5

-- Evidence locker (an inventory stash). Only on-duty holders of the job open it.
-- name: [a-z0-9_.-], 48 characters. slots 1..200, capacityG in grams.
Config.stash = { name = 'example_evidence', label = 'Evidence locker', slots = 30, capacityG = 50000 }

-- Where the locker opens: nil = anywhere (test bench), or { x, y, z, radius, bucket } in metres.
-- Example: Config.locker = { x = -1188.3, y = 2006.9, z = 7.8, radius = 3.0, bucket = 0 }
Config.locker = nil

-- Notes kept in this resource's own table (opx_example_notes): longest note in bytes, notes kept per
-- character (older ones are deleted), notes listed in the menu.
Config.notes = { maxLength = 120, perCharacter = 20, shown = 10 }

-- Milliseconds of the progress bar before a plate is run (0 = none).
Config.plateProgressMs = 2000

-- Command that opens the desk menu. nil = no command.
Config.command = 'example'
-- true: the command needs the ACL right `command.<name>`.
Config.commandRestricted = false

-- true: adds a "Give an example badge" row to each player's page of the opx_admin menu (when opx_admin runs).
-- ACL right: command.opx_admin.example.badge
Config.adminAction = true

-- Minimum milliseconds between two requests of one player (anything faster is ignored).
Config.rateLimitMs = 400

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
