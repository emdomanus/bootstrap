--!strict
local Bootstrap = require(script.bootstrap.managers.bootstrap.shared.bootstrap)
local BootstrapTypes = require(script.bootstrap.types.managers.bootstrap.shared.bootstrap)
local BootstrapProfileTypes = require(script.bootstrap.types.managers.bootstrap.shared.bootstrapProfile)
local BootstrapTelemetryReaderTypes =
	require(script.bootstrap.types.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryReader)
local BootstrapTelemetryContextTypes =
	require(script.bootstrap.types.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryContext)
local BootstrapStatusTypes = require(script.bootstrap.common.bootstrap.shared.bootstrapStatus)

local BootstrapTelemetryTaskTypes =
	require(script.bootstrap.types.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTask)
local BootstrapTelemetryTaskReaderTypes =
	require(script.bootstrap.types.ports.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskReader)
local BootstrapTelemetryTaskStateTypes =
	require(script.bootstrap.common.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskState)

export type Bootstrap<G> = BootstrapTypes.Bootstrap<G>
export type BootstrapOptions = BootstrapTypes.BootstrapOptions
export type BootstrapProfile<C, G> = BootstrapProfileTypes.BootstrapProfile<C, G>
export type BootstrapRegistration<C, G> = BootstrapProfileTypes.BootstrapRegistration<C, G>
export type BootstrapTelemetryReader = BootstrapTelemetryReaderTypes.BootstrapTelemetryReader
export type BootstrapTelemetryContext = BootstrapTelemetryContextTypes.BootstrapTelemetryContext
export type BootstrapStatus = BootstrapStatusTypes.BootstrapStatus
export type BootstrapPhase = BootstrapStatusTypes.BootstrapPhase
export type BootstrapOperationState = BootstrapStatusTypes.BootstrapOperationState
export type BootstrapTelemetryTask = BootstrapTelemetryTaskTypes.BootstrapTelemetryTask
export type BootstrapTelemetryTaskReader = BootstrapTelemetryTaskReaderTypes.BootstrapTelemetryTaskReader
export type BootstrapTelemetryTaskState = BootstrapTelemetryTaskStateTypes.BootstrapTelemetryTaskState
return Bootstrap
