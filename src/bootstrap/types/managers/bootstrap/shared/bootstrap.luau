--!strict
local BootstrapStatusTypes = require(script.Parent.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local BootstrapProfileTypes = require(script.Parent.bootstrapProfile)
local BootstrapTelemetryTypes =
	require(script.Parent.Parent.Parent.Parent.components.bootstrapTelemetry.shared.bootstrapTelemetry)
local BootstrapTelemetryReaderTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryReader)
type BootstrapStatus = BootstrapStatusTypes.BootstrapStatus
type BootstrapProfile<C, G> = BootstrapProfileTypes.BootstrapProfile<C, G>
type BootstrapTelemetryOwned = BootstrapTelemetryTypes.BootstrapTelemetryOwned
type BootstrapTelemetryReader = BootstrapTelemetryReaderTypes.BootstrapTelemetryReader

export type BootstrapOptions = {
	budgetSeconds: number?,
	clock: (() -> number)?,
	yieldExecution: (() -> ())?,
}
export type Bootstrap<G> = {
	start: (self: Bootstrap<G>) -> G,
	getStatus: (self: Bootstrap<G>) -> BootstrapStatus,
	getTelemetryReader: (self: Bootstrap<G>) -> BootstrapTelemetryReader,
	deconstruct: (self: Bootstrap<G>) -> (),
}
export type BootstrapImpl<C, G> = Bootstrap<G> & {
	_profile: BootstrapProfile<C, G>?,
	_graphContext: C,
	_status: BootstrapStatus,
	_busy: boolean,
	_entered: number,
	_checkpoint: () -> (),
	_resetBudget: () -> (),
	_bootstrapTelemetry: BootstrapTelemetryOwned,
}
return {}
