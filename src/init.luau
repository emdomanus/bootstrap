--!strict
--!optimize 2
--!native

local Bootstrap = require(script.bootstrap)

export type BootstrapAPI<SharedT, ServerT, ClientT> = Bootstrap.BootstrapAPI<SharedT, ServerT, ClientT>
export type BootstrapPhase = Bootstrap.BootstrapPhase

return Bootstrap
