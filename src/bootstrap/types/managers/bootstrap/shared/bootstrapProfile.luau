--!strict
local BootstrapTelemetryContextTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryContext)
type BootstrapTelemetryContext = BootstrapTelemetryContextTypes.BootstrapTelemetryContext

export type BootstrapRegistration<C, G> = {
	name: string,
	construct: (graphContext: C, telemetryContext: BootstrapTelemetryContext) -> (),
	init: ((graphContext: G, telemetryContext: BootstrapTelemetryContext) -> ())?,
	wire: ((graphContext: G, telemetryContext: BootstrapTelemetryContext) -> ())?,
	start: ((graphContext: G, telemetryContext: BootstrapTelemetryContext) -> ())?,
	deconstruct: (graphContext: C, telemetryContext: BootstrapTelemetryContext) -> (),
}
export type BootstrapProfile<C, G> = {
	registrations: { BootstrapRegistration<C, G> },
	validate: (graphContext: C) -> G,
}
return {}
