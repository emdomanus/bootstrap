--!strict
local Bootstrap = require(script.Parent.Parent.Parent.Parent.Parent.bootstrap)
local DisplayTypes = require(script.Parent.Parent.Parent.Parent.types.components.sample.shared.sampleLoadingDisplay)
type SampleLoadingDisplay = DisplayTypes.SampleLoadingDisplay
type BootstrapTelemetryReader = Bootstrap.BootstrapTelemetryReader
type BootstrapTelemetryTaskReader = Bootstrap.BootstrapTelemetryTaskReader
type SampleLoadingDisplayModule = {
	new: (reader: BootstrapTelemetryReader, display: (string) -> ()) -> SampleLoadingDisplay,
}
local function new(reader: BootstrapTelemetryReader, display: (string) -> ()): SampleLoadingDisplay
	local focused: BootstrapTelemetryTaskReader? = nil
	local taskConnections: { () -> () } = {}
	local function render(): ()
		local task = focused
		local text = `{reader:getPhase()}: {reader:getName() or "Bootstrap"}`
		if task then
			text ..= ` / {task:getName()}`
			local status = task:getStatus()
			if status then
				text ..= `: {status}`
			end
			local completed, total = task:getProgress()
			if completed ~= nil and total ~= nil then
				text ..= ` ({completed}/{total})`
			end
		end
		display(text)
	end
	local function disconnectTask(): ()
		for _, disconnect in taskConnections do
			disconnect()
		end
		table.clear(taskConnections)
	end
	-- Each property is independent. A Roblox view can bind each to its own widget instead.
	local stopPhase = reader:bindToPhaseChanged(render)
	local stopName = reader:bindToNameChanged(render)
	local stopFocus = reader:bindToFocusedTaskChanged(function(task)
		disconnectTask()
		focused = task
		if task then
			table.insert(taskConnections, task:bindToStatusChanged(render))
			table.insert(taskConnections, task:bindToProgressChanged(render))
		end
		render()
	end)
	return {
		deconstruct = function(): ()
			disconnectTask()
			stopFocus()
			stopName()
			stopPhase()
		end,
	}
end
return { new = new } :: SampleLoadingDisplayModule
