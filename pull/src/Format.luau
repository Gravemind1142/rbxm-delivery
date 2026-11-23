--!strict
-- Text the widget shows (spec §6.5). Pure functions, so they're testable.

local Apply = require(script.Parent.Apply)
local Marker = require(script.Parent.Apply.Marker)

local Format = {}

function Format.short(commit: string?): string
	return if commit then string.sub(commit, 1, 7) else "—"
end

-- "refs/heads/main" -> "main"
function Format.refName(ref: string): string
	return (string.gsub(ref, "^refs/heads/", ""))
end

-- "2 min ago" for an ISO 8601 time, relative to `now` (unix seconds).
function Format.ago(iso: string?, now: number): string?
	if iso == nil then
		return nil
	end
	local ok, time = pcall(DateTime.fromIsoDate, iso)
	if not ok or time == nil then
		return nil
	end
	local seconds = math.max(0, now - time.UnixTimestamp)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{seconds // 60} min ago`
	elseif seconds < 86400 then
		return `{seconds // 3600} h ago`
	end
	return `{seconds // 86400} d ago`
end

-- "Dev @ abc1234 · main @ def5678 · synced 2 min ago"
function Format.statusLine(state: Marker.State?, manifest: Apply.Manifest?, now: number): string
	local parts = { `Dev @ {Format.short(state and state.commit)}` }
	if manifest then
		table.insert(parts, `{Format.refName(manifest.ref)} @ {Format.short(manifest.commit)}`)
	end
	local ago = Format.ago(state and state.appliedAt, now)
	if ago then
		table.insert(parts, `synced {ago}`)
	end
	return table.concat(parts, " · ")
end

-- "Replaced 3, added 1, removed 1 (abc1234)"
function Format.result(result: Apply.Result): string
	local parts = {}
	for _, item in
		{
			{ "replaced", result.replaced },
			{ "added", result.added },
			{ "removed", result.removed },
		} :: { { any } }
	do
		if #item[2] > 0 then
			table.insert(parts, `{item[1]} {#item[2]}`)
		end
	end
	local summary = if #parts > 0 then table.concat(parts, ", ") else "no containers"
	return `Synced {Format.short(result.commit)}: {summary}.`
end

return Format
