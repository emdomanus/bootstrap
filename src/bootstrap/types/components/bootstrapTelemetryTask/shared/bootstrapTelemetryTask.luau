--!strict
local ReaderTypes = require(
	script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskReader
)
local SignalTypes = require(script.Parent.Parent.Parent.bootstrapTelemetrySignal.shared.bootstrapTelemetrySignal)
local StatusTypes = require(script.Parent.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local StateTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.common.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskState)
type BootstrapTelemetryTaskReader = ReaderTypes.BootstrapTelemetryTaskReader
type BootstrapTelemetrySignal<T...> = SignalTypes.BootstrapTelemetrySignal<T...>
type BootstrapTelemetryNotification = SignalTypes.BootstrapTelemetryNotification
type BootstrapPhase = StatusTypes.BootstrapPhase
type BootstrapTelemetryTaskState = StateTypes.BootstrapTelemetryTaskState
export type BootstrapTelemetryTask = {
	getReader: (self: BootstrapTelemetryTask) -> BootstrapTelemetryTaskReader,
	setStatus: (self: BootstrapTelemetryTask, status: string?) -> (),
	setProgress: (self: BootstrapTelemetryTask, completed: number, total: number) -> (),
	clearProgress: (self: BootstrapTelemetryTask) -> (),
	complete: (self: BootstrapTelemetryTask) -> (),
	fail: (self: BootstrapTelemetryTask, message: string) -> (),
	cancel: (self: BootstrapTelemetryTask) -> (),
}
export type BootstrapTelemetryTaskOwned = BootstrapTelemetryTask & BootstrapTelemetryTaskReader & {
	notifyFinished: (self: BootstrapTelemetryTaskOwned) -> (),
}
export type BootstrapTelemetryTaskImpl = BootstrapTelemetryTaskOwned & {
	_name: string,
	_phase: BootstrapPhase,
	_operationName: string?,
	_status: string?,
	_completed: number?,
	_total: number?,
	_state: BootstrapTelemetryTaskState,
	_failure: string?,
	_notification: BootstrapTelemetryNotification,
	_retire: ((BootstrapTelemetryTaskOwned) -> ())?,
	_statusSignal: BootstrapTelemetrySignal<string?>?,
	_progressSignal: BootstrapTelemetrySignal<number?, number?>?,
	_stateSignal: BootstrapTelemetrySignal<BootstrapTelemetryTaskState>?,
}
return {}
