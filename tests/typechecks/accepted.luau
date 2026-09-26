--!strict
local Bootstrap = require(script.Parent.Parent.bootstrap)
local SampleProfile = require(script.Parent.Parent.examples.sampleProfile)
local SampleProfileTypes = require(script.Parent.Parent.examples.types.managers.sample.shared.sampleProfile)
type SampleGraph = SampleProfileTypes.SampleGraph
type SampleGraphContext = SampleProfileTypes.SampleGraphContext
type BootstrapTelemetryContext = Bootstrap.BootstrapTelemetryContext
local graphContext: SampleGraphContext = {}
local profile = SampleProfile.new({
	initialValue = 3,
	report = function(value: number)
		print(value)
	end,
	display = function(text: string)
		print(text)
	end,
})
local application: Bootstrap.Bootstrap<SampleGraph> = Bootstrap.new(profile, graphContext)
local reader: Bootstrap.BootstrapTelemetryReader = application:getTelemetryReader()
reader:bindToPhaseChanged(function(phase: Bootstrap.BootstrapPhase)
	print(phase)
end)
reader:bindToTaskAdded(function(task: Bootstrap.BootstrapTelemetryTaskReader)
	task:bindToStatusChanged(function(status: string?)
		print(status)
	end)
	task:bindToProgressChanged(function(completed: number?, total: number?)
		print(completed, total)
	end)
	task:bindToStateChanged(function(state: Bootstrap.BootstrapTelemetryTaskState)
		print(state)
	end)
end)
local graph: SampleGraph = application:start()
local value: number = graph.sampleCounter:get()
application:deconstruct()
local function writeTelemetry(context: BootstrapTelemetryContext): ()
	local task: Bootstrap.BootstrapTelemetryTask = context:createTask("Load models")
	local taskReader: Bootstrap.BootstrapTelemetryTaskReader = task:getReader()
	task:setStatus("Waiting for models")
	task:setProgress(1, 2)
	task:clearProgress()
	context:checkpoint()
	task:complete()
	reader:forEachTask(function(activeTask)
		print(activeTask:getName())
	end, "construct" :: Bootstrap.BootstrapPhase)
	print(taskReader:getState())
end
return { value = value, writeTelemetry = writeTelemetry }
