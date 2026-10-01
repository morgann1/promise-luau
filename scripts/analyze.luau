--!strict

local process = require("@lute/process")

local downloadPinned = require("@scripts/lib/downloadPinned")
local project = require("@root/project")
local run = require("@scripts/lib/run")

downloadPinned.downloadPinned(
	`https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/{project.LUAU_LSP_COMMIT}/scripts/globalTypes.d.luau`,
	project.GLOBAL_DEFS_PATH,
	project.LUAU_LSP_GLOBAL_TYPES_SHA256
)

local defaultArgs = table.freeze({
	"analyze",
	`--defs={project.GLOBAL_DEFS_PATH}`,
	"--settings=./.vscode/settings.json",
	`--ignore="**/_Index/**"`,
	`--ignore="**/DevPackages/**"`,
})

local failureCount = 0

do
	local args = table.clone(defaultArgs)
	table.insert(args, "--platform=standard")
	table.insert(args, "--ignore=**/tasks/**")
	table.insert(args, "--flag:LuauSolverV2=true")
	table.insert(args, project.SCRIPTS_PATH)

	local ok = pcall(function()
		run("luau-lsp", args)
	end)

	if not ok then
		failureCount += 1
	end
end

do
	run("rojo", {
		"sourcemap",
		project.TESTS_PROJECT_PATH,
		"-o",
		"sourcemap.json",
	})

	local args = table.clone(defaultArgs)
	table.insert(args, `--sourcemap=sourcemap.json`)
	table.insert(args, project.SOURCE_PATH)
	table.insert(args, "scripts/tasks")

	local ok = pcall(function()
		run("luau-lsp", args)
	end)

	if not ok then
		failureCount += 1
	end
end

process.exit(failureCount)
