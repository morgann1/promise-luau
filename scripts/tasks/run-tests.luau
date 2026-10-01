--!strict
-- Runs inside Roblox Studio through run-in-roblox. Errors fail the run.

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Jest = require(ReplicatedStorage.DevPackages.Jest)
const root = ReplicatedStorage

const status, result = Jest.runCLI(root, {
	verbose = false,
	ci = false,
}, { root }):awaitStatus()

if status ~= "Resolved" then
	print(result)
	error("Jest did not finish")
end

if result.results.numFailedTestSuites > 0 or result.results.numFailedTests > 0 then
	error("Tests failed")
end
