--!strict
export type BootstrapStatus = "idle" | "creating" | "running" | "destroying" | "stopped" | "failed"
-- Telemetry also reports caller-authored phase names; lifecycle status remains a closed vocabulary.
export type BootstrapPhase = string
export type BootstrapOperationState = "pending" | "running" | "completed" | "failed" | "cancelled"
return {}
