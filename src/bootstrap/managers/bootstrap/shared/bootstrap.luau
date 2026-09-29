--!strict
--!optimize 2
--!native
local BootstrapTypes = require(script.Parent.Parent.Parent.Parent.types.managers.bootstrap.shared.bootstrap)
local BootstrapProfileTypes =
	require(script.Parent.Parent.Parent.Parent.types.managers.bootstrap.shared.bootstrapProfile)
local BootstrapTelemetry =
	require(script.Parent.Parent.Parent.Parent.components.bootstrapTelemetry.shared.bootstrapTelemetry)
local BootstrapTelemetryContextTypes = require(
	script.Parent.Parent.Parent.Parent.types.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryContext
)
local BootstrapTelemetryReaderTypes = require(
	script.Parent.Parent.Parent.Parent.types.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryReader
)
local BootstrapStatusTypes = require(script.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
type Bootstrap<G> = BootstrapTypes.Bootstrap<G>
type BootstrapImpl<C, G, StartPhase, StopPhase> = BootstrapTypes.BootstrapImpl<C, G, StartPhase, StopPhase>
type BootstrapOptions<StartPhase, StopPhase> = BootstrapTypes.BootstrapOptions<StartPhase, StopPhase>
type BootstrapProfile<C, G, StartPhase, StopPhase> = BootstrapProfileTypes.BootstrapProfile<C, G, StartPhase, StopPhase>
type BootstrapRegistration<C, G, StartPhase, StopPhase> = BootstrapProfileTypes.BootstrapRegistration<
	C,
	G,
	StartPhase,
	StopPhase
>
type BootstrapCallbacks<C, P> = BootstrapProfileTypes.BootstrapCallbacks<C, P>
type BootstrapShutdown<C> = BootstrapProfileTypes.BootstrapShutdown<C>
type BootstrapTelemetryContext = BootstrapTelemetryContextTypes.BootstrapTelemetryContext
type BootstrapTelemetryReader = BootstrapTelemetryReaderTypes.BootstrapTelemetryReader
type BootstrapStatus = BootstrapStatusTypes.BootstrapStatus
type BootstrapOperationState = BootstrapStatusTypes.BootstrapOperationState
type BootstrapModule = {
	new: <C, G, StartPhase, StopPhase>(
		BootstrapProfile<C, G, StartPhase, StopPhase>,
		C,
		BootstrapOptions<StartPhase, StopPhase>
	) -> Bootstrap<G>,
}

local function describeFailure(failure: unknown): string
	return debug.traceback(tostring(failure), 2)
end

local function defaultYield(): ()
	task.wait()
end

local function arrayLength<T>(values: { T }): number
	local count = 0
	for key in values do
		assert(type(key) == "number" and key >= 1 and key % 1 == 0, "Expected a dense ordered array")
		count += 1
	end
	for index = 1, count do
		assert(values[index] ~= nil, "Expected a dense ordered array")
	end
	return count
end

local function capturePhases<P>(phases: { P }): ({ P }, { [P]: number })
	local order: { P } = {}
	local positions: { [P]: number } = {}
	for index = 1, arrayLength(phases) do
		local phase = phases[index]
		assert(type(phase) == "string" and tostring(phase):match("%S"), "Phase requires a nonblank string")
		assert(positions[phase] == nil, "Duplicate phase: " .. tostring(phase))
		order[index], positions[phase] = phase, index
	end
	return order, positions
end

local function captureCallbacks<C, P>(
	callbacks: BootstrapCallbacks<C, P>,
	positions: { [P]: number }
): BootstrapCallbacks<C, P>
	local captured: BootstrapCallbacks<C, P> = {}
	for phase, callback in callbacks do
		local position = positions[phase]
		assert(position ~= nil, "Callback assigned to undeclared phase: " .. tostring(phase))
		assert(type(callback) == "function", "Invalid phase callback")
		captured[phase] = callback
	end
	return captured
end

local function checkName(name: string, names: { [string]: boolean }): ()
	assert(type(name) == "string" and name:match("%S"), "Registration requires a semantic name")
	assert(not names[name], "Duplicate registration name: " .. name)
	names[name] = true
end

local function invoke<C, G, StartPhase, StopPhase>(
	self: BootstrapImpl<C, G, StartPhase, StopPhase>,
	phase: string,
	name: string?,
	completed: number,
	total: number,
	callback: (BootstrapTelemetryContext) -> ()
): string?
	local telemetryContext = self._bootstrapTelemetry:begin(phase, name, completed, total, self._checkpoint)
	local cancelled = false
	local ok, failure = xpcall(function(): unknown
		self._checkpoint()
		-- Pacing can yield before entry too. Never acquire an owner after cancellation at that boundary.
		if self._status == "creating" and self._destroyRequested then
			cancelled = true
		else
			callback(telemetryContext)
		end
		return nil
	end, describeFailure)
	if not ok then
		local message = `Bootstrap {phase} '{name or "graph"}': {tostring(failure)}`
		self._bootstrapTelemetry:finish("failed" :: BootstrapOperationState, completed, message)
		return message
	end
	self._bootstrapTelemetry:finish(
		(if cancelled then "cancelled" else "completed") :: BootstrapOperationState,
		if cancelled then completed else completed + 1,
		nil
	)
	return nil
end

local function release<C, G, StartPhase, StopPhase>(self: BootstrapImpl<C, G, StartPhase, StopPhase>, cause: string?): ()
	self._status = "destroying" :: BootstrapStatus
	local profile = assert(self._profile, "Bootstrap profile has been released")
	local failures: { string } = {}
	if cause then
		table.insert(failures, cause)
	end
	local shutdown = profile.shutdown or {}
	local total = #shutdown
	for index = 1, #profile.registrations do
		if self._entered[index] then
			total += 1
		end -- Final destructor.
	end
	for _, phase in self._stopPhases do
		for index, registration in profile.registrations do
			if self._entered[index] and registration.stop[phase] then
				total += 1
			end
		end
	end
	local completed = 0
	self._resetBudget()
	-- Critical work has priority over every ordinary stop/destructor, even from idle.
	for _, operation in shutdown do
		local failure = invoke(self, "shutdown", operation.name, completed, total, function(context)
			operation.run(self._graphContext, context)
		end)
		if failure then
			table.insert(failures, failure)
		end
		completed += 1
	end
	for _, phase in self._stopPhases do
		for index, registration in profile.registrations do
			local callback = registration.stop[phase]
			if self._entered[index] and callback then
				local failure = invoke(self, tostring(phase), registration.name, completed, total, function(context)
					callback(self._graphContext, context)
				end)
				if failure then
					table.insert(failures, failure)
				end
				completed += 1
			end
		end
	end
	-- All stop attempts finish before final resource release, in reverse acquisition order.
	for index = #profile.registrations, 1, -1 do
		if self._entered[index] then
			local registration = profile.registrations[index]
			local failure = invoke(self, "destroy", registration.name, completed, total, function(context)
				registration.destroy(self._graphContext, context)
			end)
			if failure then
				table.insert(failures, failure)
			end
			completed += 1
		end
	end
	table.clear(self._entered)
	self._profile = nil
	self._failure = if #failures > 0 then table.concat(failures, "\n") else nil
	self._status = (if self._failure then "failed" else "stopped") :: BootstrapStatus
	self._bootstrapTelemetry:terminal(self._status, 0, 0, self._failure)
	self._bootstrapTelemetry:close()
	self._owner = nil
end

local function run<C, G, StartPhase, StopPhase>(self: BootstrapImpl<C, G, StartPhase, StopPhase>): G?
	local profile = assert(self._profile, "Bootstrap profile has been released")
	local total = #profile.registrations + 1 -- Constructors plus graph validation.
	for _, phase in self._startPhases do
		for _, registration in profile.registrations do
			if registration.start[phase] then
				total += 1
			end
		end
	end
	local completed = 0
	for index, registration in profile.registrations do
		if self._destroyRequested then
			return nil
		end
		local failure = invoke(self, "construct", registration.name, completed, total, function(context)
			-- Enter before invoking: a throwing constructor may already own partial resources.
			self._entered[index] = true
			registration.construct(self._graphContext, context)
		end)
		if failure then
			error(failure, 0)
		end
		completed += 1
	end
	if self._destroyRequested then
		return nil
	end
	local graph: G? = nil
	local failure = invoke(self, "validate", nil, completed, total, function()
		graph = profile.validate(self._graphContext)
		assert(graph ~= nil, "Graph validation must return a complete graph")
	end)
	if failure then
		error(failure, 0)
	end
	completed += 1
	if self._destroyRequested then
		return nil
	end
	local readyGraph = assert(graph, "Graph validation did not return a graph")
	for _, phase in self._startPhases do
		for _, registration in profile.registrations do
			if self._destroyRequested then
				return nil
			end
			local callback = registration.start[phase]
			if callback then
				local phaseFailure = invoke(
					self,
					tostring(phase),
					registration.name,
					completed,
					total,
					function(context)
						callback(readyGraph, context)
					end
				)
				if phaseFailure then
					error(phaseFailure, 0)
				end
				completed += 1
			end
		end
	end
	if self._destroyRequested then
		return nil
	end
	self._status = "running" :: BootstrapStatus
	self._bootstrapTelemetry:terminal("ready", completed, total, nil)
	return readyGraph
end

local function create<C, G, StartPhase, StopPhase>(self: BootstrapImpl<C, G, StartPhase, StopPhase>): G
	assert(not self._bootstrapTelemetry:isNotifying(), "Telemetry observers cannot change the lifecycle")
	assert(self._status == "idle", "Bootstrap can only create once, while idle")
	self._owner = coroutine.running()
	self._status = "creating" :: BootstrapStatus
	self._resetBudget()
	local ok, result = xpcall(function(): G?
		return run(self)
	end, describeFailure)
	if not ok then
		release(self, tostring(result))
		error(self._failure, 0)
	end
	if self._destroyRequested then
		release(self, nil)
		error(self._failure or "Bootstrap creation cancelled by destruction", 0)
	end
	self._owner = nil
	return assert(result, "Creation did not return a graph")
end

local function destroy<C, G, StartPhase, StopPhase>(self: BootstrapImpl<C, G, StartPhase, StopPhase>): ()
	assert(not self._bootstrapTelemetry:isNotifying(), "Telemetry observers cannot change the lifecycle")
	assert(self._owner ~= coroutine.running(), "Reentrant lifecycle calls cannot join their own operation")
	self._destroyRequested = true
	if self._owner then
		-- Other callers join the active owner. Only that owner may mutate or release resources.
		repeat
			self._yieldExecution()
		until self._owner == nil
	elseif self._status ~= "stopped" and self._status ~= "failed" then
		self._owner = coroutine.running()
		release(self, nil)
	end
	if self._failure then
		error(self._failure, 0)
	end
end

local function new<C, G, StartPhase, StopPhase>(
	profile: BootstrapProfile<C, G, StartPhase, StopPhase>,
	graphContext: C,
	options: BootstrapOptions<StartPhase, StopPhase>
): Bootstrap<G>
	local startPhases, startPositions = capturePhases(options.startPhases)
	local stopPhases, stopPositions = capturePhases(options.stopPhases)
	assert(type(profile.validate) == "function", "Profile requires graph validation")
	local registrations: { BootstrapRegistration<C, G, StartPhase, StopPhase> } = {}
	local names: { [string]: boolean } = {}
	for index = 1, arrayLength(profile.registrations) do
		local registration = profile.registrations[index]
		checkName(registration.name, names)
		assert(type(registration.construct) == "function", "Registration requires a construct callback")
		assert(type(registration.destroy) == "function", "Registration requires a destroy callback")
		registrations[index] = {
			name = registration.name,
			construct = registration.construct,
			start = captureCallbacks(registration.start, startPositions),
			stop = captureCallbacks(registration.stop, stopPositions),
			destroy = registration.destroy,
		}
	end
	local shutdown: { BootstrapShutdown<C> } = {}
	local shutdownNames: { [string]: boolean } = {}
	if profile.shutdown then
		for index = 1, arrayLength(profile.shutdown) do
			local operation = profile.shutdown[index]
			checkName(operation.name, shutdownNames)
			assert(type(operation.run) == "function", "Invalid shutdown callback")
			shutdown[index] = { name = operation.name, run = operation.run }
		end
	end
	local budget = if options.budgetSeconds ~= nil then options.budgetSeconds else 0.004
	assert(budget == budget and budget >= 0 and budget < math.huge, "Invalid execution budget")
	local clock = options.clock or os.clock
	local yieldExecution = options.yieldExecution or defaultYield
	local sliceStarted = 0
	local self: BootstrapImpl<C, G, StartPhase, StopPhase> = {
		_profile = {
			registrations = registrations,
			validate = profile.validate,
			shutdown = shutdown,
		},
		_startPhases = startPhases,
		_stopPhases = stopPhases,
		_graphContext = graphContext,
		_status = "idle" :: BootstrapStatus,
		_owner = nil,
		_destroyRequested = false,
		_entered = {},
		_failure = nil,
		_checkpoint = function(): ()
			if clock() - sliceStarted >= budget then
				yieldExecution()
				sliceStarted = clock()
			end
		end,
		_resetBudget = function(): ()
			sliceStarted = clock()
		end,
		_yieldExecution = yieldExecution,
		_bootstrapTelemetry = BootstrapTelemetry.new(clock),
	}
	local application: Bootstrap<G> = {
		create = function(): G
			return create(self)
		end,
		destroy = function(): ()
			destroy(self)
		end,
		getStatus = function(): BootstrapStatus
			return self._status
		end,
		getTelemetryReader = function(): BootstrapTelemetryReader
			return self._bootstrapTelemetry
		end,
	}
	return table.freeze(application)
end

local Bootstrap: BootstrapModule = { new = new }
return table.freeze(Bootstrap)
