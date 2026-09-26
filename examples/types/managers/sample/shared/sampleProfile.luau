--!strict
local SampleCounterTypes = require(script.Parent.Parent.Parent.Parent.components.sample.shared.sampleCounter)
local SampleReporterTypes = require(script.Parent.Parent.Parent.Parent.components.sample.shared.sampleReporter)
local SampleLoadingDisplayTypes =
	require(script.Parent.Parent.Parent.Parent.components.sample.shared.sampleLoadingDisplay)
type SampleCounter = SampleCounterTypes.SampleCounter
type SampleReporter = SampleReporterTypes.SampleReporter
type SampleLoadingDisplay = SampleLoadingDisplayTypes.SampleLoadingDisplay
export type SampleOptions = {
	initialValue: number,
	report: (value: number) -> (),
	display: (text: string) -> (),
}
export type SampleGraphContext = {
	sampleCounter: SampleCounter?,
	sampleReporter: SampleReporter?,
	sampleLoadingDisplay: SampleLoadingDisplay?,
}
export type SampleGraph = {
	sampleCounter: SampleCounter,
	sampleReporter: SampleReporter,
	sampleLoadingDisplay: SampleLoadingDisplay,
}
return {}
