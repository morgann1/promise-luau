--!strict

--[[
	Creates the GitHub release for a tag, with this version's CHANGELOG.md section as its
		notes.

	Usage: lute scripts/release.luau <tag>

	Needs gh signed in (GH_TOKEN in CI).
]]

local fs = require("@lute/fs")
local process = require("@std/process")

local function readFile(path: string): string
	const handle = fs.open(path, "r")
	const contents = fs.read(handle)
	fs.close(handle)

	return contents
end

local function readReleaseNotes(version: string): string
	const heading = `## [{version}]`
	const lines = {}
	local found = false

	for _, line in string.split(readFile("CHANGELOG.md"), "\n") do
		if string.sub(line, 1, #heading) == heading then
			found = true
			continue
		end

		if found and string.sub(line, 1, 3) == "## " then
			break
		end

		if found then
			table.insert(lines, line)
		end
	end

	const notes = string.match(table.concat(lines, "\n"), "^%s*(.-)%s*$")
	if notes == nil or notes == "" then
		error(`CHANGELOG.md has no "{heading}" section`)
	end

	return notes
end

local function createGitHubRelease(tag: string, notes: string)
	if process.run({ "gh", "release", "view", tag }).ok then
		print(`GitHub release {tag} already exists, skipping`)
		return
	end

	const args = { "gh", "release", "create", tag, "--title", tag, "--notes", notes }
	if string.find(tag, "-", 1, true) ~= nil then
		table.insert(args, "--prerelease")
	end

	print(`> gh release create {tag}`)

	const result = process.run(args, { stdio = "inherit" })
	if not result.ok then
		error(`gh exited with code {result.exitcode}`)
	end
end

const tag = process.args[2]
if tag == nil then
	error("usage: lute scripts/release.luau <tag>")
end

createGitHubRelease(tag, readReleaseNotes((string.gsub(tag, "^v", ""))))
