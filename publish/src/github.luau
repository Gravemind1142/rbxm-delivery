--!strict
-- The slice of the GitHub REST API that `rbxm-publish release` needs. HTTP goes through a
-- `Transport` so tests can swap in a fake GitHub.

local json = require("@std/json")
local net = require("@std/net")

export type Request = {
	method: string,
	url: string,
	headers: { [string]: string },
	body: string?,
}
export type Response = { status: number, body: string }
export type Transport = (Request) -> Response

export type Asset = { id: number, name: string }
export type Release = {
	id: number,
	htmlUrl: string,
	uploadUrl: string,
	assets: { Asset },
}

local DEFAULT_API_URL = "https://api.github.com"

local function defaultTransport(request: Request): Response
	local response = net.request(request.url, {
		method = request.method,
		headers = request.headers,
		body = request.body,
	})
	return { status = response.status, body = response.body }
end

-- Percent-encodes a path segment or query value. `/` is kept when `keepSlash` is set, since
-- tag names may contain it and the refs API takes it literally.
local function encode(s: string, keepSlash: boolean?): string
	local unsafe = if keepSlash then "[^%w%-%._~/]" else "[^%w%-%._~]"
	return (string.gsub(s, unsafe, function(c: string): string
		return string.format("%%%02X", string.byte(c))
	end))
end

local Client = {}
Client.__index = Client

export type Client = typeof(setmetatable(
	{} :: {
		repo: string,
		apiUrl: string,
		headers: { [string]: string },
		transport: Transport,
	},
	Client
))

local github = {}

function github.new(repo: string, token: string, transport: Transport?, apiUrl: string?): Client
	if not string.match(repo, "^[%w%-%._]+/[%w%-%._]+$") then
		error(`repo '{repo}' must look like owner/name`, 0)
	end
	return setmetatable({
		repo = repo,
		apiUrl = string.gsub(apiUrl or DEFAULT_API_URL, "/+$", ""),
		headers = {
			Accept = "application/vnd.github+json",
			Authorization = `Bearer {token}`,
			["User-Agent"] = "rbxm-publish",
			["X-GitHub-Api-Version"] = "2022-11-28",
		},
		transport = transport or defaultTransport,
	}, Client)
end

local function describe(response: Response): string
	local ok, decoded = pcall(json.deserialize, response.body)
	local object = if ok then json.asObject(decoded) else nil
	local message = if object and typeof(object.message) == "string" then object.message else response.body
	return `{response.status} {message}`
end

-- Sends a request. Returns the decoded JSON body, or nil for a 404 when `allowMissing` is set.
function Client.send(
	self: Client,
	method: string,
	urlOrPath: string,
	body: (string | json.Object)?,
	options: { allowMissing: boolean?, contentType: string? }?
): json.Object?
	local url = if string.sub(urlOrPath, 1, 1) == "/" then self.apiUrl .. urlOrPath else urlOrPath
	local headers = table.clone(self.headers)
	local encoded: string? = nil
	if typeof(body) == "string" then
		encoded = body
		headers["Content-Type"] = options and options.contentType or "application/octet-stream"
	elseif body ~= nil then
		encoded = json.serialize(body)
		headers["Content-Type"] = "application/json"
	end

	local response = self.transport({ method = method, url = url, headers = headers, body = encoded })
	if response.status == 404 and options and options.allowMissing then
		return nil
	end
	if response.status < 200 or response.status >= 300 then
		error(`GitHub API {method} {urlOrPath} failed: {describe(response)}`, 0)
	end
	if response.body == "" then
		return json.object({})
	end
	return json.asObject(json.deserialize(response.body)) or json.object({})
end

function Client.repoPath(self: Client, path: string): string
	return `/repos/{self.repo}{path}`
end

-- The commit a tag points at, or nil if the tag doesn't exist. Annotated tags are followed.
function Client.getTagCommit(self: Client, tag: string): string?
	local ref = self:send("GET", self:repoPath(`/git/ref/tags/{encode(tag, true)}`), nil, { allowMissing = true })
	if ref == nil then
		return nil
	end
	local object = json.asObject(ref.object) :: json.Object
	if object.type == "tag" then
		local annotated = self:send("GET", self:repoPath(`/git/tags/{object.sha}`)) :: json.Object
		object = json.asObject(annotated.object) :: json.Object
	end
	return object.sha :: string
end

function Client.createTag(self: Client, tag: string, commit: string)
	self:send("POST", self:repoPath("/git/refs"), json.object({ ref = `refs/tags/{tag}`, sha = commit }))
end

function Client.moveTag(self: Client, tag: string, commit: string)
	self:send("PATCH", self:repoPath(`/git/refs/tags/{encode(tag, true)}`), json.object({ sha = commit, force = true }))
end

-- How `head` relates to `base`: "ahead", "behind", "identical" or "diverged". Nil if GitHub
-- doesn't know one of the commits (for example after a force push).
function Client.compare(self: Client, base: string, head: string): string?
	local result = self:send("GET", self:repoPath(`/compare/{base}...{head}`), nil, { allowMissing = true })
	return if result then result.status :: string else nil
end

local function toRelease(object: json.Object): Release
	local assets: { Asset } = {}
	for _, value in json.asArray(object.assets) or {} do
		local asset = json.asObject(value) :: json.Object
		table.insert(assets, { id = asset.id :: number, name = asset.name :: string })
	end
	return {
		id = object.id :: number,
		htmlUrl = object.html_url :: string,
		uploadUrl = string.gsub(object.upload_url :: string, "{.*}$", ""),
		assets = assets,
	}
end

function Client.getReleaseByTag(self: Client, tag: string): Release?
	local object = self:send("GET", self:repoPath(`/releases/tags/{encode(tag)}`), nil, { allowMissing = true })
	return if object then toRelease(object) else nil
end

function Client.createRelease(self: Client, tag: string, name: string, body: string): Release
	local object = self:send(
		"POST",
		self:repoPath("/releases"),
		json.object({ tag_name = tag, name = name, body = body, make_latest = "false" })
	)
	return toRelease(object :: json.Object)
end

function Client.updateRelease(self: Client, id: number, name: string, body: string)
	self:send("PATCH", self:repoPath(`/releases/{id}`), json.object({ name = name, body = body }))
end

function Client.uploadAsset(self: Client, release: Release, name: string, contents: string, contentType: string): Asset
	local object =
		self:send("POST", `{release.uploadUrl}?name={encode(name)}`, contents, { contentType = contentType }) :: json.Object
	return { id = object.id :: number, name = object.name :: string }
end

function Client.deleteAsset(self: Client, id: number)
	self:send("DELETE", self:repoPath(`/releases/assets/{id}`))
end

function Client.renameAsset(self: Client, id: number, name: string)
	self:send("PATCH", self:repoPath(`/releases/assets/{id}`), json.object({ name = name }))
end

return github
