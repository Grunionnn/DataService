# DataService

DataService is a type-safe Roblox data-store wrapper with automatic client replication, nested value wrappers, signals, arrays, and mock-store support.

## Features

- Strongly typed server and client APIs using Luau's new type solver
- ProfileStore-backed player data with optional mock stores
- Automatic snapshots and mutation replication
- Callable values for reading, setting, and updating data
- Typed nested tables, dictionaries, and arrays
- Typed `Changed`, `OnInsert`, and `OnRemove` signals
- Array `Insert` and `RemoveAt` operations
- Per-mutation replication suppression on writable values
- Runtime protection against direct field assignment

## Installation

Add DataService to your `wally.toml` dependencies:

```toml
[dependencies]
DataService = "grunionnn/dataservice@version"
```

Then install the package:

```sh
wally install
```

DataService expects its server dependencies to be available through the Rojo project. Its current Wally dependencies are Networker, GoodSignal, and ProfileStore.

## Quick Example

Create and return one configured DataService module shared by the server and client:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.Packages.DataService)

local template = {
	Coins = 0,
	Inventory = {} :: { [string]: number },
	Items = {} :: { number },
	Settings = {
		MusicVolume = 0.5,
	},
}

return DataService({
	template = template,
	useMock = false,
	profileStoreIndex = "PlayerData",
})
```

Use the configured service on the server:

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(ReplicatedStorage.Data).server

Data.PlayerInitialized:Connect(function(player)
	local coins = Data[player].Coins()
	Data[player].Coins(coins + 10)

	Data[player].Coins(function(current)
		return current + 1
	end)

	Data[player].Inventory["Sword"](1)
	Data[player].Items.Insert(25)

	Data[player].Coins.Changed:Connect(function(newCoins, oldCoins)
		print(player, oldCoins, newCoins)
	end)
end)

Players.PlayerAdded:Connect(function(player)
	Data:WaitForProfile(player)
end)
```

Pass `true` as the second argument to suppress replication for one set or update:

```luau
Data[player].Coins(200, true)

Data[player].Coins(function(current)
	return current + 1
end, true)
```

The mutation is still saved and server-side signals still fire. Pass `false` or omit the second argument to replicate normally.

Read replicated data on the client:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(ReplicatedStorage.Data).client

local coins: number = Data.Coins()

Data.Coins.Changed:Connect(function(newCoins, oldCoins)
	print(oldCoins, newCoins)
end)

local index, item = Data.Items.OnInsert:Wait()
print(index, item)
```

Public value signals expose `Connect`, `Once`, and `Wait`. Signal dispatch remains internal to DataService.

## Links

- [Getting Started](docs/GETTINGSTARTED.md)
- [API Reference](docs/API.md)
- [Wally package registry](https://wally.run/)
- [Wally index](https://github.com/UpliftGames/wally-index)
- [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore)
- [Rojo](https://rojo.space/)

## Current Version

The current package version is `1.0.0`.

## Limitations

- DataService requires Luau's new type solver and user-defined type-function support.
- Only one configured DataService instance may be created in a game runtime.
- Data is currently scoped around player profiles.
- Client value wrappers are read-only.
- Luau does not currently support separate read/write indexer types for generated tables. Dictionary and array indexers therefore use a read/write type-system indexer, while direct assignment is rejected at runtime by the value wrapper.
- `dontReplicate` suppresses only the selected live mutation. A later full snapshot contains the server's current stored data, so it is not a permanent privacy filter.
- Skipping an array or structural mutation can leave the current client state unsuitable for later dependent mutations until a fresh snapshot is received.

## License

DataService is available under the MIT License.
