--!strict
local Bootstrap = require(script.Parent.Parent.bootstrap)
local SampleProfile = require(script.Parent.Parent.examples.sampleProfile)
local SampleProfileTypes = require(script.Parent.Parent.examples.types.managers.sample.shared.sampleProfile)
type SampleGraphContext = SampleProfileTypes.SampleGraphContext
type SampleGraph = SampleProfileTypes.SampleGraph
local profile = SampleProfile.new({
	initialValue = 1,
	report = function(_value: number) end,
	display = function(_text: string) end,
})
local graphContext: SampleGraphContext = {}
local application = Bootstrap.new(profile, graphContext)
local graph = application:start()
local wrong: string = graph.sampleCounter:get() -- reject
graphContext.sampleCounter = 3 -- reject
graph.sampleReporter:wire({
	get = function()
		return "wrong" -- reject
	end,
})
local registration: Bootstrap.BootstrapRegistration<SampleGraphContext, SampleGraph> = { -- reject
	name = "Missing callbacks",
}
local function misuse(context: Bootstrap.BootstrapTelemetryContext)
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
return { wrong = wrong, registration = registration, misuse = misuse, status = status, outcome = outcome }
