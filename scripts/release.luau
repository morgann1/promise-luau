--!strict

--[[
	Cuts a release. Builds Promise.rbxm, creates the GitHub release with this version's
		CHANGELOG.md section as its notes, then publishes the model to the Creator Store.

	Usage: lute scripts/release.luau <tag>

	Needs ROBLOX_API_KEY with Assets API read and write access, and gh signed in (GH_TOKEN
		in CI). Updates the model in ROBLOX_ASSET_ID, or creates one when it's unset. Open
		Cloud can't turn on Creator Store distribution, so a new model needs that toggled in
		Creator Hub once.
]]

local fs = require("@lute/fs")
local json = require("@std/json")
local net = require("@std/net")
local process = require("@std/process")
local task = require("@std/task")

const RBXM_PATH = "Promise.rbxm"
const CREATOR_USER_ID = 48044582
const ASSETS_URL = "https://apis.roblox.com/assets/v1"
const BOUNDARY = "promise-luau-release"

local function readFile(path: string): string
	const handle = fs.open(path, "r")
	const contents = fs.read(handle)
	fs.close(handle)

	return contents
end

local function run(args: { string })
	print(`> {table.concat(args, " ")}`)

	const result = process.run(args, { stdio = "inherit" })
	if not result.ok then
		error(`{args[1]} exited with code {result.exitcode}`)
	end
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

	const args = { "gh", "release", "create", tag, RBXM_PATH, "--title", tag, "--notes", notes }
	if string.find(tag, "-", 1, true) ~= nil then
		table.insert(args, "--prerelease")
	end

	run(args)
end

local function requestJson(url: string, metadata: net.Metadata): any
	const response = net.request(url, metadata)
	if not response.ok then
		error(`{metadata.method or "GET"} {url} failed with HTTP {response.status}: {response.body}`)
	end

	return json.deserialize(response.body)
end

local function publishToCreatorStore(apiKey: string, assetId: string?)
	const request = json.object({
		assetType = "Model",
		displayName = "Promise",
		description = "An implementation of Promise similar to Promise/A+.",
		creationContext = json.object({
			creator = json.object({ userId = CREATOR_USER_ID }),
		}),
	})
	if assetId ~= nil then
		request.assetId = tonumber(assetId)
	end

	-- The Assets API takes the request JSON and the model file as multipart form fields.
	const body = table.concat({
		`--{BOUNDARY}\r\n`,
		`Content-Disposition: form-data; name="request"\r\n\r\n`,
		json.serialize(request),
		`\r\n--{BOUNDARY}\r\n`,
		`Content-Disposition: form-data; name="fileContent"; filename="{RBXM_PATH}"\r\n`,
		"Content-Type: model/x-rbxm\r\n\r\n",
		readFile(RBXM_PATH),
		`\r\n--{BOUNDARY}--\r\n`,
	})

	print(if assetId ~= nil then `Updating Creator Store model {assetId}` else "Creating Creator Store model")

	local operation = requestJson(if assetId ~= nil then `{ASSETS_URL}/assets/{assetId}` else `{ASSETS_URL}/assets`, {
		method = if assetId ~= nil then "PATCH" else "POST",
		body = body,
		headers = {
			["x-api-key"] = apiKey,
			["Content-Type"] = `multipart/form-data; boundary={BOUNDARY}`,
		},
	})

	-- The upload finishes asynchronously, so poll its operation.
	const operationUrl = `{ASSETS_URL}/{operation.path}`
	for _ = 1, 30 do
		if operation.done then
			break
		end

		task.wait(2)
		operation = requestJson(operationUrl, { headers = { ["x-api-key"] = apiKey } })
	end

	if not operation.done then
		error("timed out waiting for the Creator Store upload")
	end

	if operation.error ~= nil and operation.error ~= json.null then
		error(`Creator Store upload failed: {json.serialize(operation.error)}`)
	end

	const publishedId = operation.response.assetId
	print(`Published https://create.roblox.com/store/asset/{publishedId}`)

	if assetId == nil then
		print(
			`::notice::Created model {publishedId}. Set the ROBLOX_ASSET_ID variable to it so later releases update it, then turn on Distribute on Creator Store in Creator Hub.`
		)
	end
end

const tag = process.args[2]
if tag == nil then
	error("usage: lute scripts/release.luau <tag>")
end

const apiKey = process.env.ROBLOX_API_KEY
if apiKey == nil or apiKey == "" then
	error("set ROBLOX_API_KEY to an Open Cloud key with Assets API read and write access")
end

-- GitHub passes an unset variable as an empty string.
const assetId = process.env.ROBLOX_ASSET_ID
const existingAssetId = if assetId == nil or assetId == "" then nil else assetId

const notes = readReleaseNotes((string.gsub(tag, "^v", "")))

run({ "rojo", "build", "default.project.json", "-o", RBXM_PATH })
createGitHubRelease(tag, notes)
publishToCreatorStore(apiKey, existingAssetId)
