resource "opx_example"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- OPX//77 reference resource: a small NCPD desk written the way a third-party script should be written.
-- Source of the documentation snippets and in-game test bench of the OPX APIs. NOT in the default
-- resources.load: add it by hand on a test server.
-- It registers a job (type 'leo'), an item with a usable handler, a server callback, a targeting-eye option
-- with a server event, an opx_menu menu with confirms and forms, a stash, log lines, an opx_admin row and its
-- own table (opx_example_notes). The target, inventory, progress and logs resources are found through
-- opx_core's provider slots (no dependency); opx_admin is optional (used when it runs).
-- opx_menu and opx_dialog are dependencies because require('@...') only loads a declared, running one.
dependencies {
    "opx_core",
    "opx_menu",
    "opx_dialog",
}

permissions {
    "database.access",   -- server: opx_example_notes (schema at start, inserts, reads, purge)
    "network.events",    -- both: requests to the server, answers and notifications to the client
    "players.life.read", -- server: Open77.players.isDead (a downed officer cannot check an id)
    "http.request", -- server: Open77.http.get (update check, Config.versionCheck)
}

shared_script "config.lua"

server_script "server/main.lua"
server_script "server/version.lua"

client_script "client/main.lua"

files {
    "locales/*.json",
}
