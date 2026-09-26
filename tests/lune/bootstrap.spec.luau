--!nocheck

local LoadPackage = require("./lib/loadPackage")
local warnings = {}
local function recordWarning(message)
	table.insert(warnings, tostring(message))
end
local load = LoadPackage.new(nil, recordWarning)
local Bootstrap = load("src/init.luau")
local cases = 0
local currentCase = "setup"
local function expect(condition, message)
	assert(condition, message or currentCase)
end
local function test(name, callback)
	currentCase = name
	table.clear(warnings)
	callback()
	for _, message in warnings do
		assert(
			name == "observers may bind readers but cannot mutate tasks or reenter lifecycle"
				and (
					message:find("expected observer failure", 1, true)
					or message:find("observers must not yield", 1, true)
				),
			message
		)
	end
	cases += 1
	print("PASS " .. name)
end
local function rejects(callback, fragment)
	local ok, failure = pcall(callback)
	expect(not ok and tostring(failure):find(fragment, 1, true), tostring(failure))
	return tostring(failure)
end
local function new(registrations, graphContext, validate, options)
	return Bootstrap.new({
		registrations = registrations,
		validate = validate or function(graph)
			return graph
		end,
	}, graphContext or {}, options or {
		clock = function()
			return 0
		end,
	})
end
local function registration(name)
	return { name = name, construct = function() end, deconstruct = function() end }
end

test("named registrations preserve global phase barriers and reverse cleanup", function()
	local events, context, graph = {}, {}, {}
	local application
	local registrations = {}
	for _, name in { "A", "B" } do
		local entry = registration(name)
		for _, phase in { "construct", "init", "wire", "start", "deconstruct" } do
			entry[phase] = function(value, telemetry)
				expect(value == (if phase == "construct" or phase == "deconstruct" then context else graph))
				local reader = telemetry:getReader()
				expect(
					reader:getName() == name and reader:getPhase() == phase and reader:getOperationState() == "running"
				)
				table.insert(events, phase .. name)
				if phase == "construct" then
					context[name] = name
				end
				if phase == "wire" then
					expect(context.A and context.B)
				end
			end
		end
		table.insert(registrations, entry)
	end
	application = new(registrations, context, function(value)
		expect(value == context and context.A and context.B)
		table.insert(events, "validate")
		return graph
	end)
	expect(application:getStatus() == "idle" and #events == 0)
	expect(application:start() == graph and application:getStatus() == "running")
	local reader = application:getTelemetryReader()
	local completed, total = reader:getOperationProgress()
	expect(reader:getPhase() == "ready" and completed == 9 and total == 9)
	application:deconstruct()
	application:deconstruct()
	expect(
		table.concat(events, ",")
			== "constructA,constructB,validate,initA,initB,wireA,wireB,startA,startB,deconstructB,deconstructA"
	)
	expect(application:getStatus() == "stopped")
end)

test("only semantic name construct and deconstruct are required per registration", function()
	local app = new({ registration("Minimal") })
	app:start()
	expect(select(2, app:getTelemetryReader():getOperationProgress()) == 2)
	app:deconstruct()
	local empty = new({})
	empty:start()
	expect(select(2, empty:getTelemetryReader():getOperationProgress()) == 1)
	empty:deconstruct()
end)

test("invalid registrations and budgets fail before construction", function()
	for _, entry in
		{
			{ construct = function() end, deconstruct = function() end },
			{ name = "  ", construct = function() end, deconstruct = function() end },
			{ name = "Missing construct", deconstruct = function() end },
			{ name = "Missing deconstruct", construct = function() end },
			{ name = "Bad wire", construct = function() end, deconstruct = function() end, wire = 3 },
		}
	do
		rejects(function()
			new({ entry })
		end, if entry.wire then "Invalid wire" else "Registration")
	end
	rejects(function()
		new({ registration("Same"), registration("Same") })
	end, "Duplicate")
	for _, budget in { -1, math.huge, 0 / 0 } do
		rejects(function()
			new({}, {}, nil, { budgetSeconds = budget })
		end, "budget")
	end
end)

test("deconstructing idle prevents startup without constructing", function()
	local entry = registration("Unused")
	entry.construct = function()
		error("must not construct")
	end
	local app = new({ entry })
	app:deconstruct()
	app:deconstruct()
	rejects(function()
		app:start()
	end, "only start once")
end)

test("partially throwing construction cleans entered registrations only", function()
	local events, context = {}, {}
	local registrations = {}
	for _, name in { "A", "B", "C" } do
		table.insert(registrations, {
			name = name,
			construct = function(graph)
				graph[name] = name
				table.insert(events, "+" .. name)
				if name == "B" then
					error("partial construction")
				end
			end,
			deconstruct = function(graph)
				expect(graph == context and graph[name] == name)
				graph[name] = nil
				table.insert(events, "-" .. name)
			end,
		})
	end
	local app = new(registrations, context, function()
		error("validation must not run")
	end)
	rejects(function()
		app:start()
	end, "partial construction")
	expect(table.concat(events, ",") == "+A,+B,-B,-A" and next(context) == nil)
	expect(app:getStatus() == "failed")
	app:deconstruct()
	rejects(function()
		app:start()
	end, "only start once")
end)

for _, failingPhase in { "validate", "init", "wire", "start" } do
	test("failure in " .. failingPhase .. " stops later work and reverses cleanup", function()
		local events = {}
		local entries = {}
		for _, name in { "A", "B" } do
			local entry = registration(name)
			for _, phase in { "construct", "init", "wire", "start", "deconstruct" } do
				entry[phase] = function()
					table.insert(events, phase .. name)
					if phase == failingPhase and name == "A" then
						error("deliberate " .. phase)
					end
				end
			end
			table.insert(entries, entry)
		end
		local app = new(entries, {}, function(graph)
			table.insert(events, "validate")
			if failingPhase == "validate" then
				error("deliberate validate")
			end
			return graph
		end)
		rejects(function()
			app:start()
		end, "deliberate " .. failingPhase)
		local expected = "constructA,constructB,validate"
		for _, phase in { "init", "wire", "start" } do
			if failingPhase == "validate" then
				break
			end
			expected ..= "," .. phase .. "A"
			if phase == failingPhase then
				break
			end
			expected ..= "," .. phase .. "B"
		end
		expect(table.concat(events, ",") == expected .. ",deconstructB,deconstructA")
	end)
end

test("missing graph assignment fails validation before wire", function()
	local entry = registration("Missing")
	entry.wire = function()
		error("should not wire")
	end
	local app = new({ entry }, {}, function(graph)
		return { service = assert(graph.service, "missing service") }
	end)
	rejects(function()
		app:start()
	end, "missing service")
end)

test("startup error retains cause and all cleanup failures", function()
	local entries = { registration("A"), registration("B") }
	local count = 0
	for _, entry in entries do
		local name = entry.name
		entry.deconstruct = function()
			count += 1
			error("cleanup " .. name)
		end
	end
	entries[2].construct = function()
		error("startup failed")
	end
	local app = new(entries)
	local message = rejects(function()
		app:start()
	end, "startup failed")
	expect(message:find("cleanup A", 1, true) and message:find("cleanup B", 1, true) and count == 2)
	app:deconstruct()
	expect(count == 2)
end)

test("normal shutdown continues after failure without retry", function()
	local count = 0
	local entries = { registration("Healthy"), registration("Broken") }
	entries[1].deconstruct = function()
		count += 1
	end
	entries[2].deconstruct = function()
		count += 1
		error("release failed")
	end
	local app = new(entries)
	app:start()
	rejects(function()
		app:deconstruct()
	end, "release failed")
	expect(count == 2 and app:getStatus() == "failed")
	app:deconstruct()
	expect(count == 2)
end)

test("yielding callback holds barrier and rejects reentrant lifecycle", function()
	local entry, wired = registration("Yield"), false
	entry.init = function()
		coroutine.yield("waiting")
	end
	entry.wire = function()
		wired = true
	end
	local app = new({ entry })
	local thread = coroutine.create(function()
		app:start()
	end)
	local ok, marker = coroutine.resume(thread)
	expect(ok and marker == "waiting" and app:getStatus() == "initializing" and not wired)
	rejects(function()
		app:start()
	end, "only start once")
	rejects(function()
		app:deconstruct()
	end, "active lifecycle")
	expect(coroutine.resume(thread))
	expect(wired and app:getStatus() == "running")
	app:deconstruct()
end)

test("time budget paces operations and explicit checkpoints including shutdown", function()
	local time, yields, events = 0, 0, {}
	local entries = { registration("A"), registration("B") }
	entries[1].construct = function(_, telemetry)
		time += 0.003
		telemetry:checkpoint()
		expect(yields == 0)
		time += 0.003
		telemetry:checkpoint()
		expect(yields == 1)
		time += 0.005
		table.insert(events, "A")
	end
	entries[2].construct = function()
		expect(yields == 2)
		table.insert(events, "B")
	end
	entries[2].deconstruct = function()
		time += 0.005
	end
	entries[1].deconstruct = function()
		expect(yields == 3)
	end
	local app = new(entries, {}, nil, {
		budgetSeconds = 0.004,
		clock = function()
			return time
		end,
		yieldExecution = function()
			yields += 1
			time += 10
		end,
	})
	app:start()
	expect(yields == 2 and table.concat(events) == "AB")
	time += 100
	app:deconstruct()
	expect(yields == 3)
end)

test("zero budget yields before each operation while publishing current label", function()
	local states = {}
	local app
	app = new({ registration("One") }, {}, nil, {
		budgetSeconds = 0,
		clock = function()
			return 0
		end,
		yieldExecution = function()
			local reader = app:getTelemetryReader()
			table.insert(states, reader:getPhase() .. ":" .. (reader:getName() or "graph"))
		end,
	})
	app:start()
	app:deconstruct()
	expect(table.concat(states, ",") == "construct:One,validate:graph,deconstruct:One")
end)

test("default scheduler supports the real Lune task wait boundary", function()
	local app = new({ registration("Default yield") }, {}, nil, { budgetSeconds = 0 })
	app:start()
	app:deconstruct()
	expect(app:getStatus() == "stopped")
end)

test("tasks mutate in place and notify each property independently", function()
	local entry = registration("Telemetry")
	local retainedContext, retainedTask, observedReader
	local statuses, progresses, outcomes = {}, {}, {}
	local app
	entry.construct = function(_, context)
		retainedContext = context
		local task = context:createTask("Read assets")
		retainedTask = task
		local reader = task:getReader()
		expect(reader == observedReader and reader == task:getReader())
		expect(
			reader:getName() == "Read assets"
				and reader:getPhase() == "construct"
				and reader:getOperationName() == "Telemetry"
		)
		task:setStatus("Reading")
		task:setStatus("Reading")
		task:setProgress(2, 3)
		task:setProgress(2, 3)
		task:setStatus("Finalizing")
		local completed, total = reader:getProgress()
		expect(completed == 2 and total == 3)
		task:clearProgress()
		task:clearProgress()
		task:setStatus(nil)
		expect(#statuses == 4 and #progresses == 3 and #outcomes == 1)
		task:complete()
		task:complete()
		expect(#outcomes == 2 and reader:getState() == "completed")
		rejects(function()
			task:setStatus("late")
		end, "finished")
		rejects(function()
			task:cancel()
		end, "finished")
	end
	entry.init = function(_, context)
		expect(context:getReader():getTaskCount() == 0)
		rejects(function()
			retainedContext:createTask("stale")
		end, "finished operation")
		rejects(function()
			retainedContext:checkpoint()
		end, "finished operation")
	end
	app = new({ entry })
	local reader = app:getTelemetryReader()
	reader:bindToTaskAdded(function(task)
		observedReader = task
		-- Subscribing during collection notifications is required by real UIs.
		task:bindToStatusChanged(function(status)
			expect(task:getStatus() == status)
			table.insert(statuses, status or "<nil>")
		end)
		task:bindToProgressChanged(function(completed, total)
			local actualCompleted, actualTotal = task:getProgress()
			expect(actualCompleted == completed and actualTotal == total)
			table.insert(progresses, { completed, total })
		end)
		task:bindToStateChanged(function(state)
			expect(task:getState() == state)
			if state ~= "active" then
				expect(reader:getTaskCount() == 0 and reader:getFocusedTask() == nil)
			end
			table.insert(outcomes, state)
		end)
	end)
	app:start()
	expect(retainedContext:getReader() == reader)
	local terminalReplay
	retainedTask:getReader():bindToStateChanged(function(state)
		terminalReplay = state
	end)
	expect(terminalReplay == "completed")
	app:deconstruct()
end)

test("active tasks preserve creation order and focus survives out of order completion", function()
	local entry = registration("Tasks")
	local focuses, removed, added = {}, {}, {}
	local app
	entry.wire = function(_, context)
		local reader = context:getReader()
		local first = context:createTask("First")
		local middle = context:createTask("Middle")
		local last = context:createTask("Last")
		local names = {}
		reader:forEachTask(function(task)
			table.insert(names, task:getName())
		end, "wire")
		expect(table.concat(names, ",") == "First,Middle,Last")
		reader:forEachTask(function()
			error("wrong phase")
		end, "construct")
		expect(reader:getTaskCount() == 3)
		middle:complete()
		expect(reader:getFocusedTask() == last:getReader())
		last:complete()
		expect(reader:getFocusedTask() == first:getReader())
		first:complete()
		expect(reader:getFocusedTask() == nil and reader:getTaskCount() == 0)
	end
	app = new({ entry })
	local reader = app:getTelemetryReader()
	reader:bindToFocusedTaskChanged(function(task)
		table.insert(focuses, if task then task:getName() else "none")
	end)
	reader:bindToTaskAdded(function(task)
		table.insert(added, task:getName())
	end)
	reader:bindToTaskRemoved(function(task)
		expect(task:getState() == "completed")
		table.insert(removed, task:getName())
	end)
	app:start()
	expect(table.concat(added, ",") == "First,Middle,Last")
	expect(table.concat(removed, ",") == "Middle,Last,First")
	expect(table.concat(focuses, ",") == "none,First,Middle,Last,First,none")
	app:deconstruct()
end)

test("task validation rejects invalid inputs before publishing changes", function()
	local entry = registration("Validate tasks")
	entry.construct = function(_, context)
		for _, name in { "", "  " } do
			rejects(function()
				context:createTask(name)
			end, "nonblank")
		end
		expect(context:getReader():getTaskCount() == 0)
		local task = context:createTask("Valid")
		task:setProgress(1, 2)
		for _, pair in { { -1, 2 }, { 3, 2 }, { 0, 0 }, { 0, math.huge }, { 0 / 0, 2 }, { 1, 0 / 0 } } do
			rejects(function()
				task:setProgress(pair[1], pair[2])
			end, "Invalid")
			local completed, total = task:getReader():getProgress()
			expect(completed == 1 and total == 2)
		end
		task:cancel()
		task:cancel()
	end
	local app = new({ entry })
	app:start()
	app:deconstruct()
end)

test("callback exit cancels unfinished tasks in every phase including shutdown", function()
	local entry, tasks = registration("Scoped"), {}
	for _, phase in { "construct", "init", "wire", "start", "deconstruct" } do
		entry[phase] = function(_, context)
			expect(context:getReader():getTaskCount() == 0)
			local task = context:createTask(phase)
			table.insert(tasks, task)
		end
	end
	local app = new({ entry })
	app:start()
	for _, task in tasks do
		expect(task:getReader():getState() == "cancelled")
		rejects(function()
			task:setProgress(1, 1)
		end, "finished")
	end
	app:deconstruct()
	expect(#tasks == 5 and tasks[5]:getReader():getState() == "cancelled")
	expect(app:getTelemetryReader():getTaskCount() == 0)
end)

test("throwing callback cancels its tasks before rollback begins", function()
	local entry, task, checked = registration("Failure"), nil, false
	entry.init = function(_, context)
		task = context:createTask("Pending")
		error("callback failure")
	end
	entry.deconstruct = function(_, context)
		checked = task:getReader():getState() == "cancelled" and context:getReader():getTaskCount() == 0
	end
	local app = new({ entry })
	rejects(function()
		app:start()
	end, "callback failure")
	expect(checked and app:getTelemetryReader():getFailure():find("callback failure", 1, true))
end)

test("failed task reports outcome without changing bootstrap control flow", function()
	local entry, task, events = registration("Recoverable"), nil, {}
	entry.construct = function(_, context)
		task = context:createTask("Optional assets")
		local reader = task:getReader()
		reader:bindToStateChanged(function(state)
			if state ~= "active" then
				expect(reader:getFailure() == "Asset unavailable")
				table.insert(events, "outcome")
			end
		end)
		context:getReader():bindToTaskRemoved(function()
			table.insert(events, "removed")
		end)
		task:fail("Asset unavailable")
		task:fail("ignored duplicate")
		expect(reader:getFailure() == "Asset unavailable")
	end
	local app = new({ entry })
	app:start()
	expect(app:getStatus() == "running" and table.concat(events, ",") == "outcome,removed")
	app:deconstruct()
end)

test("observers may bind readers but cannot mutate tasks or reenter lifecycle", function()
	local entry, task, app = registration("Observers"), nil, nil
	entry.construct = function(_, context)
		task = context:createTask("Work")
		local reader = task:getReader()
		local checked = false
		reader:bindToStatusChanged(function()
			rejects(function()
				task:complete()
			end, "observers")
			rejects(function()
				context:createTask("bad")
			end, "observers")
			rejects(function()
				context:checkpoint()
			end, "observers")
			rejects(function()
				app:deconstruct()
			end, "observers")
			rejects(function()
				app:start()
			end, "observers")
			checked = true
		end)
		expect(checked)
		local stops = {}
		local count = 0
		stops[1] = reader:bindToProgressChanged(function()
			error("expected observer failure")
		end)
		stops[2] = reader:bindToProgressChanged(function()
			coroutine.yield("forbidden")
		end)
		stops[3] = reader:bindToProgressChanged(function()
			count += 1
		end)
		task:setProgress(1, 2)
		expect(count == 2 and #warnings == 4)
		for _, stop in stops do
			stop()
		end
		task:setProgress(2, 2)
		expect(count == 2)
		task:complete()
	end
	app = new({ entry })
	app:start()
	app:deconstruct()
end)

test("subscribing during terminal replay does not skip existing outcome observers", function()
	local entry = registration("Terminal subscriptions")
	local app, events = nil, {}
	entry.construct = function(_, context)
		local task = context:createTask("Work")
		local reader = task:getReader()
		reader:bindToStateChanged(function(state)
			if state == "completed" then
				table.insert(events, "first")
				reader:bindToStateChanged(function(replayed)
					expect(replayed == "completed")
					table.insert(events, "replay")
				end)
			end
		end)
		reader:bindToStateChanged(function(state)
			if state == "completed" then
				table.insert(events, "second")
			end
		end)
		task:complete()
	end
	app = new({ entry })
	app:start()
	expect(table.concat(events, ",") == "first,replay,second")
	app:deconstruct()
end)

test("lifecycle observers cannot start or stop through immediate replay", function()
	local app = new({ registration("Replay") })
	for _, started in { false, true } do
		if started then
			app:start()
		end
		local verified = false
		local disconnect = app:getTelemetryReader():bindToPhaseChanged(function()
			rejects(function()
				app:start()
			end, "observers")
			rejects(function()
				app:deconstruct()
			end, "observers")
			verified = true
		end)
		expect(verified)
		disconnect()
	end
	app:deconstruct()
end)

test("lifecycle properties are committed together before independent notifications", function()
	local app = new({ registration("One") })
	local reader = app:getTelemetryReader()
	local count, valid = 0, true
	local stop = reader:bindToPhaseChanged(function(phase)
		count += 1
		if phase == "construct" then
			local completed, total = reader:getOperationProgress()
			valid = valid
				and reader:getName() == "One"
				and reader:getOperationState() == "running"
				and completed == 0
				and total == 2
		end
	end)
	expect(count == 1)
	app:start()
	expect(valid and count == 4)
	stop()
	app:deconstruct()
	expect(count == 4)
	local final
	reader:bindToPhaseChanged(function(phase)
		final = phase
	end)
	expect(final == "stopped")
end)

test("elapsed time reads live during operation and stops when callback ends", function()
	local time = 0
	local entry = registration("Timed")
	entry.construct = function(_, context)
		time = 3
		expect(context:getReader():getElapsedSeconds() == 3)
	end
	local app = new({ entry }, {}, nil, {
		clock = function()
			return time
		end,
		budgetSeconds = 100,
	})
	local elapsed
	app:getTelemetryReader():bindToOperationStateChanged(function(state)
		if state == "completed" and app:getTelemetryReader():getName() == "Timed" then
			elapsed = app:getTelemetryReader():getElapsedSeconds()
		end
	end)
	app:start()
	expect(elapsed == 3)
	app:deconstruct()
end)

test("profile registration callbacks are captured at construction", function()
	local entry, count = registration("Captured"), 0
	entry.construct = function()
		count += 1
	end
	local profile = {
		registrations = { entry },
		validate = function(graph)
			return graph
		end,
	}
	local app = Bootstrap.new(profile, {}, {
		clock = function()
			return 0
		end,
	})
	entry.construct = function()
		error("replacement")
	end
	entry.deconstruct = function()
		error("replacement cleanup")
	end
	table.clear(profile.registrations)
	profile.validate = function()
		error("replacement validation")
	end
	app:start()
	app:deconstruct()
	expect(count == 1)
end)

test("instances do not share graph or telemetry state", function()
	local entry = registration("Independent")
	entry.construct = function(graph, telemetry)
		graph.live = true
		local task = telemetry:createTask("Independent task")
		task:setStatus(tostring(graph.value))
	end
	entry.deconstruct = function(graph)
		graph.live = false
	end
	local first = new({ entry }, { value = 1 })
	local second = new({ entry }, { value = 2 })
	local a, b = first:start(), second:start()
	first:deconstruct()
	expect(a ~= b and not a.live and b.live and b.value == 2)
	expect(first:getTelemetryReader() ~= second:getTelemetryReader())
	second:deconstruct()
end)

test("actual example loads services lazily and keeps loading display until last cleanup", function()
	local loaded, displayed, reported = {}, {}, {}
	local exampleLoad = LoadPackage.new(function(path)
		loaded[path] = true
	end, recordWarning)
	local SampleProfile = exampleLoad("examples/sampleProfile.luau")
	local profile = SampleProfile.new({
		initialValue = 41,
		report = function(value)
			table.insert(reported, value)
		end,
		display = function(text)
			table.insert(displayed, text)
		end,
	})
	local context = {}
	local app = new(profile.registrations, context, profile.validate)
	for path in loaded do
		expect(not path:find("^examples/components/"), path .. " loaded eagerly")
	end
	local graph = app:start()
	expect(loaded["examples/components/sample/shared/sampleCounter.luau"])
	expect(loaded["examples/components/sample/shared/sampleReporter.luau"])
	expect(loaded["examples/components/sample/shared/sampleLoadingDisplay.luau"])
	expect(reported[1] == 41 and #reported == 1)
	expect(displayed[1] == "construct: Loading Display")
	expect(displayed[#displayed] == "ready: Bootstrap")
	expect(table.find(displayed, "construct: Counter / Prepare counter: Creating initial value (1/1)"))
	graph.sampleCounter:increment()
	expect(graph.sampleCounter:get() == 42)
	app:deconstruct()
	expect(next(context) == nil)
	local last = displayed[#displayed]
	expect(last == "deconstruct: Loading Display")
	rejects(function()
		graph.sampleCounter:get()
	end, "deconstructed")
	rejects(function()
		graph.sampleReporter:start()
	end, "deconstructed")
end)

test("loader isolates module caches without temporary source trees", function()
	local otherLoad = LoadPackage.new()
	expect(otherLoad("src/init.luau") ~= Bootstrap)
	expect(otherLoad("src/init.luau") == otherLoad("src/init.luau"))
end)

print(`Bootstrap: {cases} cases passed`)
