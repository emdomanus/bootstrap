# Bootstrap repository guide

- Apply VoxelMMO's `voxel-mmo-conventions` and `vmmo-tests` skills. This repository owns its commands
  and analyzer baseline; do not run the game's migration gates here.
- `src/init.luau` is the package entry, making the package root a ModuleScript. Implementation and mirrored types use
  `src/bootstrap/<category>/<owner>/shared/...`. Keep the runner independent of Roblox services.
- Profiles own typed composition and service selection. Do not add reflective service discovery,
  string-keyed resolution, implicit Promise awaiting, or game-specific readiness exceptions.
- Profile construction stays inert until `start`; errors stop subsequent phases and entered deconstructors all run.
- Preserve single-use lifecycle, phase barriers, reverse cleanup, and the identity of the validated graph.
- Registrations require semantic `name`, `construct`, and `deconstruct`; `init`, `wire`, and `start` are optional.
  Do not add field-name metadata. Construction assigns the typed partial graph; validation returns its complete view.
- Keep implementation requires inside construct callbacks. Bootstrap owns telemetry and automatic pacing;
  profile callbacks can checkpoint long work. Keep observers synchronous and isolate their failures.
- Use the pinned Rokit tools through `scripts/verify`, `scripts/lint`, and `scripts/build`.
- The editor and guarded analyzer use Luau's new solver. Keep `LuauSolverV2` enabled for acceptance;
  frozen contracts should declare read-only fields rather than erase readonly typing with casts.
- Run behavior tests, public positive/negative typing, full positive analysis, formatting, lint,
  and Rojo build for changes to the public lifecycle. Keep definitions fixed for analyzer comparisons.
- Lune executes source in memory. Do not create unowned temporary runtime trees.
- The editor and analyzer use `examples-sourcemap.json` from `verification.project.json` so examples
  and type fixtures resolve against the package. Keep it separate from the package-only sourcemap.
- Keep examples outside the shipped `src` tree. Their collaborators must use explicit capability
  injection and canonical type ownership too.
- No consumer migration, dependency installation, commit, or publication without user authorization.
- If a gate cannot provide a usable answer after three attempts, stop and report the evidence.
