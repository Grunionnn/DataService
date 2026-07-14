-->> Dependencies

local Types = require(script.Parent.Types)

-->> Module

local Utils = {}

-->> Path helpers

function Utils.NormalizePath(path: Types.Path): { Types.PathKey }
	if type(path) == "string" then
		assert(path ~= "", "Path cannot be empty")
		return path:split(".")
	end

	assert(#path > 0, "Path cannot be empty")
	return table.clone(path)
end

function Utils.ResolveParent(root: { [any]: any }, path: { Types.PathKey }): ({ [any]: any }, Types.PathKey)
	assert(#path > 0, "Path cannot be empty")

	local parent = root

	for index = 1, #path - 1 do
		local key = path[index]
		local nextValue = parent[key]

		assert(type(nextValue) == "table", `Cannot resolve path: value at key {key} is not a table`)

		parent = nextValue
	end

	return parent, path[#path]
end

function Utils.PathToString(path: { Types.PathKey }): string
	local parts = {}

	for index, key in path do
		if type(key) == "number" then
			parts[index] = `n:{key}`
		else
			parts[index] = `s:{#key}:{key}`
		end
	end

	return table.concat(parts, "|")
end

function Utils.IsArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end

	local count = 0
	local highestIndex = 0

	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end

		count += 1
		highestIndex = math.max(highestIndex, key)
	end

	return highestIndex == count
end

-->> Table helpers

function Utils.DeepCopy(original: any): any
	if typeof(original) ~= "table" then
		return original
	end

	local copy = {}
	for key, value in original do
		copy[key] = Utils.DeepCopy(value)
	end

	return copy
end

-->> Return

return Utils
