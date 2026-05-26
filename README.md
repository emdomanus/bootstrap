# Bootstrap

Small lifecycle bootstrap helpers for Roblox projects.

## Install

```toml
[dependencies]
bootstrap = { name = "emdomanus/bootstrap", version = "^0.1.0" }
```

## Usage

```luau
local Bootstrap = require(ReplicatedStorage.packages.roblox_packages.bootstrap)

local api = Bootstrap.bootstrapify(sharedService, serverService, clientService, {
	"initialize",
	"start",
})

Bootstrap.bootstrap({ ReplicatedStorage.shared.services }, {
	"initialize",
	"start",
})
```

`ReplicatedFirst` code should keep a tiny local bootstrap copy if it needs to run before packages are available.
