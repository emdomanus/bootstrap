--!nocheck

-- Execute original source in memory with a minimal script tree. No generated runtime files.
local fs = require("@lune/fs")
local Luau = require("@lune/luau")
local task = require("@lune/task")

local function new(onLoad, onWarning)
	local byPath = {}
	local root = {}
	local function scan(path, parent)
		local node = { Parent = parent }
		for _, entry in fs.readDir(path) do
			local childPath = path .. "/" .. entry
			if fs.isDir(childPath) then
				node[entry] = scan(childPath, node)
			elseif entry == "init.luau" then
				-- Rojo turns this directory itself into the ModuleScript.
				node.path = childPath
				byPath[childPath] = node
			elseif entry:sub(-5) == ".luau" then
				local child = { Parent = node, path = childPath }
				node[entry:sub(1, -6)] = child
				byPath[childPath] = child
			end
		end
		return node
	end
	root.bootstrap = scan("src", root)
	root.examples = scan("examples", root)
	local cache, loading = {}, {}
	local function load(node)
		assert(type(node) == "table" and node.path, "Unresolved literal script require")
		if cache[node] ~= nil then
			return cache[node]
		end
		assert(not loading[node], "Circular require: " .. node.path)
		loading[node] = true
		if onLoad then
			onLoad(node.path)
		end
		local execute = Luau.load(fs.readFile(node.path), {
			debugName = node.path,
			environment = {
				script = node,
				warn = onWarning or warn,
				task = task,
				require = function(child)
					return load(child)
				end,
			},
		})
		cache[node] = execute()
		loading[node] = nil
		return cache[node]
	end
	return function(path)
		return load(assert(byPath[path], "Unknown source file: " .. path))
	end
end

return { new = new }
