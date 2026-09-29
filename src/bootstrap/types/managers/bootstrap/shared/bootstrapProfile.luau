--!strict
local BootstrapTelemetryContextTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryContext)
type BootstrapTelemetryContext = BootstrapTelemetryContextTypes.BootstrapTelemetryContext

export type BootstrapCallbacks<C, P> = { [P]: ((C, BootstrapTelemetryContext) -> ())? }
export type BootstrapRegistration<C, G, StartPhase, StopPhase> = {
	read name: string,
	read construct: (C, BootstrapTelemetryContext) -> (),
	read start: BootstrapCallbacks<G, StartPhase>,
	read stop: BootstrapCallbacks<C, StopPhase>,
	read destroy: (C, BootstrapTelemetryContext) -> (),
}
export type BootstrapShutdown<C> = {
	read name: string,
	read run: (C, BootstrapTelemetryContext) -> (),
}
export type BootstrapProfile<C, G, StartPhase, StopPhase> = {
	read registrations: { BootstrapRegistration<C, G, StartPhase, StopPhase> },
	read validate: (C) -> G,
	read shutdown: { BootstrapShutdown<C> }?,
}
return {}
