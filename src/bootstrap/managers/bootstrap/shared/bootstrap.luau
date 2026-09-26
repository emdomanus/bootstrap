--!strict
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
type BootstrapImpl<C, G> = BootstrapTypes.BootstrapImpl<C, G>
type BootstrapOptions = BootstrapTypes.BootstrapOptions
type BootstrapProfile<C, G> = BootstrapProfileTypes.BootstrapProfile<C, G>
type BootstrapRegistration<C, G> = BootstrapProfileTypes.BootstrapRegistration<C, G>
type BootstrapTelemetryContext = BootstrapTelemetryContextTypes.BootstrapTelemetryContext
type BootstrapTelemetryReader = BootstrapTelemetryReaderTypes.BootstrapTelemetryReader
type BootstrapStatus = BootstrapStatusTypes.BootstrapStatus
type BootstrapPhase = BootstrapStatusTypes.BootstrapPhase
type BootstrapOperationState = BootstrapStatusTypes.BootstrapOperationState
type BootstrapModule = {
	new: <C, G>(profile: BootstrapProfile<C, G>, graphContext: C, options: BootstrapOptions?) -> Bootstrap<G>,
}

local function describeFailure(failure: unknown): string
	return debug.traceback(tostring(failure), 2)
end

local function defaultYield(): ()
	task.wait()
end

local function invoke<C, G>(
	self: BootstrapImpl<C, G>,
	phase: BootstrapPhase,
	name: string?,
	completed: number,
	total: number,
	callback: (BootstrapTelemetryContext) -> ()
): string?
	local telemetryContext = self._bootstrapTelemetry:begin(phase, name, completed, total, self._checkpoint)
	local ok, failure = xpcall(function(): unknown
		self._checkpoint()
		callback(telemetryContext)
		return nil
	end, describeFailure)
	if not ok then
		local message = `Bootstrap {phase} '{name or "graph"}': {tostring(failure)}`
		self._bootstrapTelemetry:finish("failed" :: BootstrapOperationState, completed, message)
		return message
	end
	self._bootstrapTelemetry:finish("completed" :: BootstrapOperationState, completed + 1, nil)
	return nil
end

local function release<C, G>(self: BootstrapImpl<C, G>): string?
	self._status = "deconstructing" :: BootstrapStatus
	local profile = self._profile
	local failures: { string } = {}
	local total = self._entered
	self._resetBudget()
	if profile then
		for index = total, 1, -1 do
			local registration = profile.registrations[index]
			local failure = invoke(
				self,
				"deconstruct" :: BootstrapPhase,
				registration.name,
				total - index,
				total,
				function(telemetryContext)
					registration.deconstruct(self._graphContext, telemetryContext)
				end
			)
			if failure then
				table.insert(failures, failure)
			end
		end
	end
	self._entered = 0
	self._profile = nil
	return if #failures == 0 then nil else table.concat(failures, "\n")
end

local function run<C, G>(self: BootstrapImpl<C, G>): G
	local profile = assert(self._profile, "Bootstrap profile has been released")
	local total = 1 -- Includes the typed graph validation boundary.
	for _, registration in profile.registrations do
		total += 1
		if registration.init then
			total += 1
		end
		if registration.wire then
			total += 1
		end
		if registration.start then
			total += 1
		end
	end
	local completed = 0
	self._status = "constructing" :: BootstrapStatus
	for index, registration in profile.registrations do
		local failure = invoke(
			self,
			"construct" :: BootstrapPhase,
			registration.name,
			completed,
			total,
			function(telemetryContext)
				-- Include a partially failed constructor in rollback. Its deconstructor tolerates absent fields.
				self._entered = index
				registration.construct(self._graphContext, telemetryContext)
			end
		)
		if failure then
			error(failure, 0)
		end
		completed += 1
	end
	self._status = "validating" :: BootstrapStatus
	local graph: G? = nil
	local failure = invoke(self, "validate" :: BootstrapPhase, nil, completed, total, function()
		graph = profile.validate(self._graphContext)
		assert(graph ~= nil, "Graph validation must return a complete graph")
	end)
	if failure then
		error(failure, 0)
	end
	completed += 1
	local readyGraph = assert(graph, "Graph validation did not return a graph")
	self._status = "initializing" :: BootstrapStatus
	for _, registration in profile.registrations do
		local callback = registration.init
		if callback then
			local phaseFailure = invoke(
				self,
				"init" :: BootstrapPhase,
				registration.name,
				completed,
				total,
				function(telemetryContext)
					callback(readyGraph, telemetryContext)
				end
			)
			if phaseFailure then
				error(phaseFailure, 0)
			end
			completed += 1
		end
	end
	self._status = "wiring" :: BootstrapStatus
	for _, registration in profile.registrations do
		local callback = registration.wire
		if callback then
			local phaseFailure = invoke(
				self,
				"wire" :: BootstrapPhase,
				registration.name,
				completed,
				total,
				function(telemetryContext)
					callback(readyGraph, telemetryContext)
				end
			)
			if phaseFailure then
				error(phaseFailure, 0)
			end
			completed += 1
		end
	end
	self._status = "starting" :: BootstrapStatus
	for _, registration in profile.registrations do
		local callback = registration.start
		if callback then
			local phaseFailure = invoke(
				self,
				"start" :: BootstrapPhase,
				registration.name,
				completed,
				total,
				function(telemetryContext)
					callback(readyGraph, telemetryContext)
				end
			)
			if phaseFailure then
				error(phaseFailure, 0)
			end
			completed += 1
		end
	end
	self._status = "running" :: BootstrapStatus
	self._bootstrapTelemetry:terminal("ready" :: BootstrapPhase, completed, total, nil)
	return readyGraph
end

local Bootstrap = {}
Bootstrap.__index = Bootstrap

function Bootstrap.new<C, G>(profile: BootstrapProfile<C, G>, graphContext: C, options: BootstrapOptions?): Bootstrap<G>
	local registrations: { BootstrapRegistration<C, G> } = {}
	local names: { [string]: boolean } = {}
	assert(type(profile.validate) == "function", "Profile requires graph validation")
	for index, registration in profile.registrations do
		assert(
			type(registration.name) == "string" and registration.name:match("%S"),
			"Registration requires a semantic name"
		)
		assert(not names[registration.name], "Duplicate registration name: " .. registration.name)
		assert(
			type(registration.construct) == "function" and type(registration.deconstruct) == "function",
			"Registration requires construct and deconstruct"
		)
		assert(registration.init == nil or type(registration.init) == "function", "Invalid init callback")
		assert(registration.wire == nil or type(registration.wire) == "function", "Invalid wire callback")
		assert(registration.start == nil or type(registration.start) == "function", "Invalid start callback")
		names[registration.name] = true
		registrations[index] = table.freeze(table.clone(registration))
	end
	local budget = if options and options.budgetSeconds ~= nil then options.budgetSeconds else 0.004
	assert(budget == budget and budget >= 0 and budget < math.huge, "Invalid startup budget")
	local clock: () -> number = if options and options.clock then options.clock else os.clock
	local yieldExecution: () -> () = if options and options.yieldExecution then options.yieldExecution else defaultYield
	local sliceStarted = 0
	local function checkpoint(): ()
		if clock() - sliceStarted >= budget then
			yieldExecution()
			sliceStarted = clock()
		end
	end
	local self = (
		setmetatable({
			_profile = table.freeze({ registrations = table.freeze(registrations), validate = profile.validate }),
			_graphContext = graphContext,
			_status = "idle" :: BootstrapStatus,
			_busy = false,
			_entered = 0,
			_checkpoint = checkpoint,
			_resetBudget = function(): ()
				sliceStarted = clock()
			end,
			_bootstrapTelemetry = BootstrapTelemetry.new(clock),
		}, Bootstrap) :: unknown
	) :: BootstrapImpl<C, G>
	return self
end

function Bootstrap.start<C, G>(self: BootstrapImpl<C, G>): G
	assert(not self._bootstrapTelemetry:isNotifying(), "Telemetry observers cannot change the lifecycle")
	assert(not self._busy and self._status == "idle", "Bootstrap can only start once, while idle")
	self._busy = true
	self._resetBudget()
	local ok, result = xpcall(function(): G
		return run(self)
	end, describeFailure)
	if not ok then
		local cleanupFailure = release(self)
		local message = tostring(result)
		if cleanupFailure then
			message ..= "\n" .. cleanupFailure
		end
		self._status = "failed" :: BootstrapStatus
		self._bootstrapTelemetry:terminal("failed" :: BootstrapPhase, 0, 0, message)
		self._bootstrapTelemetry:close()
		self._busy = false
		error(message, 0)
	end
	self._busy = false
	return result :: G
end

function Bootstrap.getStatus<C, G>(self: BootstrapImpl<C, G>): BootstrapStatus
	return self._status
end

function Bootstrap.getTelemetryReader<C, G>(self: BootstrapImpl<C, G>): BootstrapTelemetryReader
	return self._bootstrapTelemetry
end

function Bootstrap.deconstruct<C, G>(self: BootstrapImpl<C, G>): ()
	assert(not self._bootstrapTelemetry:isNotifying(), "Telemetry observers cannot change the lifecycle")
	assert(not self._busy, "Bootstrap cannot deconstruct during an active lifecycle operation")
	local status = self._status
	if status == "stopped" or status == "failed" then
		return
	end
	self._busy = true
	local failure = release(self)
	self._status = (if failure then "failed" else "stopped") :: BootstrapStatus
	self._bootstrapTelemetry:terminal((if failure then "failed" else "stopped") :: BootstrapPhase, 0, 0, failure)
	self._bootstrapTelemetry:close()
	self._busy = false
	if failure then
		error(failure, 0)
	end
end

return table.freeze({ new = Bootstrap.new }) :: BootstrapModule
