--!strict
local StatusTypes = require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local StateTypes = require(
	script.Parent.Parent.Parent.Parent.Parent.Parent.common.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskState
)
type BootstrapPhase = StatusTypes.BootstrapPhase
type BootstrapTelemetryTaskState = StateTypes.BootstrapTelemetryTaskState
export type BootstrapTelemetryTaskReader = {
	getName: (self: BootstrapTelemetryTaskReader) -> string,
	getPhase: (self: BootstrapTelemetryTaskReader) -> BootstrapPhase,
	getOperationName: (self: BootstrapTelemetryTaskReader) -> string?,
	getStatus: (self: BootstrapTelemetryTaskReader) -> string?,
	getProgress: (self: BootstrapTelemetryTaskReader) -> (number?, number?),
	getState: (self: BootstrapTelemetryTaskReader) -> BootstrapTelemetryTaskState,
	getFailure: (self: BootstrapTelemetryTaskReader) -> string?,
	bindToStatusChanged: (self: BootstrapTelemetryTaskReader, callback: (string?) -> ()) -> () -> (),
	bindToProgressChanged: (self: BootstrapTelemetryTaskReader, callback: (number?, number?) -> ()) -> () -> (),
	bindToStateChanged: (self: BootstrapTelemetryTaskReader, callback: (BootstrapTelemetryTaskState) -> ()) -> () -> (),
}
return {}
