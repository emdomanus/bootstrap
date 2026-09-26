--!strict

local SampleCounterTypes = require(script.Parent.Parent.Parent.Parent.types.components.sample.shared.sampleCounter)
type SampleCounter = SampleCounterTypes.SampleCounter
type SampleCounterModule = { new: (initialValue: number) -> SampleCounter }

local function new(initialValue: number): SampleCounter
	local value = initialValue
	local live = true
	return {
		get = function(): number
			assert(live, "Counter has been deconstructed")
			return value
		end,
		increment = function(): ()
			assert(live, "Counter has been deconstructed")
			value += 1
		end,
		deconstruct = function(): ()
			live = false
		end,
	}
end

return { new = new } :: SampleCounterModule
