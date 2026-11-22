# opx_example

A small NCPD desk written the way a third-party OPX resource should be: a job, an item, a server callback, an eye option, a menu, a stash, logs, a staff row and its own table. The documentation snippets come from it.

## Install
- Not in the default `resources.load`: add it by hand on a test server, after `opx_core`, `opx_menu`, `opx_dialog` and the providers.
- Creates its `opx_example_notes` table at start.
- Needs no other change: the job and the `example_badge` item are registered from code (`RegisterJob`, `RegisterItem` on the inventory provider). There is no item config to edit in the inventory.

## In game
- `setjob me example_leo 1` (staff), then `/example`: the desk menu.
- Menu: go on / off duty, run a plate (form, progress bar, server callback), take a badge (confirm, cash), show it, evidence locker, notes.
- Use the badge in the inventory: the players around you see it.
- Targeting eye on a player, on duty: Check ID.
- Staff menu (F10), a player's page: Give an example badge (`command.opx_admin.example.badge`).

## Config
`config.lua`: `Config.job`, `Config.item`, `Config.badgePrice`, `Config.locker` (nil = anywhere), `Config.command`. Everything else is commented in the file.

## For developers
- Read `server/main.lua` and `client/main.lua` top to bottom: one short block per feature.
- Every optional OPX member (`NotifyLocale`, `GetPlayersByJobType`, client `HasItem`, `OPX.HasJob`) is called under `pcall` with a fallback.
- Registrations are made on its own start and again when `opx_core`, the inventory provider, `opx_admin` or the target provider restart.
- Item: `RegisterItem('example_badge', { label, description, weightG, unique, usable = true })` then `RegisterUsable('example_badge', 'exampleUseBadge')` on `exports.opx_core:GetProvider('inventory')`. The item stays in the catalogue when this resource stops.
- Callback: `OPX.AwaitCallback('opx_example:lookupPlate', plate)` → result table, `false, reason` (refused) or `nil, err` (failed).
- Event: `opx:example:idChecked (officerSource, targetSource)`.
- Full list of what it registers: `types.lua`.
