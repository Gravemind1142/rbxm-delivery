--!strict
-- Builds from a rolling GitHub release (spec §6.1). Other hosts can implement the same
-- `getManifest` / `getArtifact` interface.
--
-- HTTP goes through an injectable `Http` function (HttpService:RequestAsync by default) so
-- tests can use a fake. Findings from probing Studio's HttpService:
--   - It refuses a `User-Agent` header, and sends its own, which GitHub accepts.

local HttpService = game:GetService("HttpService")

local Apply = require(script.Parent.Apply)

export type HttpRequest = { Url: string, Method: string, Headers: { [string]: string } }
export type HttpResponse = { StatusCode: number, Body: string, Headers: { [string]: string } }
export type Http = (HttpRequest) -> HttpResponse

export type Options = {
	repo: string,
	channel: string,
	token: string?,
	http: Http?,
	apiUrl: string?,
}

export type Release = {
	manifest: Apply.Manifest,
	-- For the next conditional request.
	etag: string?,
	htmlUrl: string?,
	body: string?,
	artifactAssetId: number,
}

-- `unchanged` when the release hasn't changed since `etag`.
export type ManifestResult = { unchanged: true } | { unchanged: false, release: Release }

local API_URL = "https://api.github.com"

local GitHub = {}
GitHub.__index = GitHub

export type Source = typeof(setmetatable(
	{} :: {
		repo: string,
		channel: string,
		token: string?,
		http: Http,
		apiUrl: string,
	},
	GitHub
))

local function defaultHttp(request: HttpRequest): HttpResponse
	local response = HttpService:RequestAsync(request :: any)
	return { StatusCode = response.StatusCode, Body = response.Body, Headers = response.Headers }
end

-- Percent-encodes a URL path segment, keeping RFC 3986 unreserved characters
-- (HttpService:UrlEncode escapes those too, e.g. "-" as %2D).
local function encodeSegment(s: string): string
	return (
		string.gsub(s, "[^%w%-%._~]", function(c: string): string
			return string.format("%%%02X", string.byte(c))
		end)
	)
end

local function header(headers: { [string]: string }, name: string): string?
	local lower = string.lower(name)
	for key, value in headers do
		if string.lower(key) == lower then
			return value
		end
	end
	return nil
end

function GitHub.new(options: Options): Source
	if not string.match(options.repo, "^[%w%-%._]+/[%w%-%._]+$") then
		error(`repo '{options.repo}' must look like owner/name`, 0)
	end
	return setmetatable({
		repo = options.repo,
		channel = options.channel,
		token = if options.token and options.token ~= "" then options.token else nil,
		http = options.http or defaultHttp,
		apiUrl = options.apiUrl or API_URL,
	}, GitHub)
end

function GitHub.request(self: Source, path: string, accept: string, extra: { [string]: string }?): HttpResponse
	local headers: { [string]: string } = {
		Accept = accept,
		["X-GitHub-Api-Version"] = "2022-11-28",
	}
	if self.token then
		headers.Authorization = `Bearer {self.token}`
	end
	for key, value in extra or {} do
		headers[key] = value
	end
	local ok, response = pcall(self.http, { Url = self.apiUrl .. path, Method = "GET", Headers = headers })
	if not ok then
		error(`couldn't reach GitHub: {response}`, 0)
	end
	return response
end

local function describeFailure(response: HttpResponse, what: string, hasToken: boolean): string
	local message = ""
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body)
	if ok and typeof(decoded) == "table" and typeof(decoded.message) == "string" then
		message = decoded.message
	end
	if response.StatusCode == 404 then
		return `{what} not found{if hasToken then "" else " (a private repo needs a GitHub token)"}`
	elseif response.StatusCode == 401 then
		return "GitHub rejected the token (expired or revoked?)"
	elseif response.StatusCode == 403 or response.StatusCode == 429 then
		if string.find(message, "rate limit", 1, true) then
			return `GitHub rate limit reached{if hasToken then "" else "; add a token for a higher limit"}`
		end
	end
	return `{what}: GitHub answered {response.StatusCode} {message}`
end

-- Fetches the channel's release and its build.json. Pass the previous `etag` to get
-- `{ unchanged = true }` when nothing changed.
function GitHub.getManifest(self: Source, etag: string?): ManifestResult
	local response = self:request(
		`/repos/{self.repo}/releases/tags/{encodeSegment(self.channel)}`,
		"application/vnd.github+json",
		if etag then { ["If-None-Match"] = etag } else nil
	)
	if response.StatusCode == 304 then
		return { unchanged = true }
	end
	if response.StatusCode ~= 200 then
		error(describeFailure(response, `release '{self.channel}' in {self.repo}`, self.token ~= nil), 0)
	end

	local release = HttpService:JSONDecode(response.Body)
	local manifestId, artifactId
	for _, asset in release.assets or {} do
		if asset.name == "build.json" then
			manifestId = asset.id
		elseif asset.name == "managed.rbxm" then
			artifactId = asset.id
		end
	end
	if manifestId == nil or artifactId == nil then
		error(`release '{self.channel}' has no build yet (or is mid-publish); try again shortly`, 0)
	end

	local manifestResponse = self:request(`/repos/{self.repo}/releases/assets/{manifestId}`, "application/octet-stream")
	if manifestResponse.StatusCode ~= 200 then
		error(describeFailure(manifestResponse, "build.json", self.token ~= nil), 0)
	end

	return {
		unchanged = false,
		release = {
			manifest = Apply.Manifest.decode(manifestResponse.Body),
			etag = header(response.Headers, "ETag"),
			htmlUrl = release.html_url,
			body = release.body,
			artifactAssetId = artifactId,
		},
	}
end

-- Downloads managed.rbxm for a release from getManifest. Verification is Apply's job.
function GitHub.getArtifact(self: Source, release: Release): buffer
	local response =
		self:request(`/repos/{self.repo}/releases/assets/{release.artifactAssetId}`, "application/octet-stream")
	if response.StatusCode ~= 200 then
		error(describeFailure(response, "managed.rbxm", self.token ~= nil), 0)
	end
	return buffer.fromstring(response.Body)
end

-- The GitHub page for a commit, for "Open commit".
function GitHub.commitUrl(self: Source, commit: string): string
	return `https://github.com/{self.repo}/commit/{commit}`
end

return GitHub
