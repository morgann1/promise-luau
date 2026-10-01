--!strict

local process = require("@lute/process")
const project = require("@root/project")

local function installWallyPackages()
	process.run({
		"wally",
		"install",
	}, {
		stdio = "inherit",
	})
end

local function generateRojoSourcemap()
	process.run({
		"rojo",
		"sourcemap",
		project.TESTS_PROJECT_PATH,
		"--output",
		"sourcemap.json",
	}, {
		stdio = "inherit",
	})
end

local function generateWallyPackageTypes()
	process.run({
		"wally-package-types",
		"--sourcemap",
		"sourcemap.json",
		"DevPackages",
	}, {
		stdio = "inherit",
	})
end

installWallyPackages()
generateRojoSourcemap()
generateWallyPackageTypes()
