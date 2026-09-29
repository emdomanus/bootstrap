# Bootstrap

A typed lifecycle controller with four registration sections: construct, phased start, phased stop,
and destroy. Profiles own composition; Bootstrap owns ordering, execution pacing, progress, and
cleanup eligibility. The package entry is `src/init.luau`; `Bootstrap.new` is its only top-level
runtime export.

## Entry and usage

```luau
local application = Bootstrap.new(profile, graphContext, {
    startPhases = { "init", "wire", "activate" },
    stopPhases = { "quiesce", "persist" },
    budgetSeconds = 0.004,
})
-- Register the host's shutdown hook here, before create can yield.
-- The hook calls application:destroy(). Handle its reported error at the host boundary.
local graph = application:create()
-- Use the graph while application:getStatus() == "running".
application:destroy()
```

Start and stop phase names are application choices, with distinct literal-union types. Annotate
options/maps at their authoring boundary. See the [typed host usage](tests/typechecks/accepted.luau)
and [executable profile](examples/sampleProfile.luau). The sample constructs its loading display
first, so reverse final destruction keeps it alive until every other owner has been released.

## Registrations and typed graphs

`BootstrapProfile<C, G, StartPhase, StopPhase>` contains:

- `registrations`: an ordered array of named resource owners.
- `validate(context: C) -> G`: runs once after every constructor succeeds and before any start
  callback. It checks and returns the complete graph, without an unchecked cast.
- `shutdown`: optional ordered `{ name, run(context: C, telemetryContext) }` callbacks installed
  before creation. These always run on destruction, independently of registration entry.

Each registration requires a semantic `name` and four sections:

| Section | Shape | Callback context | Responsibility |
| --- | --- | --- | --- |
| `construct` | One required callback | Partial context `C` | Instantiate objects and assign graph fields. |
| `start` | Map keyed by `StartPhase` | Validated graph `G` | Initialize, wire, and activate objects. |
| `stop` | Map keyed by `StopPhase` | Original context `C` | Coordinate quiescence, persistence, and shutdown. |
| `destroy` | One required callback | Original context `C` | Release owned resources after all stop attempts. |

The two maps are required but may be empty. Their values are explicitly optional:
`BootstrapCallbacks<C, P> = { [P]: ((C, BootstrapTelemetryContext) -> ())? }`.
Missing/nil callbacks are skipped. A lookup must be narrowed before calling it. There is no
requirement to implement every phase and no phase generic for `construct` or `destroy`.
Every callback also receives `BootstrapTelemetryContext`.

```luau
type StartPhase = "activate"
type StopPhase = "quiesce"
type Context = { count: number? }
type Graph = { count: number }

local profile: Bootstrap.BootstrapProfile<Context, Graph, StartPhase, StopPhase> = {
    validate = function(context: Context): Graph
        return { count = assert(context.count, "Count was not constructed") }
    end,
    registrations = {{
        name = "Counter",
        construct = function(context: Context)
            context.count = 1
        end,
        start = {
            ["activate" :: StartPhase] = function(graph: Graph)
                print(graph.count)
            end,
        },
        stop = {
            ["quiesce" :: StopPhase] = function(context: Context)
                -- Tolerate a partial graph, including a throwing constructor.
                print(context.count)
            end,
        },
        destroy = function(context: Context)
            context.count = nil
        end,
    }},
    shutdown = {{
        name = "Host shutdown work",
        run = function(context: Context)
            -- Attempt work using preinstalled capabilities or whatever was acquired.
            -- This also runs with an empty context; do not construct unused services here.
            print(context.count)
        end,
    }},
}
local options: Bootstrap.BootstrapOptions<StartPhase, StopPhase> = {
    startPhases = { "activate" :: StartPhase },
    stopPhases = { "quiesce" :: StopPhase },
}
local context: Context = {}
local application = Bootstrap.new(profile, context, options)
local graph = application:create()
application:destroy()
```

The complete graph may be a different table containing the same acquired objects. Bootstrap passes
that exact validated value to every start callback and returns it from `create`. Stop, destroy,
and critical shutdown always receive the original context, including after validation fails.
The composition owner sees the graph; services receive only injected capabilities. Keep implementation
requires inside construct callbacks. There is no service locator or reflective discovery.

## Ordering, ownership, and cancellation

`new` validates and copies phase arrays, registration callbacks/maps, and shutdown callback references
without executing application callbacks. Subsequent declaration edits do not change the controller.
Captured closure values and graph objects remain caller-owned references. Arrays must be dense,
phase names nonblank strings and unique within each array, and owner names unique within their list.
The same phase spelling may occur in both arrays. Supplied start/stop callbacks must belong to a
declared phase. Both arrays, either map, and the registration array may be empty.

```text
application:create():
  construct A -> construct B -> validate
  first start phase A -> first start phase B
  next start phase A  -> next start phase B -> running

application:destroy():
  critical shutdown callbacks
  first stop phase A -> first stop phase B
  next stop phase A  -> next stop phase B
  destroy B -> destroy A
```

Constructors run in registration order. Start and stop each iterate their own supplied phase array,
then the registration array in forward order. Dictionary iteration never schedules callbacks. Final
destructors run in reverse registration order, after all eligible stop attempts. Stop failures do
not skip later stop callbacks or destructors; destructor failures do not skip remaining destructors.
Each callback returns before the next begins; Promises must be explicitly awaited inside callbacks.

Entry into `construct` acquires cleanup ownership for that registration, even if it throws. Every
stop callback and the final destructor of an entered owner gets one attempt, tolerating absent or
partially initialized fields **even when no start callback ran**. Unentered owners receive neither
stop nor destroy. Publish acquired resources into `C` as soon as cleanup can safely own them; a
constructor that throws before publishing must release its own unpublished resources. Detached
service work remains service-owned. The four sections do not add restart support: this controller
still has one creation and one destruction operation.

Status is `idle`, `creating`, `running`, `destroying`, then `stopped` or `failed`.
`create` is single-use; concurrent, repeated, or reentrant calls fail. `destroy` from another
coroutine during creation sets a cancellation request and waits for that lifecycle owner. The active
callback may finish, but no later constructor, validation, or start callback begins. Bootstrap also
checks after its pre-callback pacing yield, before acquiring an owner. `checkpoint()` within a
callback paces that callback; it does not unwind it. Cleanup starts only after the active creation
callback returns or throws, so creation and destruction never mutate the owned graph concurrently.

Concurrent destruction callers join that one operation, including while critical work, stop, or
destroy yields. Completion is single-shot. After successful destruction, repeated `destroy` calls
return without work. After terminal failure, every joined or repeated `destroy` rethrows the same
stored aggregate, with no retries. Cancellation alone produces `stopped`: `create` throws a
cancellation error and joined `destroy` calls return successfully. Creation or cleanup exceptions
produce `failed` and take precedence over the cancellation message.

Calling `destroy` from the active callback's own coroutine is rejected before requesting shutdown,
preventing a self-join deadlock. This applies to constructors, validation, start, stop, destroy, and
critical shutdown callbacks. Telemetry observers cannot call lifecycle methods. Do not synchronously
await a child coroutine that joins your own lifecycle operation; Bootstrap cannot detect arbitrary
cycles in application waits.

## Critical shutdown and limits

Profile `shutdown` callbacks run first, in their explicit array order, before **any** ordinary stop
or destroy callback. They run even from idle and after incomplete, cancelled, or failed creation.
They are a generic mechanism for preinstalled critical work, including application-owned persistence
attempts; Bootstrap has no storage or Roblox service knowledge. Each must tolerate partial context.
If a persistence attempt needs quiescence, include that coordination in this ordered critical prefix;
ordinary `stopPhases` have not run yet. Do not give two callbacks ownership of the same release.

Prioritizing critical work prevents unrelated ordinary cleanup from trapping it behind a yield.
It does not bypass an active creation callback or an earlier critical callback. All callbacks remain
sequential to protect shared resources. A callback that never returns can prevent shutdown completion,
and a nonreturning creation callback prevents even the critical prefix from starting. Schedule
bounded, cooperative critical callbacks in priority order. Bootstrap does not forcibly terminate
callbacks, impose timeouts, guarantee persistence, or extend an external host shutdown deadline.
The host owns deadlines and any independently safe emergency persistence path. Killing the coroutine
that owns creation/destruction also abandons its joiners; keep it alive until the operation settles.

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
`yieldExecution` also parks destruction joiners: it must actually yield whenever another operation
is active (a no-op is only suitable for synchronous tests). Join polling does not reset the owner's pacing budget.
The clock must be monotonic and non-yielding; both scheduler functions must work without throwing.
Pacing gives the scheduler opportunities to run; it does not enforce a hard frame-time limit.

## Telemetry tasks and loading UI

Each registration callback receives a `BootstrapTelemetryContext` with three methods:

- `createTask(name) -> BootstrapTelemetryTask`: create active work owned by this operation.
- `getReader() -> BootstrapTelemetryReader`: observe the lifecycle and active task collection.
- `checkpoint()`: cooperate with the runner's time budget.

The context is frozen. Its method fields are typed `read`, so callers can invoke them but cannot
replace them. This does not make the tasks created through the context read-only.

The host can also obtain `application:getTelemetryReader()` before calling `create`.
The context has no arbitrary metadata fields, snapshot setter, or combined change notification.

```luau
["wire" :: StartPhase] = function(graph, telemetryContext)
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

- `getName()`, `getPhase()`, `getOperationName()` for immutable identity. Phase and the operation
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
| `getPhase()` | Caller start/stop phase name, or lifecycle labels `idle`, `construct`, `validate`, `shutdown`, `destroy`, `ready`, `stopped`, `failed`. Use controller status to disambiguate a reused spelling. |
| `getName()` | Current registration label; nil for graph validation and terminal phases. |
| `getOperationState()` | `pending`, `running`, `completed`, `cancelled`, or `failed`. A callback skipped after a pacing yield reports `cancelled`. |
| `getOperationProgress()` | Finished-attempt/total callback counts, including constructors and validation. Shutdown counts critical callbacks plus eligible stop callbacks and final destructors; stopped/failed reset counts to zero. This is not a time estimate. |
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

Place the UI registration first. It subscribes through `telemetryContext:getReader()` during
construction; reverse final destruction keeps it alive through every stop phase and other owner cleanup.
The package owns no GUI, ReplicatedFirst behavior, or engine shutdown hook. The client/server entry
script connects those application-specific policies.

## Failure reporting and migration

A constructor, validation, or start exception stops later creation and automatically runs the critical
prefix, eligible stop phases, and final destructors. Cleanup exceptions include phase/name and
traceback; they are collected while remaining callbacks are attempted. The terminal error retains
the creation cause and all shutdown failures. Failed cleanup is never silently retried. Graph
references become invalid for live use once destruction begins; the consumer must coordinate its
other users of those objects.

The public types are `Bootstrap<G>`, `BootstrapOptions<StartPhase, StopPhase>`,
`BootstrapProfile<C, G, StartPhase, StopPhase>`, `BootstrapRegistration<C, G, StartPhase, StopPhase>`,
`BootstrapCallbacks<C, Phase>`, and `BootstrapShutdown<C>`. Existing telemetry context, reader, task,
and task-reader capabilities remain. `BootstrapStatus` is lifecycle state; `BootstrapPhase` is an
observational string because start/stop phase names belong to callers. `BootstrapOperationState`
includes `cancelled` for an operation skipped at its pacing boundary.

For the pending VMMO migration:

- Replace controller `start`/`deconstruct` with `create`/`destroy`; there are no compatibility aliases.
- Keep one registration `construct` callback. Move later initialization/wiring/activation into the
  `start` map. Split coordinated shutdown into the `stop` map and final resource release into `destroy`.
- Supply independent `StartPhase`/`StopPhase` types and explicit `startPhases`/`stopPhases` arrays.
  Individual callbacks are optional; both maps are required and may be empty.
- Validation automatically follows construction. There is no `validateAfter`, `prepare` map,
  registration `create` map, `createPhases`, or `destroyPhases` in this API.
- Audit partial-context handling in both stop and destroy, plus final reverse destruction order.
  Install critical shutdown callbacks on the profile before `new`, and bind the host shutdown hook
  after `new` but before `create`.
- Update status observers and phase-dependent loading UI. Catch cancellation from `create` and
  stored terminal failures from `destroy`, including repeated calls. Registration start/stop sections
  do not expose reversible lifecycle methods on the controller.

No consumer dependency, VMMO code, engine hook, or publication is changed by this package pass.

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
