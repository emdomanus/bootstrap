--!strict

local SampleCounterReaderTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.sample.shared.sampleCounterReader)
type SampleCounterReader = SampleCounterReaderTypes.SampleCounterReader

export type SampleCounter = SampleCounterReader & {
	increment: (self: SampleCounter) -> (),
	deconstruct: (self: SampleCounter) -> (),
}

return {}
