--!strict
--!optimize 2
--!native
local TaskTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTask)
local ReaderTypes = require(
	script.Parent.Parent.Parent.Parent.types.ports.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskReader
)
local SignalTypes = require(
	script.Parent.Parent.Parent.Parent.types.components.bootstrapTelemetrySignal.shared.bootstrapTelemetrySignal
)
local StatusTypes = require(script.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local StateTypes =
	require(script.Parent.Parent.Parent.Parent.common.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskState)
local Signal = require(script.Parent.Parent.Parent.bootstrapTelemetrySignal.shared.bootstrapTelemetrySignal)
type BootstrapTelemetryTaskImpl = TaskTypes.BootstrapTelemetryTaskImpl
type BootstrapTelemetryTaskOwned = TaskTypes.BootstrapTelemetryTaskOwned
type BootstrapTelemetryTaskReader = ReaderTypes.BootstrapTelemetryTaskReader
type BootstrapTelemetrySignal<T...> = SignalTypes.BootstrapTelemetrySignal<T...>
type BootstrapTelemetryNotification = SignalTypes.BootstrapTelemetryNotification
type BootstrapPhase = StatusTypes.BootstrapPhase
type BootstrapTelemetryTaskState = StateTypes.BootstrapTelemetryTaskState
type BootstrapTelemetryTaskModule = {
	new: (
		name: string,
		phase: BootstrapPhase,
		operationName: string?,
		notification: BootstrapTelemetryNotification,
		retire: (BootstrapTelemetryTaskOwned) -> ()
	) -> BootstrapTelemetryTaskOwned,
}
local Task = {}
Task.__index = Task
local function writable(self: BootstrapTelemetryTaskImpl): ()
	assert(self._notification.depth == 0, "Telemetry observers cannot mutate tasks")
	assert(self._state == "active", "Telemetry task has finished")
end
local function finish(self: BootstrapTelemetryTaskImpl, state: BootstrapTelemetryTaskState, failure: string?): ()
	assert(self._notification.depth == 0, "Telemetry observers cannot mutate tasks")
	if self._state == state then
		return
	end
	assert(self._state == "active", "Telemetry task has finished")
	self._state, self._failure = state, failure
	local retire = self._retire
	self._retire = nil
	if retire then
		retire(self)
	end
end
function Task.new(
	name: string,
	phase: BootstrapPhase,
	operationName: string?,
	notification: BootstrapTelemetryNotification,
	retire: (BootstrapTelemetryTaskOwned) -> ()
): BootstrapTelemetryTaskOwned
	assert(type(name) == "string" and name:match("%S"), "Telemetry task requires a nonblank name")
	return (
		setmetatable({
			_name = name,
			_phase = phase,
			_operationName = operationName,
			_state = "active" :: BootstrapTelemetryTaskState,
			_notification = notification,
			_retire = retire,
		}, Task) :: unknown
	) :: BootstrapTelemetryTaskImpl
end
function Task.getReader(self: BootstrapTelemetryTaskImpl): BootstrapTelemetryTaskReader
	return self
end
function Task.getName(self: BootstrapTelemetryTaskImpl): string
	return self._name
end
function Task.getPhase(self: BootstrapTelemetryTaskImpl): BootstrapPhase
	return self._phase
end
function Task.getOperationName(self: BootstrapTelemetryTaskImpl): string?
	return self._operationName
end
function Task.getStatus(self: BootstrapTelemetryTaskImpl): string?
	return self._status
end
function Task.getProgress(self: BootstrapTelemetryTaskImpl): (number?, number?)
	return self._completed, self._total
end
function Task.getState(self: BootstrapTelemetryTaskImpl): BootstrapTelemetryTaskState
	return self._state
end
function Task.getFailure(self: BootstrapTelemetryTaskImpl): string?
	return self._failure
end
function Task.setStatus(self: BootstrapTelemetryTaskImpl, status: string?): ()
	writable(self)
	if self._status == status then
		return
	end
	self._status = status
	if self._statusSignal then
		self._statusSignal:emit(status)
	end
end
function Task.setProgress(self: BootstrapTelemetryTaskImpl, completed: number, total: number): ()
	writable(self)
	assert(
		completed == completed
			and total == total
			and completed >= 0
			and total > 0
			and total < math.huge
			and completed <= total,
		"Invalid task progress"
	)
	if self._completed == completed and self._total == total then
		return
	end
	self._completed, self._total = completed, total
	if self._progressSignal then
		self._progressSignal:emit(completed, total)
	end
end
function Task.clearProgress(self: BootstrapTelemetryTaskImpl): ()
	writable(self)
	if self._total == nil then
		return
	end
	self._completed, self._total = nil, nil
	if self._progressSignal then
		self._progressSignal:emit(nil, nil)
	end
end
function Task.complete(self: BootstrapTelemetryTaskImpl): ()
	finish(self, "completed" :: BootstrapTelemetryTaskState, nil)
end
function Task.fail(self: BootstrapTelemetryTaskImpl, message: string): ()
	finish(self, "failed" :: BootstrapTelemetryTaskState, message)
end
function Task.cancel(self: BootstrapTelemetryTaskImpl): ()
	finish(self, "cancelled" :: BootstrapTelemetryTaskState, nil)
end
function Task.notifyFinished(self: BootstrapTelemetryTaskImpl): ()
	if self._stateSignal then
		self._stateSignal:emit(self._state)
		self._stateSignal:close()
	end
	if self._statusSignal then
		self._statusSignal:close()
	end
	if self._progressSignal then
		self._progressSignal:close()
	end
end
function Task.bindToStatusChanged(self: BootstrapTelemetryTaskImpl, callback: (string?) -> ()): () -> ()
	local existing = self._statusSignal
	local signal: BootstrapTelemetrySignal<string?> = existing or Signal.new(self._notification)
	if existing == nil then
		self._statusSignal = signal
		if self._state ~= "active" then
			signal:close()
		end
	end
	local disconnect = signal:connect(callback)
	signal:replay(callback, self._status)
	return disconnect
end
function Task.bindToProgressChanged(self: BootstrapTelemetryTaskImpl, callback: (number?, number?) -> ()): () -> ()
	local existing = self._progressSignal
	local signal: BootstrapTelemetrySignal<number?, number?> = existing or Signal.new(self._notification)
	if existing == nil then
		self._progressSignal = signal
		if self._state ~= "active" then
			signal:close()
		end
	end
	local disconnect = signal:connect(callback)
	signal:replay(callback, self._completed, self._total)
	return disconnect
end
function Task.bindToStateChanged(
	self: BootstrapTelemetryTaskImpl,
	callback: (BootstrapTelemetryTaskState) -> ()
): () -> ()
	local existing = self._stateSignal
	local signal: BootstrapTelemetrySignal<BootstrapTelemetryTaskState> = existing or Signal.new(self._notification)
	if existing == nil then
		self._stateSignal = signal
		if self._state ~= "active" then
			signal:close()
		end
	end
	local disconnect = signal:connect(callback)
	signal:replay(callback, self._state)
	return disconnect
end
return table.freeze({ new = Task.new }) :: BootstrapTelemetryTaskModule
