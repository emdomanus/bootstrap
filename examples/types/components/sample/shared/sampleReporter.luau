--!strict

local SampleCounterReaderTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.sample.shared.sampleCounterReader)
type SampleCounterReader = SampleCounterReaderTypes.SampleCounterReader

export type SampleReporter = {
	wire: (self: SampleReporter, sampleCounterReader: SampleCounterReader) -> (),
	start: (self: SampleReporter) -> (),
	deconstruct: (self: SampleReporter) -> (),
}

return {}
