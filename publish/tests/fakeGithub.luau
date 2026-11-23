--!strict
-- An in-memory GitHub that implements just the endpoints rbxm-publish calls, as a Transport.
-- Not a test file itself (no .test suffix).

local json = require("@std/json")

local github = require("../src/github")

local API = "https://api.test"
local UPLOADS = "https://uploads.test"
local REPO = "owner/game"

export type Asset = { id: number, name: string, contents: string, contentType: string }
export type Release = {
	id: number,
	tag: string,
	name: string,
	body: string,
	makeLatest: string?,
	assets: { Asset },
}

export type Fake = {
	-- Commits in history order; compare() uses positions in this list.
	history: { string },
	refs: { [string]: string },
	releases: { Release },
	calls: { string },
	-- When set, the first request whose "METHOD path" matches this pattern fails with a 500.
	failOn: string?,
	client: (self: Fake) -> github.Client,
	release: (self: Fake, tag: string) -> Release?,
	asset: (self: Fake, tag: string, name: string) -> Asset?,
}

local fake = {}
fake.REPO = REPO

local function respond(status: number, value: json.Value?): github.Response
	return { status = status, body = if value == nil then "" else json.serialize(value) }
end

local function releaseJson(r: Release): json.Object
	local assets: json.Array = {}
	for _, a in r.assets do
		table.insert(assets, json.object({ id = a.id, name = a.name }))
	end
	return json.object({
		id = r.id,
		tag_name = r.tag,
		html_url = `https://github.test/{REPO}/releases/tag/{r.tag}`,
		upload_url = `{UPLOADS}/repos/{REPO}/releases/{r.id}/assets\{?name,label}`,
		assets = assets,
	})
end

local function decodeQuery(s: string): string
	return (
		string.gsub(s, "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) :: number)
		end)
	)
end

function fake.new(history: { string }): Fake
	local self = {
		history = history,
		refs = {},
		releases = {},
		calls = {},
		failOn = nil,
	} :: Fake
	local nextId = 100

	local function id(): number
		nextId += 1
		return nextId
	end

	local function findAsset(assetId: number): (Release?, number?)
		for _, r in self.releases do
			for i, a in r.assets do
				if a.id == assetId then
					return r, i
				end
			end
		end
		return nil, nil
	end

	local function handle(request: github.Request): github.Response
		local prefix = `{API}/repos/{REPO}`
		local uploadPrefix = `{UPLOADS}/repos/{REPO}`
		local path: string
		if string.sub(request.url, 1, #prefix) == prefix then
			path = string.sub(request.url, #prefix + 1)
		elseif string.sub(request.url, 1, #uploadPrefix) == uploadPrefix then
			path = "upload:" .. string.sub(request.url, #uploadPrefix + 1)
		else
			return respond(404, json.object({ message = `unknown host in {request.url}` }))
		end
		local call = `{request.method} {path}`
		table.insert(self.calls, call)

		if self.failOn and string.find(call, self.failOn) then
			self.failOn = nil
			return respond(500, json.object({ message = "injected failure" }))
		end
		if request.headers.Authorization ~= "Bearer test-token" then
			return respond(401, json.object({ message = "Bad credentials" }))
		end
		local body = if request.body and request.headers["Content-Type"] == "application/json"
			then json.asObject(json.deserialize(request.body))
			else nil
		local method = request.method

		local tag = string.match(path, "^/git/ref/tags/(.+)$")
		if method == "GET" and tag then
			local sha = self.refs[tag]
			if sha == nil then
				return respond(404, json.object({ message = "Not Found" }))
			end
			return respond(200, json.object({ object = json.object({ type = "commit", sha = sha }) }))
		end

		if method == "POST" and path == "/git/refs" and body then
			local name = string.match(body.ref :: string, "^refs/tags/(.+)$") :: string
			if self.refs[name] then
				return respond(422, json.object({ message = "Reference already exists" }))
			end
			self.refs[name] = body.sha :: string
			return respond(201, json.object({}))
		end

		tag = string.match(path, "^/git/refs/tags/(.+)$")
		if method == "PATCH" and tag and body then
			if self.refs[tag] == nil then
				return respond(422, json.object({ message = "Reference does not exist" }))
			end
			self.refs[tag] = body.sha :: string
			return respond(200, json.object({}))
		end

		local base, head = string.match(path, "^/compare/(%x+)%.%.%.(%x+)$")
		if method == "GET" and base and head then
			local baseIndex = table.find(self.history, base)
			local headIndex = table.find(self.history, head)
			if baseIndex == nil or headIndex == nil then
				return respond(404, json.object({ message = "Not Found" }))
			end
			local status = if headIndex > baseIndex
				then "ahead"
				elseif headIndex < baseIndex then "behind"
				else "identical"
			return respond(200, json.object({ status = status }))
		end

		tag = string.match(path, "^/releases/tags/(.+)$")
		if method == "GET" and tag then
			local r = self:release(decodeQuery(tag))
			return if r then respond(200, releaseJson(r)) else respond(404, json.object({ message = "Not Found" }))
		end

		if method == "POST" and path == "/releases" and body then
			local tagName = body.tag_name :: string
			if self.refs[tagName] == nil then
				-- Real GitHub would create the tag from the default branch here.
				return respond(422, json.object({ message = "test fake: tag must exist first" }))
			end
			local r: Release = {
				id = id(),
				tag = tagName,
				name = body.name :: string,
				body = body.body :: string,
				makeLatest = body.make_latest :: string?,
				assets = {},
			}
			table.insert(self.releases, r)
			return respond(201, releaseJson(r))
		end

		local releaseId = tonumber(string.match(path, "^/releases/(%d+)$"))
		if method == "PATCH" and releaseId and body then
			for _, r in self.releases do
				if r.id == releaseId then
					r.name = body.name :: string
					r.body = body.body :: string
					return respond(200, releaseJson(r))
				end
			end
			return respond(404, json.object({ message = "Not Found" }))
		end

		local uploadId, name = string.match(path, "^upload:/releases/(%d+)/assets%?name=(.+)$")
		if method == "POST" and uploadId and name then
			name = decodeQuery(name)
			for _, r in self.releases do
				if r.id == tonumber(uploadId) then
					for _, a in r.assets do
						if a.name == name then
							return respond(422, json.object({ message = "already_exists" }))
						end
					end
					local a: Asset = {
						id = id(),
						name = name,
						contents = request.body or "",
						contentType = request.headers["Content-Type"],
					}
					table.insert(r.assets, a)
					return respond(201, json.object({ id = a.id, name = a.name }))
				end
			end
			return respond(404, json.object({ message = "Not Found" }))
		end

		local assetId = tonumber(string.match(path, "^/releases/assets/(%d+)$"))
		if assetId and (method == "DELETE" or method == "PATCH") then
			local r, index = findAsset(assetId)
			if r == nil or index == nil then
				return respond(404, json.object({ message = "Not Found" }))
			end
			if method == "DELETE" then
				table.remove(r.assets, index)
				return respond(204)
			end
			local newName = (body :: json.Object).name :: string
			for _, a in r.assets do
				if a.name == newName then
					return respond(422, json.object({ message = "already_exists" }))
				end
			end
			r.assets[index].name = newName
			return respond(200, json.object({ id = assetId, name = newName }))
		end

		return respond(404, json.object({ message = `fake has no route for {call}` }))
	end

	function self.client(fakeSelf: Fake): github.Client
		return github.new(REPO, "test-token", handle, API)
	end

	function self.release(fakeSelf: Fake, tagName: string): Release?
		for _, r in fakeSelf.releases do
			if r.tag == tagName then
				return r
			end
		end
		return nil
	end

	function self.asset(fakeSelf: Fake, tagName: string, assetName: string): Asset?
		local r = fakeSelf:release(tagName)
		if r then
			for _, a in r.assets do
				if a.name == assetName then
					return a
				end
			end
		end
		return nil
	end

	return self
end

return fake
