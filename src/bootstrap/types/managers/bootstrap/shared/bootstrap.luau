--!strict
local BootstrapStatusTypes = require(script.Parent.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local BootstrapProfileTypes = require(script.Parent.bootstrapProfile)
local BootstrapTelemetryTypes =
	require(script.Parent.Parent.Parent.Parent.components.bootstrapTelemetry.shared.bootstrapTelemetry)
local BootstrapTelemetryReaderTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryReader)
type BootstrapStatus = BootstrapStatusTypes.BootstrapStatus
type BootstrapProfile<C, G, StartPhase, StopPhase> = BootstrapProfileTypes.BootstrapProfile<C, G, StartPhase, StopPhase>
type BootstrapTelemetryOwned = BootstrapTelemetryTypes.BootstrapTelemetryOwned
type BootstrapTelemetryReader = BootstrapTelemetryReaderTypes.BootstrapTelemetryReader

export type BootstrapOptions<StartPhase, StopPhase> = {
	read startPhases: { StartPhase },
	read stopPhases: { StopPhase },
	read budgetSeconds: number?,
	read clock: (() -> number)?,
	read yieldExecution: (() -> ())?,
}
export type Bootstrap<G> = {
	read create: (self: Bootstrap<G>) -> G,
	read destroy: (self: Bootstrap<G>) -> (),
	read getStatus: (self: Bootstrap<G>) -> BootstrapStatus,
	read getTelemetryReader: (self: Bootstrap<G>) -> BootstrapTelemetryReader,
}
export type BootstrapImpl<C, G, StartPhase, StopPhase> = {
	_profile: BootstrapProfile<C, G, StartPhase, StopPhase>?,
	_startPhases: { StartPhase },
	_stopPhases: { StopPhase },
	_graphContext: C,
	_status: BootstrapStatus,
	_owner: thread?,
	_destroyRequested: boolean,
	_entered: { [number]: boolean },
	_failure: string?,
	_checkpoint: () -> (),
	_resetBudget: () -> (),
	_yieldExecution: () -> (),
	_bootstrapTelemetry: BootstrapTelemetryOwned,
}
return {}
