--!strict
--!optimize 2
--!native
local SignalTypes = require(
	script.Parent.Parent.Parent.Parent.types.components.bootstrapTelemetrySignal.shared.bootstrapTelemetrySignal
)
type BootstrapTelemetrySignal<T...> = SignalTypes.BootstrapTelemetrySignal<T...>
type BootstrapTelemetrySignalImpl<T...> = SignalTypes.BootstrapTelemetrySignalImpl<T...>
type BootstrapTelemetryNotification = SignalTypes.BootstrapTelemetryNotification
type BootstrapTelemetrySignalModule = {
	new: <T...>(notification: BootstrapTelemetryNotification) -> BootstrapTelemetrySignal<T...>,
}
local Signal = {}
Signal.__index = Signal
function Signal.new<T...>(notification: BootstrapTelemetryNotification): BootstrapTelemetrySignal<T...>
	return (
		setmetatable({ _notification = notification, _listeners = {}, _nextId = 0, _closed = false }, Signal) :: unknown
	) :: BootstrapTelemetrySignalImpl<T...>
end
function Signal.replay<T...>(self: BootstrapTelemetrySignalImpl<T...>, callback: (T...) -> (), ...: T...): ()
	self._notification.depth += 1
	local thread = coroutine.create(callback)
	local ok, failure = coroutine.resume(thread, ...)
	if not ok then
		warn("Bootstrap telemetry observer failed: " .. tostring(failure))
	elseif coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		warn("Bootstrap telemetry observers must not yield")
	end
	self._notification.depth -= 1
end
function Signal.connect<T...>(self: BootstrapTelemetrySignalImpl<T...>, callback: (T...) -> ()): () -> ()
	self._nextId += 1
	local id = self._nextId
	if not self._closed then
		self._listeners[id] = callback
	end
	return function(): ()
		self._listeners[id] = nil
	end
end
function Signal.emit<T...>(self: BootstrapTelemetrySignalImpl<T...>, ...: T...): ()
	local lastId = self._nextId
	for id = 1, lastId do
		local callback = self._listeners[id]
		if callback then
			self:replay(callback, ...)
		end
	end
end
function Signal.close<T...>(self: BootstrapTelemetrySignalImpl<T...>): ()
	self._closed = true
	table.clear(self._listeners)
end
return table.freeze({ new = Signal.new }) :: BootstrapTelemetrySignalModule
