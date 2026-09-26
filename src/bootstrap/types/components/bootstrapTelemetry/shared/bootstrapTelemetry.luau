--!strict
local StatusTypes = require(script.Parent.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local ReaderTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryReader)
local ContextTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryContext)
local TaskTypes = require(script.Parent.Parent.Parent.bootstrapTelemetryTask.shared.bootstrapTelemetryTask)
local TaskReaderTypes = require(
	script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskReader
)
local SignalTypes = require(script.Parent.Parent.Parent.bootstrapTelemetrySignal.shared.bootstrapTelemetrySignal)
type BootstrapPhase = StatusTypes.BootstrapPhase
type BootstrapOperationState = StatusTypes.BootstrapOperationState
type BootstrapTelemetryReader = ReaderTypes.BootstrapTelemetryReader
type BootstrapTelemetryContext = ContextTypes.BootstrapTelemetryContext
type BootstrapTelemetryTaskOwned = TaskTypes.BootstrapTelemetryTaskOwned
type BootstrapTelemetryTaskReader = TaskReaderTypes.BootstrapTelemetryTaskReader
type BootstrapTelemetrySignal<T...> = SignalTypes.BootstrapTelemetrySignal<T...>
type BootstrapTelemetryNotification = SignalTypes.BootstrapTelemetryNotification
export type BootstrapTelemetryOwned = BootstrapTelemetryReader & {
	isNotifying: (self: BootstrapTelemetryOwned) -> boolean,
	begin: (
		self: BootstrapTelemetryOwned,
		phase: BootstrapPhase,
		name: string?,
		completed: number,
		total: number,
		checkpoint: () -> ()
	) -> BootstrapTelemetryContext,
	finish: (self: BootstrapTelemetryOwned, state: BootstrapOperationState, completed: number, failure: string?) -> (),
	terminal: (
		self: BootstrapTelemetryOwned,
		phase: BootstrapPhase,
		completed: number,
		total: number,
		failure: string?
	) -> (),
	close: (self: BootstrapTelemetryOwned) -> (),
}
export type BootstrapTelemetryImpl = BootstrapTelemetryOwned & {
	_phase: BootstrapPhase,
	_name: string?,
	_state: BootstrapOperationState,
	_completed: number,
	_total: number,
	_failure: string?,
	_tasks: { BootstrapTelemetryTaskOwned },
	_notification: BootstrapTelemetryNotification,
	_token: number,
	_active: boolean,
	_clock: () -> number,
	_started: number,
	_elapsed: number,
	_retireTask: (BootstrapTelemetryTaskOwned) -> (),
	_phaseSignal: BootstrapTelemetrySignal<BootstrapPhase>,
	_nameSignal: BootstrapTelemetrySignal<string?>,
	_stateSignal: BootstrapTelemetrySignal<BootstrapOperationState>,
	_progressSignal: BootstrapTelemetrySignal<number, number>,
	_failureSignal: BootstrapTelemetrySignal<string?>,
	_focusSignal: BootstrapTelemetrySignal<BootstrapTelemetryTaskReader?>,
	_addedSignal: BootstrapTelemetrySignal<BootstrapTelemetryTaskReader>,
	_removedSignal: BootstrapTelemetrySignal<BootstrapTelemetryTaskReader>,
}
return {}
