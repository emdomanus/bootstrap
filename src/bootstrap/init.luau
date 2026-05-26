--!strict
--!optimize 2
--!native

local IsServer = game:GetService("RunService"):IsServer()

export type BootstrapPhase = string
export type BootstrapAPI<SharedT, ServerT, ClientT> = {
	shared: SharedT,
	server: ServerT,
	client: ClientT,
}

local function bootstrapify<SharedT, ServerT, ClientT>(
	shared: SharedT,
	server: ServerT,
	client: ClientT,
	phases: { BootstrapPhase }
): BootstrapAPI<SharedT, ServerT, ClientT>
	local subj = if IsServer then server else client
	local candidates = { subj, shared :: any }
	local api = {
		shared = shared,
		server = server,
		client = client,
	} :: any

	for _, phase in phases do
		for _, obj in candidates do
			if obj == nil then
				continue
			end

			local phaseFn = (obj :: any)[phase]
			if phaseFn and typeof(phaseFn) == "function" then
				api[phase] = function()
					(phaseFn :: (any) -> ())(obj)
				end
				break
			end
		end
	end

	return api
end

local function collectModules(roots: { Instance }, modules: { { [unknown]: unknown } })
	for _, root in roots do
		if root:IsA("ModuleScript") then
			local ok, result = pcall(require, root)
			if ok then
				table.insert(modules, result)
			else
				warn(`Failed to require {root.Name}: {tostring(result)}`)
			end
		elseif root:IsA("Folder") then
			collectModules(root:GetChildren(), modules)
		end
	end
end

local function runPhaseAsync(modules: { { [unknown]: unknown } }, phase: BootstrapPhase)
	local nThreads = 0
	local cThreads = 0

	for _, module in modules do
		local fn = (module :: any)[phase]
		if fn and typeof(fn) == "function" then
			nThreads += 1
			task.spawn(function()
				local ok, err = xpcall(fn, debug.traceback)
				if not ok then
					warn(`Phase "{phase}" failed:\n{err}`)
				end
				cThreads += 1
			end)
		end
	end

	while cThreads < nThreads do
		task.wait()
	end
end

local function bootstrap(roots: { Instance }, phases: { BootstrapPhase }): { { [unknown]: unknown } }
	local modules: { { [unknown]: unknown } } = {}
	collectModules(roots, modules)

	for _, phase in phases do
		runPhaseAsync(modules, phase)
	end

	return modules
end

return {
	bootstrap = bootstrap,
	bootstrapify = bootstrapify,
}
