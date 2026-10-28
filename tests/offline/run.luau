-- Offline tests for server logic. Run from the repo root: lune run tests/offline/run
local process = require("@lune/process")
local H = require("./harness")
require("./tests")(H)
process.exit(if H.run() == 0 then 0 else 1)
