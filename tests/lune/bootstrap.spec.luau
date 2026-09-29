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
local function new(registrations, graphContext, validate, options, shutdown)
	options = table.clone(options or {})
	options.startPhases = options.startPhases or { "init", "wire", "start" }
	options.stopPhases = options.stopPhases or { "release" }
	options.clock = options.clock or function()
		return 0
	end
	return Bootstrap.new({
		registrations = registrations,
		validate = validate or function(graph)
			return graph
		end,
		shutdown = shutdown,
	}, graphContext or {}, options)
end
local function registration(name)
	return { name = name, construct = function() end, start = {}, stop = {}, destroy = function() end }
end

local function resume(thread)
	local ok, marker = coroutine.resume(thread)
	expect(ok, tostring(marker))
	return marker
end
local function launch(callback)
	local thread = coroutine.create(callback)
	return thread, resume(thread)
end
local function cooperativeOptions()
	return {
		yieldExecution = function()
			coroutine.yield("join")
		end,
	}
end

test("four sections preserve graph identity phase barriers and reverse final destruction", function()
	local events, context, graph = {}, {}, {}
	local entries = {}
	for _, name in { "A", "B" } do
		entries[#entries + 1] = {
			name = name,
			construct = function(value, telemetry)
				expect(value == context and telemetry:getReader():getPhase() == "construct")
				context[name] = true
				table.insert(events, "construct" .. name)
			end,
			start = {
				connect = function(value)
					expect(value == graph)
					table.insert(events, "connect" .. name)
				end,
				activate = function(value, telemetry)
					expect(
						value == graph and context.A and context.B and telemetry:getReader():getPhase() == "activate"
					)
					table.insert(events, "activate" .. name)
				end,
			},
			stop = {
				flush = function(value)
					expect(value == context)
					table.insert(events, "flush" .. name)
				end,
				detach = function()
					table.insert(events, "detach" .. name)
				end,
			},
			destroy = function(value, telemetry)
				expect(value == context and telemetry:getReader():getPhase() == "destroy")
				table.insert(events, "destroy" .. name)
			end,
		}
	end
	local app = new(entries, context, function(value)
		expect(value == context and context.A and context.B)
		table.insert(events, "validate")
		return graph
	end, { startPhases = { "connect", "activate" }, stopPhases = { "detach", "flush" } })
	expect(#events == 0 and app:getStatus() == "idle")
	expect(app:create() == graph and app:getStatus() == "running")
	local completed, total = app:getTelemetryReader():getOperationProgress()
	expect(completed == 7 and total == 7)
	app:destroy()
	app:destroy()
	expect(
		table.concat(events, ",")
			== "constructA,constructB,validate,connectA,connectB,activateA,activateB,detachA,detachB,flushA,flushB,destroyB,destroyA"
	)
	expect(app:getStatus() == "stopped")
	rejects(function()
		app:create()
	end, "only create once")
end)

test("invalid phase declarations and registration callbacks fail while inert", function()
	local function build(options, mutate)
		local entry = registration("Owner")
		local profile = {
			registrations = { entry },
			validate = function(graph)
				return graph
			end,
		}
		if mutate then
			mutate(profile, entry)
		end
		return Bootstrap.new(profile, {}, options or { startPhases = { "wire" }, stopPhases = { "release" } })
	end
	for _, options in
		{
			{ startPhases = { "wire", "wire" }, stopPhases = {} },
			{ startPhases = {}, stopPhases = { "release", "release" } },
			{ startPhases = { "wire", " " }, stopPhases = {} },
			{ startPhases = { "wire", 3 }, stopPhases = {} },
			{ startPhases = { [1] = "wire", [3] = "activate" }, stopPhases = {} },
			{ startPhases = { [1] = "wire", extra = "activate" }, stopPhases = {} },
		}
	do
		rejects(function()
			build(options)
		end, "")
	end
	for _, mutate in
		{
			function(_, entry)
				entry.start.unknown = function() end
			end,
			function(_, entry)
				entry.stop.unknown = function() end
			end,
			function(_, entry)
				entry.start.wire = 3
			end,
			function(_, entry)
				entry.stop.release = 3
			end,
			function(_, entry)
				entry.construct = nil
			end,
			function(_, entry)
				entry.destroy = nil
			end,
			function(_, entry)
				entry.construct = {}
			end,
			function(_, entry)
				entry.destroy = {}
			end,
			function(_, entry)
				entry.start = nil
			end,
			function(_, entry)
				entry.stop = nil
			end,
			function(profile)
				profile.registrations[3] = registration("Hole")
			end,
			function(profile)
				profile.registrations[2] = registration("Owner")
			end,
			function(profile)
				profile.shutdown = { { name = "Bad", run = 3 } }
			end,
		}
	do
		rejects(function()
			build(nil, mutate)
		end, "")
	end
	for _, budget in { -1, math.huge, 0 / 0 } do
		rejects(function()
			new({}, nil, nil, { budgetSeconds = budget })
		end, "budget")
	end
end)

test("empty phase arrays and absent optional phase callbacks still construct validate and destroy", function()
	local events = {}
	local entry = registration("Owner")
	entry.construct = function()
		table.insert(events, "construct")
	end
	entry.destroy = function()
		table.insert(events, "destroy")
	end
	entry.start.wire = nil
	entry.stop.release = nil
	local app = new({ entry }, nil, function(graph)
		table.insert(events, "validate")
		return graph
	end, { startPhases = {}, stopPhases = {} })
	app:create()
	app:destroy()
	expect(table.concat(events, ",") == "construct,validate,destroy")
	local sparse = new({ entry }, nil, nil, { startPhases = { "wire", "activate" }, stopPhases = { "release" } })
	sparse:create()
	sparse:destroy()
end)

test("partial creation failure cleans entered owners and preserves every failure", function()
	local events, context = {}, {}
	local entries = {}
	for _, name in { "A", "B", "Unused" } do
		local entry = registration(name)
		entry.construct = function(value)
			value[name] = true
			table.insert(events, "+" .. name)
			if name == "B" then
				error("creation cause")
			end
		end
		entry.destroy = function(value)
			expect(value == context and value[name])
			value[name] = nil
			table.insert(events, "-" .. name)
			if name == "A" then
				error("cleanup cause")
			end
		end
		entries[#entries + 1] = entry
	end
	local app = new(
		entries,
		context,
		function()
			error("validation must not run")
		end,
		nil,
		{
			{
				name = "Critical",
				run = function(value)
					expect(value == context)
					table.insert(events, "critical")
					error("critical cause")
				end,
			},
			{
				name = "Critical later",
				run = function()
					table.insert(events, "critical later")
				end,
			},
		}
	)
	local failure = rejects(function()
		app:create()
	end, "creation cause")
	expect(failure:find("cleanup cause", 1, true) and failure:find("critical cause", 1, true))
	expect(table.concat(events, ",") == "+A,+B,critical,critical later,-B,-A" and next(context) == nil)
	expect(app:getStatus() == "failed")
	expect(rejects(function()
		app:destroy()
	end, "creation cause") == failure)
	expect(app:getTelemetryReader():getFailure() == failure)
	rejects(function()
		app:create()
	end, "only create once")
end)

for _, phase in { "validate", "init", "wire", "start" } do
	test("failure at " .. phase .. " prevents later creation and cleans all entered owners", function()
		local events = {}
		local entries = { registration("A"), registration("B") }
		for _, entry in entries do
			for _, name in { "init", "wire", "start" } do
				entry.start[name] = function()
					table.insert(events, name .. entry.name)
					if name == phase then
						error("failed " .. phase)
					end
				end
			end
			entry.destroy = function()
				table.insert(events, "release" .. entry.name)
			end
		end
		local app = new(entries, nil, function(graph)
			if phase == "validate" then
				error("failed validate")
			end
			return graph
		end)
		rejects(function()
			app:create()
		end, "failed " .. phase)
		expect(events[#events - 1] == "releaseB" and events[#events] == "releaseA")
		if phase ~= "validate" then
			expect(events[#events - 2] == phase .. "A")
		end
	end)
end

test("idle shutdown attempts critical work without constructing or cleaning unused owners", function()
	local count = 0
	local entry = registration("Unused")
	entry.construct = function()
		error("must not construct")
	end
	entry.destroy = function()
		error("must not clean")
	end
	local app = new({ entry }, nil, nil, nil, { {
		name = "Preinstalled",
		run = function()
			count += 1
		end,
	} })
	app:destroy()
	app:destroy()
	expect(count == 1 and app:getStatus() == "stopped")
	rejects(function()
		app:create()
	end, "only create once")
end)

test("stop failure does not skip later owners phases or final destructors", function()
	local events = {}
	local a, b = registration("A"), registration("B")
	a.stop.release = function()
		table.insert(events, "failed stop")
		error("stop failed")
	end
	b.stop.release = function()
		table.insert(events, "later owner")
	end
	a.stop.finish = function()
		table.insert(events, "later phase")
	end
	b.destroy = function()
		table.insert(events, "failed destroy")
		error("destroy failed")
	end
	a.destroy = function()
		table.insert(events, "last destroy")
	end
	local app = new({ a, b }, nil, nil, { stopPhases = { "release", "finish" } })
	app:create()
	local failure = rejects(function()
		app:destroy()
	end, "stop failed")
	expect(failure:find("destroy failed", 1, true))
	expect(rejects(function()
		app:destroy()
	end, "stop failed") == failure)
	expect(table.concat(events, ",") == "failed stop,later owner,later phase,failed destroy,last destroy")
end)

test("destruction during suspended creation cancels later callbacks and joins cleanup", function()
	local entry, unused, events = registration("Active"), registration("Unused"), {}
	entry.construct = function(context)
		context.partial = true
		table.insert(events, "entered")
		coroutine.yield("creating")
		expect(context.partial)
		table.insert(events, "returned")
	end
	entry.start.wire = function()
		error("must not wire")
	end
	unused.construct = function()
		error("must not construct unused")
	end
	unused.destroy = function()
		error("must not clean unused")
	end
	entry.destroy = function(context)
		expect(context.partial)
		context.partial = nil
		table.insert(events, "cleanup")
		coroutine.yield("cleaning")
	end
	local app = new(
		{ entry, unused },
		nil,
		function()
			error("must not validate")
		end,
		cooperativeOptions(),
		{
			{
				name = "Critical",
				run = function()
					table.insert(events, "critical")
				end,
			},
		}
	)
	local creator, marker = launch(function()
		rejects(function()
			app:create()
		end, "creation cancelled")
	end)
	expect(marker == "creating")
	local first, firstMarker = launch(function()
		app:destroy()
		table.insert(events, "joined1")
	end)
	local second, secondMarker = launch(function()
		app:destroy()
		table.insert(events, "joined2")
	end)
	expect(firstMarker == "join" and secondMarker == "join" and table.concat(events) == "entered")
	expect(app:getStatus() == "creating")
	rejects(function()
		app:create()
	end, "only create once")
	expect(resume(creator) == "cleaning" and app:getStatus() == "destroying")
	expect(table.concat(events, ",") == "entered,returned,critical,cleanup")
	expect(resume(first) == "join" and resume(second) == "join")
	resume(creator)
	resume(first)
	resume(second)
	expect(
		coroutine.status(creator) == "dead" and coroutine.status(first) == "dead" and coroutine.status(second) == "dead"
	)
	expect(app:getStatus() == "stopped")
	app:destroy()
	expect(table.concat(events, ",") == "entered,returned,critical,cleanup,joined1,joined2")
end)

test("multiple destruction requests join a suspended failing cleanup with identical outcomes", function()
	local entry, count, failures = registration("Owner"), 0, {}
	entry.destroy = function()
		count += 1
		coroutine.yield("cleaning")
		error("shared failure")
	end
	local app = new({ entry }, nil, nil, cooperativeOptions())
	app:create()
	local function call()
		local failure = rejects(function()
			app:destroy()
		end, "shared failure")
		table.insert(failures, failure)
	end
	local owner, marker = launch(call)
	local first, a = launch(call)
	local second, b = launch(call)
	expect(marker == "cleaning" and a == "join" and b == "join" and count == 1)
	resume(owner)
	resume(first)
	resume(second)
	expect(#failures == 3 and failures[1] == failures[2] and failures[2] == failures[3])
	expect(rejects(function()
		app:destroy()
	end, "shared failure") == failures[1] and count == 1)
end)

test("critical shutdown finishes before unrelated yielding ordinary cleanup starts", function()
	local entry, critical, done = registration("Yield cleanup"), false, false
	entry.destroy = function()
		expect(critical)
		coroutine.yield("unrelated wait")
	end
	local app = new(
		{ entry },
		nil,
		nil,
		nil,
		{ {
			name = "Critical",
			run = function()
				critical = true
			end,
		} }
	)
	app:create()
	local owner, marker = launch(function()
		app:destroy()
		done = true
	end)
	expect(marker == "unrelated wait" and critical and not done)
	resume(owner)
	expect(done)
end)

test("cancellation during pacing never enters or cleans the pending owner", function()
	local entry, critical = registration("Pending"), 0
	entry.construct = function()
		error("must not enter")
	end
	entry.destroy = function()
		error("must not clean")
	end
	local app = new({ entry }, nil, nil, {
		budgetSeconds = 0,
		yieldExecution = function()
			coroutine.yield("paced")
		end,
	}, {
		{
			name = "Critical",
			run = function()
				critical += 1
			end,
		},
	})
	local creator = launch(function()
		rejects(function()
			app:create()
		end, "creation cancelled")
	end)
	local destroyer = launch(function()
		app:destroy()
	end)
	expect(resume(creator) == "paced") -- Critical work is paced too, after cancelled creation.
	expect(critical == 0)
	resume(creator)
	resume(destroyer)
	expect(critical == 1 and app:getStatus() == "stopped")
end)

test("reentrant calls fail explicitly from creation validation critical work and cleanup", function()
	local app, count = nil, 0
	local function reenter()
		rejects(function()
			app:create()
		end, "only create once")
		rejects(function()
			app:destroy()
		end, "Reentrant")
		count += 1
	end
	local entry = registration("Reentrant")
	entry.construct = reenter
	entry.destroy = reenter
	app = new({ entry }, nil, function(graph)
		reenter()
		return graph
	end, nil, { { name = "Critical", run = reenter } })
	app:create()
	app:destroy()
	expect(count == 4 and app:getStatus() == "stopped")
end)

test("default scheduler joins concurrent destruction across actual task waits", function()
	local task = require("@lune/task")
	local entry, calls, finished = registration("Scheduled"), 0, 0
	entry.destroy = function()
		calls += 1
		task.wait()
		task.wait()
	end
	local app = new({ entry })
	app:create()
	task.spawn(function()
		app:destroy()
		finished += 1
	end)
	app:destroy()
	finished += 1
	expect(calls == 1 and finished == 2 and app:getStatus() == "stopped")
end)

test("cancellation during suspended validation preserves partial context and stops activation", function()
	local entry, critical = registration("Owner"), false
	entry.construct = function(context)
		context.acquired = true
	end
	entry.start.init = function()
		error("must not activate")
	end
	entry.destroy = function(context)
		expect(context.acquired and critical)
		context.acquired = nil
	end
	local app = new(
		{ entry },
		nil,
		function(context)
			coroutine.yield("validation")
			expect(context.acquired)
			return { ready = true }
		end,
		cooperativeOptions(),
		{
			{
				name = "Critical",
				run = function(context)
					expect(context.acquired)
					critical = true
				end,
			},
		}
	)
	local creator, marker = launch(function()
		rejects(function()
			app:create()
		end, "creation cancelled")
	end)
	expect(marker == "validation")
	local destroyer, joined = launch(function()
		app:destroy()
	end)
	expect(joined == "join" and not critical)
	resume(creator)
	resume(destroyer)
	expect(critical and app:getStatus() == "stopped")
end)

test("creation failure during cancellation is shared with destruction joiners", function()
	local entry, failures, cleaned = registration("Owner"), {}, 0
	entry.construct = function()
		coroutine.yield("creation")
		error("creation failed during cancellation")
	end
	entry.destroy = function()
		cleaned += 1
	end
	local app = new({ entry }, nil, nil, cooperativeOptions())
	local creator = launch(function()
		local failure = rejects(function()
			app:create()
		end, "creation failed during cancellation")
		table.insert(failures, failure)
	end)
	local destroyer = launch(function()
		local failure = rejects(function()
			app:destroy()
		end, "creation failed during cancellation")
		table.insert(failures, failure)
	end)
	resume(creator)
	resume(destroyer)
	expect(#failures == 2 and failures[1] == failures[2] and cleaned == 1 and app:getStatus() == "failed")
end)

test("idle critical shutdown may yield and concurrent requests join it once", function()
	local count, joined = 0, 0
	local app = new(
		{},
		nil,
		nil,
		cooperativeOptions(),
		{ {
			name = "Critical",
			run = function()
				count += 1
				coroutine.yield("critical")
			end,
		} }
	)
	local owner, marker = launch(function()
		app:destroy()
		joined += 1
	end)
	local other, waiting = launch(function()
		app:destroy()
		joined += 1
	end)
	expect(marker == "critical" and waiting == "join" and count == 1 and joined == 0)
	resume(owner)
	resume(other)
	expect(count == 1 and joined == 2)
end)

test("phase arrays maps and critical callbacks are captured independently of authored mutations", function()
	local events, context = {}, {}
	local entry = registration("Captured")
	entry.construct = function(value)
		expect(value == context)
		table.insert(events, "create")
	end
	entry.destroy = function()
		table.insert(events, "destroy")
	end
	local shutdown =
		{ {
			name = "Captured critical",
			run = function()
				table.insert(events, "critical")
			end,
		} }
	entry.start.wire = function()
		table.insert(events, "wire")
	end
	entry.stop.release = function()
		table.insert(events, "stop")
	end
	local options = { startPhases = { "wire" }, stopPhases = { "release" } }
	local app = new({ entry }, context, nil, options, shutdown)
	entry.construct = function()
		error("replacement construct")
	end
	entry.destroy = function()
		error("replacement destroy")
	end
	table.clear(entry.start)
	table.clear(entry.stop)
	table.clear(options.startPhases)
	table.clear(options.stopPhases)
	shutdown[1].run = function()
		error("replacement")
	end
	table.clear(shutdown)
	app:create()
	app:destroy()
	expect(table.concat(events, ",") == "create,wire,critical,stop,destroy")
end)

test("an empty profile still validates and missing assignments fail before graph consumers", function()
	local app = new({})
	app:create()
	app:destroy()
	local entry = registration("Missing")
	entry.start.wire = function()
		error("must not wire")
	end
	app = new({ entry }, nil, function(context)
		return { service = assert(context.service, "missing service") }
	end)
	rejects(function()
		app:create()
	end, "missing service")
	expect(app:getStatus() == "failed")
end)

test("destruction during suspended start stops later starts and releases every constructed owner", function()
	local context, graph, events = {}, {}, {}
	local a, b = registration("A"), registration("B")
	a.construct = function(value)
		value.a = true
	end
	b.construct = function(value)
		value.b = true
	end
	a.start.init = function(value)
		expect(value == graph)
		table.insert(events, "start entered")
		coroutine.yield("starting")
		expect(context.a and context.b)
		table.insert(events, "start returned")
	end
	b.start.init = function()
		error("must not start B")
	end
	a.start.wire = function()
		error("must not wire")
	end
	for _, entry in { a, b } do
		entry.stop.release = function(value)
			expect(value == context and value.a and value.b)
			table.insert(events, "stop" .. entry.name)
		end
		entry.destroy = function()
			table.insert(events, "destroy" .. entry.name)
		end
	end
	local app = new(
		{ a, b },
		context,
		function()
			return graph
		end,
		cooperativeOptions(),
		{ {
			name = "Critical",
			run = function()
				table.insert(events, "critical")
			end,
		} }
	)
	local creator, marker = launch(function()
		rejects(function()
			app:create()
		end, "creation cancelled")
	end)
	local destroyer, joined = launch(function()
		app:destroy()
	end)
	expect(marker == "starting" and joined == "join" and table.concat(events) == "start entered")
	resume(creator)
	resume(destroyer)
	expect(table.concat(events, ",") == "start entered,start returned,critical,stopA,stopB,destroyB,destroyA")
	expect(app:getStatus() == "stopped")
end)

test("multiple destruction requests join suspended stop and wait for final destruction", function()
	local entry, events, joined = registration("Owner"), {}, 0
	entry.stop.release = function()
		table.insert(events, "stop")
		coroutine.yield("stopping")
	end
	entry.destroy = function()
		table.insert(events, "destroy")
		coroutine.yield("destroying")
	end
	local app = new({ entry }, nil, nil, cooperativeOptions())
	app:create()
	local owner, marker = launch(function()
		app:destroy()
		joined += 1
	end)
	local other, waiting = launch(function()
		app:destroy()
		joined += 1
	end)
	expect(marker == "stopping" and waiting == "join" and joined == 0 and #events == 1)
	expect(resume(owner) == "destroying" and joined == 0)
	expect(resume(other) == "join")
	resume(owner)
	resume(other)
	app:destroy()
	expect(table.concat(events, ",") == "stop,destroy" and joined == 2)
end)

test("stop handles partially constructed owners even when start never ran", function()
	local context, events = {}, {}
	local a, b, unused = registration("A"), registration("B"), registration("Unused")
	a.construct = function(value)
		value.a = true
	end
	b.construct = function(value)
		value.partial = true
		error("partial constructor")
	end
	for _, entry in { a, b } do
		entry.start.init = function()
			error("must not start")
		end
		entry.stop.release = function(value)
			expect(value == context and value.a and value.partial)
			table.insert(events, "stop" .. entry.name)
		end
		entry.destroy = function()
			table.insert(events, "destroy" .. entry.name)
		end
	end
	unused.stop.release = function()
		error("must not stop unused")
	end
	unused.destroy = function()
		error("must not destroy unused")
	end
	local app = new({ a, b, unused }, context)
	rejects(function()
		app:create()
	end, "partial constructor")
	expect(table.concat(events, ",") == "stopA,stopB,destroyB,destroyA")
end)

test("critical work precedes a suspended stop and reentrancy is rejected in start and stop", function()
	local app, entry, critical, destroyed = nil, registration("Owner"), false, false
	local function reenter()
		rejects(function()
			app:create()
		end, "only create once")
		rejects(function()
			app:destroy()
		end, "Reentrant")
	end
	entry.start.init = reenter
	entry.stop.release = function()
		expect(critical)
		reenter()
		coroutine.yield("stop wait")
	end
	entry.destroy = function()
		destroyed = true
	end
	app = new({ entry }, nil, nil, nil, { {
		name = "Critical",
		run = function()
			critical = true
		end,
	} })
	app:create()
	local owner, marker = launch(function()
		app:destroy()
	end)
	expect(marker == "stop wait" and critical and not destroyed)
	resume(owner)
	expect(destroyed)
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
	entries[2].destroy = function()
		time += 0.005
	end
	entries[1].destroy = function()
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
	app:create()
	expect(yields == 2 and table.concat(events) == "AB")
	time += 100
	app:destroy()
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
	app:create()
	app:destroy()
	expect(table.concat(states, ",") == "construct:One,validate:graph,destroy:One")
end)

test("default scheduler supports the real Lune task wait boundary", function()
	local app = new({ registration("Default yield") }, {}, nil, { budgetSeconds = 0 })
	app:create()
	app:destroy()
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
	entry.start.init = function(_, context)
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
	app:create()
	expect(retainedContext:getReader() == reader)
	local terminalReplay
	retainedTask:getReader():bindToStateChanged(function(state)
		terminalReplay = state
	end)
	expect(terminalReplay == "completed")
	app:destroy()
end)

test("active tasks preserve creation order and focus survives out of order completion", function()
	local entry = registration("Tasks")
	local focuses, removed, added = {}, {}, {}
	local app
	entry.start.wire = function(_, context)
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
	app:create()
	expect(table.concat(added, ",") == "First,Middle,Last")
	expect(table.concat(removed, ",") == "Middle,Last,First")
	expect(table.concat(focuses, ",") == "none,First,Middle,Last,First,none")
	app:destroy()
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
	app:create()
	app:destroy()
end)

test("callback exit cancels unfinished tasks in all four sections", function()
	local entry, tasks = registration("Scoped"), {}
	local function callback(_, context)
		expect(context:getReader():getTaskCount() == 0)
		table.insert(tasks, context:createTask(context:getReader():getPhase()))
	end
	entry.construct, entry.destroy = callback, callback
	entry.start.init, entry.start.wire, entry.start.start = callback, callback, callback
	entry.stop.release = callback
	local app = new({ entry })
	app:create()
	expect(#tasks == 4)
	for _, task in tasks do
		expect(task:getReader():getState() == "cancelled")
		rejects(function()
			task:setProgress(1, 1)
		end, "finished")
	end
	app:destroy()
	expect(#tasks == 6)
	for _, task in tasks do
		expect(task:getReader():getState() == "cancelled")
	end
	expect(app:getTelemetryReader():getTaskCount() == 0)
end)

test("throwing callback cancels its tasks before rollback begins", function()
	local entry, task, checked = registration("Failure"), nil, false
	entry.start.init = function(_, context)
		task = context:createTask("Pending")
		error("callback failure")
	end
	entry.destroy = function(_, context)
		checked = task:getReader():getState() == "cancelled" and context:getReader():getTaskCount() == 0
	end
	local app = new({ entry })
	rejects(function()
		app:create()
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
	app:create()
	expect(app:getStatus() == "running" and table.concat(events, ",") == "outcome,removed")
	app:destroy()
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
				app:destroy()
			end, "observers")
			rejects(function()
				app:create()
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
	app:create()
	app:destroy()
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
	app:create()
	expect(table.concat(events, ",") == "first,replay,second")
	app:destroy()
end)

test("lifecycle observers cannot start or stop through immediate replay", function()
	local app = new({ registration("Replay") })
	for _, started in { false, true } do
		if started then
			app:create()
		end
		local verified = false
		local disconnect = app:getTelemetryReader():bindToPhaseChanged(function()
			rejects(function()
				app:create()
			end, "observers")
			rejects(function()
				app:destroy()
			end, "observers")
			verified = true
		end)
		expect(verified)
		disconnect()
	end
	app:destroy()
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
	app:create()
	expect(valid and count == 4)
	stop()
	app:destroy()
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
	app:create()
	expect(elapsed == 3)
	app:destroy()
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
		startPhases = { "init", "wire", "start" },
		stopPhases = { "release" },
		clock = function()
			return 0
		end,
	})
	entry.construct = function()
		error("replacement")
	end
	entry.destroy = function()
		error("replacement cleanup")
	end
	table.clear(profile.registrations)
	profile.validate = function()
		error("replacement validation")
	end
	app:create()
	app:destroy()
	expect(count == 1)
end)

test("instances do not share graph or telemetry state", function()
	local entry = registration("Independent")
	entry.construct = function(graph, telemetry)
		graph.live = true
		local task = telemetry:createTask("Independent task")
		task:setStatus(tostring(graph.value))
	end
	entry.destroy = function(graph)
		graph.live = false
	end
	local first = new({ entry }, { value = 1 })
	local second = new({ entry }, { value = 2 })
	local a, b = first:create(), second:create()
	first:destroy()
	expect(a ~= b and not a.live and b.live and b.value == 2)
	expect(first:getTelemetryReader() ~= second:getTelemetryReader())
	second:destroy()
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
	local app = new(
		profile.registrations,
		context,
		profile.validate,
		{ startPhases = { "init", "wire", "activate" }, stopPhases = { "quiesce", "persist" } }
	)
	for path in loaded do
		expect(not path:find("^examples/components/"), path .. " loaded eagerly")
	end
	local graph = app:create()
	expect(loaded["examples/components/sample/shared/sampleCounter.luau"])
	expect(loaded["examples/components/sample/shared/sampleReporter.luau"])
	expect(loaded["examples/components/sample/shared/sampleLoadingDisplay.luau"])
	expect(reported[1] == 41 and #reported == 1)
	expect(displayed[1] == "construct: Loading Display")
	expect(displayed[#displayed] == "ready: Bootstrap")
	expect(table.find(displayed, "construct: Counter / Prepare counter: Creating initial value (1/1)"))
	graph.sampleCounter:increment()
	expect(graph.sampleCounter:get() == 42)
	app:destroy()
	expect(next(context) == nil)
	local last = displayed[#displayed]
	expect(last == "destroy: Loading Display")
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
