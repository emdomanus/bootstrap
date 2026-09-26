--!strict

local SampleReporterTypes = require(script.Parent.Parent.Parent.Parent.types.components.sample.shared.sampleReporter)
local SampleCounterReaderTypes =
	require(script.Parent.Parent.Parent.Parent.types.ports.components.sample.shared.sampleCounterReader)
type SampleReporter = SampleReporterTypes.SampleReporter
type SampleCounterReader = SampleCounterReaderTypes.SampleCounterReader
type SampleReporterModule = { new: (report: (number) -> ()) -> SampleReporter }

local function new(report: (number) -> ()): SampleReporter
	local storedSampleCounterReader: SampleCounterReader? = nil
	local live = true
	return {
		wire = function(_self: SampleReporter, sampleCounterReader: SampleCounterReader): ()
			assert(live and storedSampleCounterReader == nil, "Reporter must be live and unwired")
			storedSampleCounterReader = sampleCounterReader
		end,
		start = function(): ()
			assert(live, "Reporter has been deconstructed")
			local sampleCounterReader = assert(storedSampleCounterReader, "Reporter must be wired before start")
			report(sampleCounterReader:get())
		end,
		deconstruct = function(): ()
			storedSampleCounterReader = nil
			live = false
		end,
	}
end

return { new = new } :: SampleReporterModule
