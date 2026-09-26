# Bootstrap

A typed lifecycle runner for ordered, named service registrations. Profiles choose what loads.
Bootstrap runs phase barriers, budgets time between operations, reports progress, and releases
entered registrations in reverse order.

## Entry and usage

The package entry is `src/init.luau`, so the package root becomes a Roblox ModuleScript.
`Bootstrap.new` is the only top-level runtime export.

```luau
local graphContext: SampleGraphContext = {}
local application = Bootstrap.new(SampleProfile.new(options), graphContext, {
    budgetSeconds = 0.004,
})
local reader = application:getTelemetryReader()
reader:bindToPhaseChanged(function(phase)
    print(phase, reader:getName())
end)
local graph = application:start()
graph.sampleCounter:increment()
application:deconstruct()
```

See the [executable profile](examples/sampleProfile.luau) and
[typed host usage](tests/typechecks/accepted.luau). The example includes a loading-display
collaborator; its display callback can drive a host-owned UI.

## Registrations and typed graphs

A profile contains an ordered `registrations` array and a `validate(graphContext) -> G` function.
Each registration requires **`name`, `construct`, and `deconstruct`**.
`init`, `wire`, and `start` are optional. Names are unique, nonblank human-readable labels.
There is no field-name metadata. Callbacks assign fields directly, with normal Luau typechecking.

| Callback | Graph received | Responsibility |
| --- | --- | --- |
| `construct(graphContext, telemetryContext)` | Construction graph `C` | Lazily require implementations, construct objects, assign their fields. |
| `init(graphContext, telemetryContext)` | Complete graph `G` | Prepare owned resources. |
| `wire(graphContext, telemetryContext)` | Complete graph `G` | Inject narrow capabilities into collaborators. |
| `start(graphContext, telemetryContext)` | Complete graph `G` | Begin active behavior. |
| `deconstruct(graphContext, telemetryContext)` | Original construction graph `C` | Release owned resources and clear fields, tolerating partial startup. |

Construction fields are optional because the graph starts empty. After all constructors finish,
`validate` asserts the required fields and returns the complete graph. That graph is passed unchanged
to every later startup callback and returned from `start`. It can be a new table holding the same
constructed objects; Bootstrap does not clone service instances. Deconstruction always receives
the original construction graph, even if validation failed.

A registration looks like this inside a typed profile:

```luau
{
    name = "Camera Service",
    construct = function(graphContext, telemetryContext)
        local task = telemetryContext:createTask("Prepare camera")
        task:setStatus("Constructing camera")
        local CameraService = require(script.Parent.cameraService)
        graphContext.cameraService = CameraService.new()
        task:complete()
    end,
    wire = function(graphContext)
        graphContext.cameraService:wire(graphContext.playerService:getReader())
    end,
    deconstruct = function(graphContext)
        local cameraService = graphContext.cameraService
        graphContext.cameraService = nil
        if cameraService then
            cameraService:deconstruct()
        end
    end,
}
```

The snippet assumes application-owned services; the executable example is self-contained.
Construction options belong to the profile factory and its callback closures. Bootstrap accepts
the initial graph context, not a separate generic service-options object.

The composition owner sees the graph. Services receive only the ports they need. There is no
service locator, inferred dependency graph, reflective discovery, or type function. Client/server
profiles choose different registrations. Keep implementation requires **inside `construct`**;
requiring a profile should load only inert composition code and type leaves.

## Phase ordering and lifecycle

For registrations A and B, the order is:

```text
construct A -> construct B -> validate
init A      -> init B
wire A      -> wire B
start A     -> start B
running
deconstruct B -> deconstruct A
```

Missing optional callbacks are skipped. Each phase completes before the next begins.
Callbacks execute sequentially on the caller's coroutine; yielding holds the phase barrier.
Promises are not implicitly awaited. Await them inside the callback when needed, and never wait
for a producer that only starts in a later phase.

`new` captures and freezes registration callback references without running them. It retains
the profile callbacks until shutdown for cleanup. Captured application options and graph objects
remain caller-owned references.

Each runner is single-use. `start` requires `idle`. Status moves through `constructing`,
`validating`, `initializing`, `wiring`, `starting`, and `running`. Shutdown uses
`deconstructing`, then `stopped` or `failed`. Empty optional phases have no telemetry operations.
Deconstructing an idle runner prevents startup without constructing anything.

Reentrant lifecycle calls are rejected, including while callbacks are yielding and from telemetry
observers. There is no detached worker, implicit cancellation, retry, restart, or timeout policy.

## Pacing and long operations

`budgetSeconds` defaults to **0.004 seconds**. Before each operation, Bootstrap checks elapsed time
since the last yield and yields with `task.wait()` once the budget is consumed. A value of zero
yields before every operation. Shutdown and rollback use the same pacing, with a fresh time budget.

An individual callback or `require` cannot be preempted by Bootstrap. Long loops must cooperate:

```luau
local task = telemetryContext:createTask("Build definitions")
for index, definition in definitions do
    build(definition)
    if index % 100 == 0 then
        task:setProgress(index, #definitions)
        telemetryContext:checkpoint()
    end
end
task:complete()
```

`checkpoint()` uses the same elapsed-time budget; it does not necessarily yield on every call.
Avoid heavy top-level module work and split genuinely expensive tasks into bounded chunks.
Yielding between phases alone cannot prevent one large constructor from timing out.

Hosts/tests may inject `clock: () -> number` and `yieldExecution: () -> ()`.
The clock must be monotonic and non-yielding; both scheduler functions must work without throwing.
Pacing gives the scheduler opportunities to run; it does not enforce a hard frame-time limit.

## Telemetry tasks and loading UI

Each registration callback receives a `BootstrapTelemetryContext` with three methods:

- `createTask(name) -> BootstrapTelemetryTask`: create active work owned by this operation.
- `getReader() -> BootstrapTelemetryReader`: observe the lifecycle and active task collection.
- `checkpoint()`: cooperate with the runner's time budget.

The context is frozen. Its method fields are typed `read`, so callers can invoke them but cannot
replace them. This does not make the tasks created through the context read-only.

The host can also obtain `application:getTelemetryReader()` before calling `start`.
The context has no arbitrary metadata fields, snapshot setter, or combined change notification.

```luau
wire = function(graph, telemetryContext)
    local task = telemetryContext:createTask("Load weapon models")
    task:setStatus("Waiting for assets")
    task:setProgress(0, #models)

    for index, model in models do
        loadModel(model)
        task:setProgress(index, #models)
        telemetryContext:checkpoint()
    end

    task:setStatus("Finalizing")
    task:complete()
end
```

### Task commands and readers

The task returned to its creator is the write/lifecycle capability. `task:getReader()` returns
its read-only capability without allocating a wrapper.

| Task command | Meaning |
| --- | --- |
| `setStatus(string?)` | Arbitrary display text. Nil clears it. It does not change progress or outcome. |
| `setProgress(completed, total)` | Finite numeric progress with `0 <= completed <= total` and `total > 0`. It does not change status text. |
| `clearProgress()` | Clear both progress numbers, representing unknown progress. |
| `complete()` | Finish successfully. Reaching total progress alone does not complete a task. |
| `fail(message)` | Finish with a failure message. This reports an outcome; it does not throw or abort Bootstrap. |
| `cancel()` | Finish without success or failure. It does not cancel the underlying service work. |

State is `active`, `completed`, `failed`, or `cancelled`. The string passed to `setStatus` is
independent: even `setStatus("completed")` is only display text. Repeating the same terminal
command is harmless and preserves the first outcome; attempting a different outcome or writing
status/progress afterward fails. There is no reactivation or separate release operation.

Task readers provide:

- `getName()`, `getPhase()`, `getOperationName()` for immutable identity. Phase and the registration
  label are captured from the creating operation.
- `getStatus()`, `getProgress() -> (number?, number?)`, `getState()`, `getFailure()`.
- `bindToStatusChanged(callback)`, `bindToProgressChanged(callback)`, and
  `bindToStateChanged(callback)`, each returning an idempotent disconnect function.

Each property binding immediately replays its current value. Progress delivers both numbers
as arguments; no progress means both are nil. Identical writes do not notify.
Failure text is installed before the state callback, so failure observers read it with `getFailure()`.

### Active collection and focus

The telemetry reader provides:

- `getTaskCount()` and `forEachTask(callback, phase?)`: visit active tasks in creation order,
  optionally filtering by phase, without allocating an array copy.
- `getFocusedTask()`: the newest active task, or nil.
- `bindToTaskAdded(callback)` and `bindToTaskRemoved(callback)`: future collection events only.
- `bindToFocusedTaskChanged(callback)`: immediately replay focus, then observe changes.

A list UI subscribes to added/removed events and enumerates existing tasks. A compact UI follows
focus and binds separately to the focused reader's status/progress. See the
[loading display example](examples/components/sample/shared/sampleLoadingDisplay.luau).

Tasks can finish out of order. Completing an older task preserves focus; completing the focused
task reveals the newest remaining one. Creation-order storage uses an array: adding/finding focus
is O(1), removing a task is O(active tasks), and traversal is O(active tasks). This is intended for
small sets of meaningful startup tasks, not one telemetry task per asset or simulation entity.

Terminal tasks are removed automatically. Outcome and collection membership are updated before
state notifications, followed by task-removed and, if needed, focus notifications. Task listeners
are released after terminal notification. A retained reader still exposes its terminal values and
can replay them, but Bootstrap retains no completed-task history. A diagnostic consumer may record
outcomes if historical information is needed.

### Lifetime and allocation

Tasks belong to the particular phase callback that created them. On normal return **or error**,
Bootstrap cancels every unfinished task before proceeding to the next operation or rollback.
The context's `createTask` and `checkpoint` then expire; `getReader` remains usable. Asynchronous
work must be awaited within that callback if its telemetry task should remain active. Finishing
telemetry does not stop that asynchronous work; service code owns its cancellation.

A task starts with one state table and allocates each property's signal/listener storage only on
its first subscription. Setters mutate private state in place. They do not clone snapshots or
field maps. Observer delivery still creates a coroutine to isolate errors and forbidden yields;
this is not a claim that notifications are allocation-free.

### Automatic lifecycle information

The telemetry reader also exposes Bootstrap-owned information independently of tasks:

| Getter | Meaning |
| --- | --- |
| `getPhase()` | `idle`, `construct`, `validate`, `init`, `wire`, `start`, `deconstruct`, `ready`, `stopped`, or `failed`. |
| `getName()` | Current registration label; nil for graph validation and terminal phases. |
| `getOperationState()` | `pending`, `running`, `completed`, or `failed`. |
| `getOperationProgress()` | Completed/total callback counts, including startup validation. Shutdown counts entered registrations; stopped/failed reset counts to zero. This is not a time estimate. |
| `getElapsedSeconds()` | Live elapsed operation time while running, held at completion; terminal phases reset it to zero. |
| `getFailure()` | Current operation or terminal failure text, when present. |

Phase, name, operation state, operation progress, and failure each have a corresponding
`bindTo...Changed` method with immediate replay. Elapsed time is queried; there is no timer pump.
Lifecycle transitions install all values before firing the individual property notifications.

Observers must return synchronously. Errors are warned and isolated; yielding observers are closed
and warned. Observers may subscribe or disconnect, including subscribing to a newly added task.
They cannot mutate telemetry, checkpoint, or change Bootstrap's lifecycle during notification.
Enumeration callbacks obey the same rules. Shutdown publishes terminal lifecycle values and clears
remaining listeners. Retained readers can read/replay those final values.

Place the UI registration first. It subscribes through `telemetryContext:getReader()` during its
constructor and remains available through later service loading; reverse shutdown releases it last.
The package owns no GUI, ReplicatedFirst behavior, or engine shutdown hook. The client/server entry
script connects those application-specific policies.

## Cleanup and failure

Every entered constructor gets one deconstruction attempt, including a constructor that throws.
Registrations not reached do not get deconstructed. Deconstructors must tolerate missing fields
and partially initialized or wired objects. Publish acquired objects into the construction graph
as soon as cleanup can safely own them. An object constructor that throws before returning must
release its own unpublished resources.

A failure in construction, validation, initialization, wiring, or startup prevents later work
and triggers reverse deconstruction. Cleanup errors do not skip remaining registrations. The
eventual error includes phase/name context, the original traceback, and collected cleanup failures.
Ordinary shutdown likewise reports failures after attempting every entered registration.

Shutdown is idempotent after completion/failure; failed cleanup is not retried. Returned graph
references are no longer valid for live use after teardown. Each registration owns its resources;
do not double-release a child already owned by another object. Long-running tasks and cancellation
belong to the service that starts them.

## Public types

- `Bootstrap<G>`: start, status, telemetry reader, and deconstruction.
- `BootstrapOptions`: pacing and scheduler options.
- `BootstrapProfile<C, G>` and `BootstrapRegistration<C, G>`: named lifecycle composition.
- `BootstrapTelemetryContext`, `BootstrapTelemetryReader`.
- `BootstrapTelemetryTask`, `BootstrapTelemetryTaskReader`, `BootstrapTelemetryTaskState`.
- `BootstrapStatus`, `BootstrapPhase`, `BootstrapOperationState`.

`C` is the construction/cleanup graph; `G` is the validated graph. The telemetry key generic `K`,
`BootstrapTelemetrySnapshot`, `getSnapshot`, aggregate `bindToChanged`, `onProgress` option, and
context `setDetail`/`setField`/`setProgress` have been removed. Create an operation-owned task for
status and progress instead. This is a breaking package rewrite; consumers are not migrated here.

## Verification

Use PowerShell 7 and the Rokit versions in `rokit.toml`. No runtime package dependencies are needed.
This repository owns its checks; VMMO's analyzer baseline does not apply.
The guarded analyzer explicitly enables Luau's new solver (`LuauSolverV2`), and the workspace's
VS Code settings select the same solver. The pinned luau-lsp version remains 1.66.0.

Place pinned Roblox definitions at `.verification/globalTypes.d.luau`, or pass
`-Definitions <path>`. Keep the same definitions for before/after comparisons.
Checks do not install dependencies, update definitions, publish, or migrate consumers.

```powershell
./scripts/verify/run.ps1 -Check tests
./scripts/verify/run.ps1 -Check analyze -OutDir .verification/after
./scripts/verify/run.ps1 -Check types
./scripts/lint/run.ps1 -Check stylua
./scripts/lint/run.ps1 -Check selene
./scripts/build/run.ps1
```

The full positive analyzer surface is `src`, `examples`, and `tests/typechecks/accepted.luau`.
Expect zero diagnostics. The rejected fixture is checked separately; every marked misuse must
produce an error at its marked line with no unexpected type errors. Captures and per-file counts
are saved under the selected output directory.

The build writes an ignored model, package-only `sourcemap.json`, and `examples-sourcemap.json`.
The editor/analyzer use the latter, from `verification.project.json`.

### Reviewing examples in VS Code

Open this repository folder as the workspace. `.vscode/settings.json` enables automatic generation
of `examples-sourcemap.json`. That tree places the package ModuleScript, examples, and type
fixtures under ReplicatedStorage, matching their literal `script` paths.
Package-only builds do not overwrite the editor's map. Use the build script to regenerate both.
If an open editor retains stale paths, restart its Luau language server or reload the window.
Rojo must resolve to the Rokit shim on the editor's PATH. The rejected fixture is deliberately
excluded from background diagnostics; opening it intentionally displays errors.

The Lune harness executes original source in memory with a minimal script tree and an independent
module cache per loader. It creates no temporary source trees. Behavioral tests construct the
public runner and actual example. Lune supplies its real task scheduler for the default-yield test;
injected clocks/schedulers make pacing assertions deterministic.
Set `LUNE_LUAU_JIT=0` for an interpreter run. Roblox UI integration and engine shutdown remain
the consuming application's Studio verification responsibility.
