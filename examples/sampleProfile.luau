--!strict
local Bootstrap = require(script.Parent.Parent.bootstrap)
local SampleProfileTypes = require(script.Parent.types.managers.sample.shared.sampleProfile)
type SampleGraphContext = SampleProfileTypes.SampleGraphContext
type SampleGraph = SampleProfileTypes.SampleGraph
type SampleOptions = SampleProfileTypes.SampleOptions
type BootstrapTelemetryContext = Bootstrap.BootstrapTelemetryContext
type BootstrapProfile = Bootstrap.BootstrapProfile<SampleGraphContext, SampleGraph>
type SampleProfileModule = { new: (options: SampleOptions) -> BootstrapProfile }

local function new(options: SampleOptions): BootstrapProfile
	return {
		registrations = {
			{
				name = "Loading Display",
				construct = function(graphContext: SampleGraphContext, telemetryContext: BootstrapTelemetryContext): ()
					local SampleLoadingDisplay = require(script.Parent.components.sample.shared.sampleLoadingDisplay)
					graphContext.sampleLoadingDisplay =
						SampleLoadingDisplay.new(telemetryContext:getReader(), options.display)
				end,
				deconstruct = function(graphContext: SampleGraphContext): ()
					local sampleLoadingDisplay = graphContext.sampleLoadingDisplay
					graphContext.sampleLoadingDisplay = nil
					if sampleLoadingDisplay then
						sampleLoadingDisplay:deconstruct()
					end
				end,
			},
			{
				name = "Counter",
				construct = function(graphContext: SampleGraphContext, telemetryContext: BootstrapTelemetryContext): ()
					local task = telemetryContext:createTask("Prepare counter")
					task:setStatus("Creating initial value")
					local SampleCounter = require(script.Parent.components.sample.shared.sampleCounter)
					graphContext.sampleCounter = SampleCounter.new(options.initialValue)
					task:setProgress(1, 1)
					task:complete()
				end,
				deconstruct = function(graphContext: SampleGraphContext): ()
					local sampleCounter = graphContext.sampleCounter
					graphContext.sampleCounter = nil
					if sampleCounter then
						sampleCounter:deconstruct()
					end
				end,
			},
			{
				name = "Reporter",
				construct = function(graphContext: SampleGraphContext): ()
					local SampleReporter = require(script.Parent.components.sample.shared.sampleReporter)
					graphContext.sampleReporter = SampleReporter.new(options.report)
				end,
				wire = function(graphContext: SampleGraph): ()
					graphContext.sampleReporter:wire(graphContext.sampleCounter)
				end,
				start = function(graphContext: SampleGraph): ()
					graphContext.sampleReporter:start()
				end,
				deconstruct = function(graphContext: SampleGraphContext): ()
					local sampleReporter = graphContext.sampleReporter
					graphContext.sampleReporter = nil
					if sampleReporter then
						sampleReporter:deconstruct()
					end
				end,
			},
		},
		validate = function(graphContext: SampleGraphContext): SampleGraph
			-- Normal runtime checks and ordinary Luau typing, without type functions or an unchecked graph cast.
			return {
				sampleCounter = assert(graphContext.sampleCounter, "Counter was not constructed"),
				sampleReporter = assert(graphContext.sampleReporter, "Reporter was not constructed"),
				sampleLoadingDisplay = assert(graphContext.sampleLoadingDisplay, "Loading display was not constructed"),
			}
		end,
	}
end
return { new = new } :: SampleProfileModule
