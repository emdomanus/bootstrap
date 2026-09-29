--!strict
--!optimize 2
--!native
local TelemetryTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.bootstrapTelemetry.shared.bootstrapTelemetry)
local ContextTypes = require(
	script.Parent.Parent.Parent.Parent.types.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryContext
)
local ReaderTypes = require(
	script.Parent.Parent.Parent.Parent.types.ports.components.bootstrapTelemetry.shared.bootstrapTelemetryReader
)
local TaskTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTask)
local TaskReaderTypes = require(
	script.Parent.Parent.Parent.Parent.types.ports.components.bootstrapTelemetryTask.shared.bootstrapTelemetryTaskReader
)
local StatusTypes = require(script.Parent.Parent.Parent.Parent.common.bootstrap.shared.bootstrapStatus)
local Signal = require(script.Parent.Parent.Parent.bootstrapTelemetrySignal.shared.bootstrapTelemetrySignal)
local Task = require(script.Parent.Parent.Parent.bootstrapTelemetryTask.shared.bootstrapTelemetryTask)
type BootstrapTelemetryOwned = TelemetryTypes.BootstrapTelemetryOwned
type BootstrapTelemetryImpl = TelemetryTypes.BootstrapTelemetryImpl
type BootstrapTelemetryContext = ContextTypes.BootstrapTelemetryContext
type BootstrapTelemetryReader = ReaderTypes.BootstrapTelemetryReader
type BootstrapTelemetryTask = TaskTypes.BootstrapTelemetryTask
type BootstrapTelemetryTaskOwned = TaskTypes.BootstrapTelemetryTaskOwned
type BootstrapTelemetryTaskReader = TaskReaderTypes.BootstrapTelemetryTaskReader
type BootstrapPhase = StatusTypes.BootstrapPhase
type BootstrapOperationState = StatusTypes.BootstrapOperationState
type BootstrapTelemetryModule = { new: (clock: () -> number) -> BootstrapTelemetryOwned }
local Telemetry = {}
Telemetry.__index = Telemetry
local function active(self: BootstrapTelemetryImpl, token: number): ()
	assert(self._active and self._token == token, "Telemetry context belongs to a finished operation")
	assert(self._notification.depth == 0, "Telemetry observers cannot mutate the active operation")
end
local function update(
	self: BootstrapTelemetryImpl,
	phase: BootstrapPhase,
	name: string?,
	state: BootstrapOperationState,
	completed: number,
	total: number,
	failure: string?
): ()
	local phaseChanged, nameChanged, stateChanged = self._phase ~= phase, self._name ~= name, self._state ~= state
	local progressChanged = self._completed ~= completed or self._total ~= total
	local failureChanged = self._failure ~= failure
	self._phase, self._name, self._state = phase, name, state
	self._completed, self._total, self._failure = completed, total, failure
	-- Install every field before delivering separate notifications.
	if phaseChanged then
		self._phaseSignal:emit(phase)
	end
	if nameChanged then
		self._nameSignal:emit(name)
	end
	if stateChanged then
		self._stateSignal:emit(state)
	end
	if progressChanged then
		self._progressSignal:emit(completed, total)
	end
	if failureChanged then
		self._failureSignal:emit(failure)
	end
end
function Telemetry.new(clock: () -> number): BootstrapTelemetryOwned
	local notification = { depth = 0 }
	local self = (
		setmetatable({
			_phase = "idle" :: BootstrapPhase,
			_state = "pending" :: BootstrapOperationState,
			_completed = 0,
			_total = 0,
			_tasks = {},
			_notification = notification,
			_token = 0,
			_active = false,
			_clock = clock,
			_started = 0,
			_elapsed = 0,
			_phaseSignal = Signal.new(notification),
			_nameSignal = Signal.new(notification),
			_stateSignal = Signal.new(notification),
			_progressSignal = Signal.new(notification),
			_failureSignal = Signal.new(notification),
			_focusSignal = Signal.new(notification),
			_addedSignal = Signal.new(notification),
			_removedSignal = Signal.new(notification),
		}, Telemetry) :: unknown
	) :: BootstrapTelemetryImpl
	self._retireTask = function(task: BootstrapTelemetryTaskOwned): ()
		local focused = self._tasks[#self._tasks]
		local index = table.find(self._tasks, task)
		if index then
			table.remove(self._tasks, index)
		end
		-- Terminal state and collection membership agree even inside outcome observers.
		task:notifyFinished()
		self._removedSignal:emit(task)
		if focused ~= self._tasks[#self._tasks] then
			self._focusSignal:emit(self._tasks[#self._tasks])
		end
	end
	return self
end
function Telemetry.isNotifying(self: BootstrapTelemetryImpl): boolean
	return self._notification.depth > 0
end
function Telemetry.getElapsedSeconds(self: BootstrapTelemetryImpl): number
	return if self._active then self._clock() - self._started else self._elapsed
end
function Telemetry.getTaskCount(self: BootstrapTelemetryImpl): number
	return #self._tasks
end
function Telemetry.forEachTask(
	self: BootstrapTelemetryImpl,
	callback: (BootstrapTelemetryTaskReader) -> (),
	phase: BootstrapPhase?
): ()
	for _, task in self._tasks do
		if phase == nil or task:getPhase() == phase then
			self._addedSignal:replay(callback, task)
		end
	end
end
function Telemetry.bindToTaskAdded(
	self: BootstrapTelemetryImpl,
	callback: (BootstrapTelemetryTaskReader) -> ()
): () -> ()
	return self._addedSignal:connect(callback)
end
function Telemetry.bindToTaskRemoved(
	self: BootstrapTelemetryImpl,
	callback: (BootstrapTelemetryTaskReader) -> ()
): () -> ()
	return self._removedSignal:connect(callback)
end
function Telemetry.begin(
	self: BootstrapTelemetryImpl,
	phase: BootstrapPhase,
	name: string?,
	completed: number,
	total: number,
	checkpoint: () -> ()
): BootstrapTelemetryContext
	self._token += 1
	local token = self._token
	self._active = true
	self._started, self._elapsed = self._clock(), 0
	update(self, phase, name, "running" :: BootstrapOperationState, completed, total, nil)
	local context: BootstrapTelemetryContext = {
		getReader = function(): BootstrapTelemetryReader
			return self
		end,
		createTask = function(_context: BootstrapTelemetryContext, taskName: string): BootstrapTelemetryTask
			active(self, token)
			local task = Task.new(taskName, phase, name, self._notification, self._retireTask)
			table.insert(self._tasks, task)
			self._addedSignal:emit(task)
			self._focusSignal:emit(task)
			return task
		end,
		checkpoint = function(): ()
			active(self, token)
			checkpoint()
		end,
	}
	return table.freeze(context)
end
function Telemetry.finish(
	self: BootstrapTelemetryImpl,
	state: BootstrapOperationState,
	completed: number,
	failure: string?
): ()
	self._active = false
	self._elapsed = self._clock() - self._started
	while #self._tasks > 0 do
		self._tasks[#self._tasks]:cancel()
	end
	update(self, self._phase, self._name, state, completed, self._total, failure)
end
function Telemetry.terminal(
	self: BootstrapTelemetryImpl,
	phase: BootstrapPhase,
	completed: number,
	total: number,
	failure: string?
): ()
	self._active = false
	self._elapsed = 0
	update(
		self,
		phase,
		nil,
		(if failure then "failed" else "completed") :: BootstrapOperationState,
		completed,
		total,
		failure
	)
end
function Telemetry.close(self: BootstrapTelemetryImpl): ()
	self._active = false
	self._phaseSignal:close()
	self._nameSignal:close()
	self._stateSignal:close()
	self._progressSignal:close()
	self._failureSignal:close()
	self._focusSignal:close()
	self._addedSignal:close()
	self._removedSignal:close()
end
function Telemetry.getPhase(self: BootstrapTelemetryImpl): BootstrapPhase
	return self._phase
end
function Telemetry.bindToPhaseChanged(self: BootstrapTelemetryImpl, callback: (BootstrapPhase) -> ()): () -> ()
	local disconnect = self._phaseSignal:connect(callback)
	self._phaseSignal:replay(callback, self._phase)
	return disconnect
end
function Telemetry.getName(self: BootstrapTelemetryImpl): string?
	return self._name
end
function Telemetry.bindToNameChanged(self: BootstrapTelemetryImpl, callback: (string?) -> ()): () -> ()
	local disconnect = self._nameSignal:connect(callback)
	self._nameSignal:replay(callback, self._name)
	return disconnect
end
function Telemetry.getOperationState(self: BootstrapTelemetryImpl): BootstrapOperationState
	return self._state
end
function Telemetry.bindToOperationStateChanged(
	self: BootstrapTelemetryImpl,
	callback: (BootstrapOperationState) -> ()
): () -> ()
	local disconnect = self._stateSignal:connect(callback)
	self._stateSignal:replay(callback, self._state)
	return disconnect
end
function Telemetry.getOperationProgress(self: BootstrapTelemetryImpl): (number, number)
	return self._completed, self._total
end
function Telemetry.bindToOperationProgressChanged(
	self: BootstrapTelemetryImpl,
	callback: (number, number) -> ()
): () -> ()
	local disconnect = self._progressSignal:connect(callback)
	self._progressSignal:replay(callback, self._completed, self._total)
	return disconnect
end
function Telemetry.getFailure(self: BootstrapTelemetryImpl): string?
	return self._failure
end
function Telemetry.bindToFailureChanged(self: BootstrapTelemetryImpl, callback: (string?) -> ()): () -> ()
	local disconnect = self._failureSignal:connect(callback)
	self._failureSignal:replay(callback, self._failure)
	return disconnect
end
function Telemetry.getFocusedTask(self: BootstrapTelemetryImpl): BootstrapTelemetryTaskReader?
	return self._tasks[#self._tasks]
end
function Telemetry.bindToFocusedTaskChanged(
	self: BootstrapTelemetryImpl,
	callback: (BootstrapTelemetryTaskReader?) -> ()
): () -> ()
	local disconnect = self._focusSignal:connect(callback)
	self._focusSignal:replay(callback, self._tasks[#self._tasks])
	return disconnect
end
return table.freeze({ new = Telemetry.new }) :: BootstrapTelemetryModule
