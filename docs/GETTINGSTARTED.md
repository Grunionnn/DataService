# Getting Started with DataService

## Introduction

DataService is a type-safe player-data wrapper for Roblox. It stores data through ProfileStore, exposes each field as a callable value, and automatically replicates server mutations to a read-only client copy.

This guide uses one shared `Data` ModuleScript to configure the package. Requiring that module returns the server API on the server and the client API on the client while preserving the template's Luau types.

DataService requires Luau's new type solver because its nested value types are generated from your template.

## Installation

Add DataService to your `wally.toml`:

```toml
[dependencies]
DataService = "grunionnn/dataservice@version"
```

Install the dependencies:

```sh
wally install
```

Make sure your Rojo project maps regular Wally packages into `ReplicatedStorage.Packages` and server dependencies into `ServerScriptService.ServerPackages`. DataService requires Networker and GoodSignal as shared dependencies and ProfileStore as a server dependency.

## Folder Structure

A small project can use this layout:

```text
ReplicatedStorage
├── Data                   Shared configuration ModuleScript
└── Packages
    ├── DataService
    ├── GoodSignal
    └── Networker

ServerScriptService
├── ServerPackages
│   └── ProfileStore
└── DataExample.server.lua

StarterPlayer
└── StarterPlayerScripts
    └── DataExample.client.lua
```

The exact package names depend on the aliases in your `wally.toml`. The important part is that the configured `Data` module is visible to both server and client, while ProfileStore remains server-only.

## Creating your template

Create a ModuleScript named `Data` in `ReplicatedStorage`. Define every persistent field and its default value in the template:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.Packages.DataService)

local template = {
	Coins = 0,
	HasPlayed = false,
	Inventory = {} :: { [string]: number },
	Items = {} :: { number },
	Settings = {
		MusicVolume = 0.5,
		SFXVolume = 0.5,
	},
}

return DataService({
	template = template,
	useMock = false,
	profileStoreIndex = "PlayerData",
})
```

Annotate empty dictionaries and arrays. Without an annotation, an empty table does not contain enough information for Luau to infer its key and item types.

DataService may only be configured once in each game runtime, so other scripts should require this shared module instead of calling `DataService(...)` again.

## Initializing the server

Require the shared module and select its `server` member:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(ReplicatedStorage.Data).server

Data.PlayerInitialized:Connect(function(player)
	print(`Data is ready for {player.Name}`)
	print(Data[player].Coins())
end)
```

DataService automatically starts and releases player profile sessions. Do not index `Data[player]` until the profile has initialized.

If a particular workflow begins before initialization, wait for the profile:

```luau
local profile = Data:WaitForProfile(player, 30)

if not profile then
	return
end

local coins = Data[player].Coins()
```

You can also use `Data:HasProfile(player)`, `Data:GetData(player)`, or `Data:GetRawProfile(player)` when the lower-level result is appropriate.

## Connecting the client

Require the same shared module from a LocalScript and select its `client` member:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(ReplicatedStorage.Data).client

local coins: number = Data.Coins()
print(`Replicated coins: {coins}`)
```

Creating the client requests an initial snapshot from the server. Client wrappers are read-only: clients can read fields and subscribe to signals, but they cannot set values or call array mutation operations.

`Data:IsReady()` reports whether the initial snapshot has been installed, `Data:WaitForData(timeout?)` waits for and returns a copy of that snapshot, and `Data:GetData()` immediately returns a copy of the complete replicated data table.

## Getting a value

Call a value wrapper with no arguments:

```luau
local coins: number = Data[player].Coins()
local volume: number = Data[player].Settings.MusicVolume()
local swordCount: number = Data[player].Inventory["Sword"]()
local allData = Data:GetData(player)
```

On the client, omit the player index:

```luau
local coins: number = Data.Coins()
local volume: number = Data.Settings.MusicVolume()
local swordCount: number = Data.Inventory["Sword"]()
local allData = Data:GetData()
```

Returned tables are copied so callers cannot bypass DataService by mutating the stored table directly.

## Setting a value

On the server, call a field with its new value:

```luau
Data[player].Coins(200)
Data[player].Settings.MusicVolume(0.75)
Data[player].Inventory["Sword"](1)
```

The call returns the resulting value:

```luau
local newCoins: number = Data[player].Coins(200)
```

To save a mutation without sending that live mutation to the client, pass `true` as the second argument:

```luau
Data[player].Coins(200, true)
```

Pass `false` or omit the argument to replicate normally. This is not a permanent privacy filter: a later full snapshot contains the server's current stored data.

Never assign directly to a wrapper:

```luau
-- Wrong
Data[player].Coins = 200

-- Correct
Data[player].Coins(200)
```

## Updating a value

Pass a callback when the new value depends on the current value:

```luau
local newCoins: number = Data[player].Coins(function(current)
	return current + 25
end)
```

The callback receives the correctly inferred field type and must return the same type. Updates also support replication suppression:

```luau
Data[player].Coins(function(current)
	return current + 25
end, true)
```

Updates are server-only because the client API is read-only.

## Arrays

Annotate an empty array in the template:

```luau
local template = {
	Items = {} :: { number },
}
```

Insert an item on the server:

```luau
local insertedItem: number = Data[player].Items.Insert(10)
local insertedAtStart: number = Data[player].Items.Insert(20, 1)
```

Remove an item by index:

```luau
local removedItem: number = Data[player].Items.RemoveAt(1)
```

Read the complete array or a wrapped item:

```luau
local items: { number } = Data[player].Items()
local firstItem: number = Data[player].Items[1]()
```

`Insert` and `RemoveAt` are not exposed by client array wrappers. Per-mutation `dontReplicate` is currently supported by field set/update calls, not by array operations.

## Signals

Every non-root field exposes `Changed`. Array fields additionally expose `OnInsert` and `OnRemove`:

```luau
Data[player].Coins.Changed:Connect(function(newCoins, oldCoins)
	print(`Coins changed from {oldCoins} to {newCoins}`)
end)

Data[player].Items.OnInsert:Connect(function(index, item)
	print(`Inserted {item} at {index}`)
end)

Data[player].Items.OnRemove:Connect(function(index, item)
	print(`Removed {item} from {index}`)
end)
```

Signals expose `Connect`, `Once`, and `Wait`:

```luau
Data[player].Coins.Changed:Once(function(newCoins, oldCoins)
	print(newCoins, oldCoins)
end)

local index, item = Data[player].Items.OnInsert:Wait()
```

They intentionally do not expose `Fire`; DataService owns signal dispatch. The same read-only signal API is available on the client.

## Mock Mode

Set `useMock` to `true` while developing locally:

```luau
return DataService({
	template = template,
	useMock = true,
	profileStoreIndex = "PlayerData",
})
```

Mock mode uses ProfileStore's mock store instead of the live data store. Keep the option controlled from a server-safe development configuration and set it to `false` before testing production persistence.

## Common mistakes

- Creating DataService more than once instead of sharing one configured module.
- Accessing `Data[player]` before `PlayerInitialized` or `WaitForProfile` completes.
- Trying to set data from the client. Client wrappers are read-only by design.
- Assigning with `Data[player].Coins = 10` instead of calling `Data[player].Coins(10)`.
- Leaving an empty dictionary or array untyped in the template.
- Treating `dontReplicate` as secure private storage. Future snapshots still include the stored value.
- Suppressing a structural mutation and then sending dependent mutations. The client may not have the state needed to apply them correctly.
- Calling `Fire` on a public signal. Use `Connect`, `Once`, or `Wait`; DataService fires signals internally.
- Expecting direct dictionary or array index assignment to work. Generated indexers must currently appear writable because of a Luau limitation, but the runtime wrapper rejects direct assignment.

## Next steps

- Read the project [README](../README.md) for the feature summary, current version, and known limitations.
- Use the complete [API Reference](API.md) for method signatures, parameters, return values, and execution behavior.
- Define a production template with explicit dictionary and array annotations.
- Start in mock mode and test profile initialization, server mutations, client replication, and signal callbacks.
- Switch mock mode off only when you are ready to test persistent data stores.
