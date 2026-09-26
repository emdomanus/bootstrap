--!strict
local StatusTypes = require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local TaskReaderTypes = require(script.Parent.Parent.Parent.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskReader)
type BootstrapPhase = StatusTypes.BootstrapPhase
type BootstrapOperationState = StatusTypes.BootstrapOperationState
type BootstrapTelemetryTaskReader = TaskReaderTypes.BootstrapTelemetryTaskReader
export type BootstrapTelemetryReader = {
	getPhase: (self: BootstrapTelemetryReader) -> BootstrapPhase,
	bindToPhaseChanged: (self: BootstrapTelemetryReader, callback: (BootstrapPhase) -> ()) -> () -> (),
	getName: (self: BootstrapTelemetryReader) -> string?,
	bindToNameChanged: (self: BootstrapTelemetryReader, callback: (string?) -> ()) -> () -> (),
	getOperationState: (self: BootstrapTelemetryReader) -> BootstrapOperationState,
	bindToOperationStateChanged: (
		self: BootstrapTelemetryReader,
		callback: (BootstrapOperationState) -> ()
	) -> () -> (),
	getOperationProgress: (self: BootstrapTelemetryReader) -> (number, number),
	bindToOperationProgressChanged: (self: BootstrapTelemetryReader, callback: (number, number) -> ()) -> () -> (),
	getFailure: (self: BootstrapTelemetryReader) -> string?,
	bindToFailureChanged: (self: BootstrapTelemetryReader, callback: (string?) -> ()) -> () -> (),
	getFocusedTask: (self: BootstrapTelemetryReader) -> BootstrapTelemetryTaskReader?,
	bindToFocusedTaskChanged: (
		self: BootstrapTelemetryReader,
		callback: (BootstrapTelemetryTaskReader?) -> ()
	) -> () -> (),
	getElapsedSeconds: (self: BootstrapTelemetryReader) -> number,
	getTaskCount: (self: BootstrapTelemetryReader) -> number,
	forEachTask: (
		self: BootstrapTelemetryReader,
		callback: (BootstrapTelemetryTaskReader) -> (),
		phase: BootstrapPhase?
	) -> (),
	bindToTaskAdded: (self: BootstrapTelemetryReader, callback: (BootstrapTelemetryTaskReader) -> ()) -> () -> (),
	bindToTaskRemoved: (self: BootstrapTelemetryReader, callback: (BootstrapTelemetryTaskReader) -> ()) -> () -> (),
}
return {}
