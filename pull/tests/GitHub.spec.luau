local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local GitHub = require(ReplicatedStorage.RbxmPull.GitHubSource)

local API = "https://api.test"
local MANIFEST = {
	schemaVersion = 1,
	commit = string.rep("c", 40),
	ref = "refs/heads/main",
	builtAt = "2026-11-22T10:15:00Z",
	artifact = { size = 3, sha256 = string.rep("0", 64) },
	containers = { "ReplicatedStorage/Systems" },
}

type Route = { status: number, body: string, headers: { [string]: string }? }

-- A fake HTTP function serving `routes` by URL, recording every request.
local function fakeHttp(routes: { [string]: Route })
	local requests = {}
	local function http(request)
		table.insert(requests, request)
		local route = routes[request.Url]
		if route == nil then
			return { StatusCode = 404, Body = '{"message":"Not Found"}', Headers = {} }
		end
		return { StatusCode = route.status, Body = route.body, Headers = route.headers or {} }
	end
	return http, requests
end

local function releaseRoutes(): { [string]: Route }
	return {
		[`{API}/repos/o/r/releases/tags/dev-latest`] = {
			status = 200,
			headers = { etag = 'W/"abc"' },
			body = HttpService:JSONEncode({
				html_url = "https://github.test/o/r/releases/tag/dev-latest",
				body = "notes",
				assets = { { id = 11, name = "managed.rbxm" }, { id = 12, name = "build.json" } },
			}),
		},
		[`{API}/repos/o/r/releases/assets/12`] = { status = 200, body = HttpService:JSONEncode(MANIFEST) },
		[`{API}/repos/o/r/releases/assets/11`] = { status = 200, body = "\0\1\255" },
	}
end

local function source(routes, token: string?)
	local http, requests = fakeHttp(routes)
	return GitHub.new({ repo = "o/r", channel = "dev-latest", token = token, http = http, apiUrl = API }), requests
end

describe("GitHub source", function()
	it("fetches the release and decodes build.json", function()
		local s, requests = source(releaseRoutes())
		local result = s:getManifest(nil) :: any
		expect(result.unchanged).toBe(false)
		expect(result.release.manifest.commit).toBe(MANIFEST.commit)
		expect(result.release.etag).toBe('W/"abc"')
		expect(result.release.artifactAssetId).toBe(11)
		expect(result.release.htmlUrl).toBe("https://github.test/o/r/releases/tag/dev-latest")
		expect(requests[2].Headers.Accept).toBe("application/octet-stream")
		expect(requests[1].Headers.Authorization).toBeNil()
	end)

	it("downloads the artifact as a binary-safe buffer", function()
		local s = source(releaseRoutes())
		local result = s:getManifest(nil) :: any
		local rbxm = s:getArtifact(result.release)
		expect(buffer.len(rbxm)).toBe(3)
		expect(buffer.readu8(rbxm, 2)).toBe(255)
	end)

	it("sends the token and the ETag", function()
		local s, requests = source(releaseRoutes(), "secret")
		s:getManifest('W/"abc"')
		expect(requests[1].Headers.Authorization).toBe("Bearer secret")
		expect(requests[1].Headers["If-None-Match"]).toBe('W/"abc"')
	end)

	it("reports an unchanged release", function()
		local routes = releaseRoutes()
		routes[`{API}/repos/o/r/releases/tags/dev-latest`] = { status = 304, body = "" }
		local s, requests = source(routes)
		expect(s:getManifest('W/"abc"')).toEqual({ unchanged = true })
		expect(#requests).toBe(1)
	end)

	it("explains common failures", function()
		local s = source({})
		expect(function()
			s:getManifest(nil)
		end).toThrow("a private repo needs a GitHub token")

		local limited = source({
			[`{API}/repos/o/r/releases/tags/dev-latest`] = {
				status = 403,
				body = '{"message":"API rate limit exceeded for 1.2.3.4."}',
			},
		})
		expect(function()
			limited:getManifest(nil)
		end).toThrow("rate limit reached; add a token")

		local partial = releaseRoutes()
		partial[`{API}/repos/o/r/releases/tags/dev-latest`].body = HttpService:JSONEncode({ assets = {} })
		expect(function()
			source(partial):getManifest(nil)
		end).toThrow("has no build yet")
	end)

	it("validates the repo and builds commit URLs", function()
		expect(function()
			GitHub.new({ repo = "not a repo", channel = "x" })
		end).toThrow("owner/name")
		local s = source({})
		expect(s:commitUrl("abc")).toBe("https://github.com/o/r/commit/abc")
	end)
end)
