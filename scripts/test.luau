--!strict

const process = require("@lute/process")
const project = require("@root/project")

const PLACE_PATH = "tests.rbxl"
const TASK_PATH = "scripts/tasks/run-tests.luau"

const build = process.run({
	"rojo",
	"build",
	project.TESTS_PROJECT_PATH,
	"--output",
	PLACE_PATH,
}, {
	stdio = "inherit",
})

if not build.ok then
	print("ERROR: failed to build the test place")
	process.exit(1)
end

-- run-in-roblox opens a copy of the place in Studio, runs the task as a plugin,
-- and exits with code 1 if Studio logs an error.
const tests = process.run({
	"run-in-roblox",
	"--place",
	PLACE_PATH,
	"--script",
	TASK_PATH,
}, {
	stdio = "inherit",
})

process.exit(tests.exitcode)
