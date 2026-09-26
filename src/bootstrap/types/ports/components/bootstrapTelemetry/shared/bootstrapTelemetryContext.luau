--!strict
local ReaderTypes = require(script.Parent.bootstrapTelemetryReader)
local TaskTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTask)
type BootstrapTelemetryReader = ReaderTypes.BootstrapTelemetryReader
type BootstrapTelemetryTask = TaskTypes.BootstrapTelemetryTask
export type BootstrapTelemetryContext = {
	read getReader: (self: BootstrapTelemetryContext) -> BootstrapTelemetryReader,
	read createTask: (self: BootstrapTelemetryContext, name: string) -> BootstrapTelemetryTask,
	read checkpoint: (self: BootstrapTelemetryContext) -> (),
}
return {}
