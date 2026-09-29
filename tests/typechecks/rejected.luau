--!strict
local Bootstrap = require(script.Parent.Parent.bootstrap)
local SampleProfile = require(script.Parent.Parent.examples.sampleProfile)
local SampleProfileTypes = require(script.Parent.Parent.examples.types.managers.sample.shared.sampleProfile)
type SampleStartPhase = SampleProfileTypes.SampleStartPhase
type SampleStopPhase = SampleProfileTypes.SampleStopPhase
type SampleGraphContext = SampleProfileTypes.SampleGraphContext
type SampleGraph = SampleProfileTypes.SampleGraph
local profile = SampleProfile.new({
	initialValue = 1,
	report = function(_value: number) end,
	display = function(_text: string) end,
})
local graphContext: SampleGraphContext = {}
local application = Bootstrap.new(profile, graphContext, {
	startPhases = {
		"init" :: SampleStartPhase,
		"wire" :: SampleStartPhase,
		"activate" :: SampleStartPhase,
	},
	stopPhases = { "quiesce" :: SampleStopPhase, "persist" :: SampleStopPhase },
})
local wrongStartOptions: Bootstrap.BootstrapOptions<SampleStopPhase, SampleStopPhase> = {
	startPhases = { "quiesce" :: SampleStopPhase },
	stopPhases = { "quiesce" :: SampleStopPhase },
}
Bootstrap.new(profile, graphContext, wrongStartOptions) -- reject
local wrongStopOptions: Bootstrap.BootstrapOptions<SampleStartPhase, SampleStartPhase> = {
	startPhases = { "wire" :: SampleStartPhase },
	stopPhases = { "wire" :: SampleStartPhase },
}
Bootstrap.new(profile, graphContext, wrongStopOptions) -- reject
local graph = application:create()
local wrong: string = graph.sampleCounter:get() -- reject
graphContext.sampleCounter = 3 -- reject
graph.sampleReporter:wire({
	get = function()
		return "wrong" -- reject
	end,
})
local registration: Bootstrap.BootstrapRegistration<SampleGraphContext, SampleGraph, SampleStartPhase, SampleStopPhase> =
	{ -- reject
		name = "Missing callbacks",
	}
local wrongStart: SampleStartPhase = "release" -- reject
local wrongStop: SampleStopPhase = "construct" -- reject
local invalidCallbacks: Bootstrap.BootstrapCallbacks<SampleGraph, SampleStartPhase> = {}
invalidCallbacks["release"] = function() end -- reject
local invalidCleanup: Bootstrap.BootstrapCallbacks<SampleGraphContext, SampleStopPhase> = {}
invalidCleanup["construct"] = function() end -- reject
local function rejectRegistrationShape(_value: Bootstrap.BootstrapRegistration<
	SampleGraphContext,
	SampleGraph,
	SampleStartPhase,
	SampleStopPhase
>): () end
rejectRegistrationShape({ name = "No construct", start = {}, stop = {}, destroy = function() end }) -- reject
rejectRegistrationShape({ name = "No destroy", construct = function() end, start = {}, stop = {} }) -- reject
application:start() -- reject
application:deconstruct() -- reject
local function misuse(context: Bootstrap.BootstrapTelemetryContext)
	local callback = invalidCallbacks["wire" :: SampleStartPhase]
	callback(graph, context) -- reject
	local stop = invalidCleanup["quiesce" :: SampleStopPhase]
	stop(graphContext, context) -- reject
	context:setField("resource", "models") -- reject
	context:setProgress(1, 2) -- reject
	context:getReader():createTask("forbidden") -- reject
	local task = context:createTask("Work")
	task:setStatus(42) -- reject
	task:setProgress("one", 2) -- reject
	task:getReader():complete() -- reject
	task:getReader():setStatus("forbidden") -- reject
	task:getReader()._state = "active" -- reject
	context:start() -- reject
	context.checkpoint = function() end -- reject
end
application._status = "running" -- reject
local status: Bootstrap.BootstrapStatus = "ready" -- reject
local outcome: Bootstrap.BootstrapTelemetryTaskState = "guardingEntries" -- reject
return {
	wrongStart = wrongStart,
	wrongStop = wrongStop,
	invalidCallbacks = invalidCallbacks,
	invalidCleanup = invalidCleanup,
	wrong = wrong,
	registration = registration,
	misuse = misuse,
	status = status,
	outcome = outcome,
}
