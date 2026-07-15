# DataService API Reference

This reference documents the public DataService API. Server APIs appear before client APIs. Examples assume a shared configured module named `ReplicatedStorage.Data`.

## API conventions

### Execution and asynchronous labels

- **Synchronous:** completes in the current thread and does not intentionally yield.
- **Asynchronous (yields):** suspends the current thread until a result or timeout is available.
- **Event-driven:** registers a callback that runs later when DataService dispatches the signal.

### Configured module shape

DataService is configured once with a template:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataService = require(ReplicatedStorage.Packages.DataService)

local template = {
	Coins = 0,
	Inventory = {} :: { [string]: number },
	Items = {} :: { number },
}

return DataService({
	template = template,
	useMock = false,
	profileStoreIndex = "PlayerData",
})
```

The exported type is `ConfiguredData<T>`, but only the member for the current runtime is populated:

- On the server, use `require(ReplicatedStorage.Data).server`.
- On the client, use `require(ReplicatedStorage.Data).client`.

Calling the factory more than once in the same runtime throws an error.

## Shared types

### `Options<T>`

```luau
type Options<T> = {
	template: T,
	useMock: boolean?,
	profileStoreIndex: string?,
}
```

Parameters:

- `template: T` — default player-data structure and source of the generated API types.
- `useMock: boolean?` — when `true`, uses ProfileStore's mock store. Defaults to `false`.
- `profileStoreIndex: string?` — ProfileStore name. Defaults to `"Default"`.

Example:

```luau
local options: DataService.Options<typeof(template)> = {
	template = template,
	useMock = true,
	profileStoreIndex = "PlayerDataDev",
}
```

### `ConfiguredData<T>`

```luau
type ConfiguredData<T> = {
	server: Server<T>,
	client: Client<T>,
}
```

Fields:

- `server: Server<T>` — populated in a server runtime.
- `client: Client<T>` — populated in a client runtime.

Example:

```luau
local configured = require(ReplicatedStorage.Data)
local Data = if RunService:IsServer() then configured.server else configured.client
```

Prefer selecting the correct member in environment-specific scripts so Luau retains the precise API type.

### `PathKey`

```luau
type PathKey = string | number
```

A named table property uses a string key; an array item uses a number key.

### `SignalConnection`

```luau
type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
```

#### `SignalConnection:Disconnect()`

**Execution:** Synchronous.

Parameters: none.

Returns: `()`.

Example:

```luau
local connection = Data[player].Coins.Changed:Connect(function(newCoins, oldCoins)
	print(oldCoins, newCoins)
end)

connection:Disconnect()
```

### `ReadOnlySignal<T...>`

Public value signals are read-only. They expose `Connect`, `Once`, and `Wait`; they do not expose `Fire`.

#### `ReadOnlySignal:Connect(callback)`

**Execution:** Event-driven; registration itself is synchronous.

Parameters:

- `callback: (T...) -> ()` — function called with the signal's typed arguments each time it is dispatched.

Returns: `SignalConnection`.

Example:

```luau
local connection = Data[player].Coins.Changed:Connect(function(newCoins, oldCoins)
	print(`{oldCoins} -> {newCoins}`)
end)
```

#### `ReadOnlySignal:Once(callback)`

**Execution:** Event-driven; registration itself is synchronous.

Parameters:

- `callback: (T...) -> ()` — function called only for the next dispatch.

Returns: `SignalConnection`.

Example:

```luau
Data[player].Coins.Changed:Once(function(newCoins, oldCoins)
	print(`First observed change: {oldCoins} -> {newCoins}`)
end)
```

#### `ReadOnlySignal:Wait()`

**Execution:** Asynchronous (yields).

Parameters: none.

Returns: `T...`, the arguments from the next signal dispatch.

Example:

```luau
local index: number, item: number = Data[player].Items.OnInsert:Wait()
print(index, item)
```

### `ChangedSignal<T>`

```luau
type ChangedSignal<T> = ReadOnlySignal<T, T>
```

Signal arguments:

- `newValue: T` — value after the mutation.
- `oldValue: T` — value before the mutation.

Example:

```luau
Data[player].Coins.Changed:Connect(function(newValue: number, oldValue: number)
	print(oldValue, newValue)
end)
```

### `ArraySignal<Item>`

```luau
type ArraySignal<Item> = ReadOnlySignal<number, Item>
```

Signal arguments:

- `index: number` — affected array index.
- `item: Item` — inserted or removed item.

Example:

```luau
Data[player].Items.OnRemove:Connect(function(index: number, item: number)
	print(`Removed {item} from {index}`)
end)
```

### Generated value types

DataService generates wrapper types recursively from the configured template:

```luau
type ValueType<T> = -- writable server wrapper generated from T
type ReadOnlyValueType<T> = -- read-only client wrapper generated from T
```

Named fields are exposed as read-only properties. Dictionary and array keys produce typed child wrappers. Luau currently cannot represent separate read/write types for generated indexers, so direct index assignment may appear available to static analysis; the runtime wrapper still rejects it.

## DataService factory

### `DataService(options)`

```luau
DataService<T>(options: {
	template: T,
	useMock: boolean?,
	profileStoreIndex: string?,
}): ConfiguredData<T>
```

**Execution:** Server construction is synchronous. Client construction requests its initial snapshot and may yield while invoking the server.

Parameters:

- `options` — template and ProfileStore configuration. `T` is inferred directly from `template`; the other fields are type-checked at the call site.

Returns: `ConfiguredData<T>` with the current runtime's server or client view populated.

Example:

```luau
return DataService({
	template = template,
	useMock = false,
	profileStoreIndex = "PlayerData",
})
```

# Server API

Acquire the server API with:

```luau
local Data = require(ReplicatedStorage.Data).server
```

## Server signals

### `Data.PlayerInitialized`

```luau
PlayerInitialized: Signal<Player>
```

**Execution:** Event-driven.

Signal parameters:

- `player: Player` — player whose profile has loaded, reconciled, and been wrapped.

Returns from `Connect`: `SignalConnection`.

Example:

```luau
Data.PlayerInitialized:Connect(function(player)
	print(Data[player].Coins())
end)
```

### `Data.ProfileReleasing`

```luau
ProfileReleasing: Signal<Player, any>
```

**Execution:** Event-driven.

Signal parameters:

- `player: Player` — player whose profile is being released.
- `profile: any` — underlying ProfileStore profile. The runtime implementation carries `Profile<T>`, but the current public facade exports this argument as `any`.

Returns from `Connect`: `SignalConnection`.

Example:

```luau
Data.ProfileReleasing:Connect(function(player, profile)
	print(`Releasing profile for {player.Name}`, profile)
end)
```

This event fires before DataService clears its cached profile and value wrappers.

## Server profile methods

### `Data:HasProfile(player)`

```luau
Data:HasProfile(player: Player): boolean
```

**Execution:** Synchronous.

Parameters:

- `player: Player` — player to inspect.

Returns: `boolean`; `true` when DataService currently owns an initialized profile for the player.

Example:

```luau
if Data:HasProfile(player) then
	print(Data[player].Coins())
end
```

### `Data:WaitForProfile(player, timeout?)`

```luau
Data:WaitForProfile(player: Player, timeout: number?): any?
```

**Execution:** Asynchronous (may yield). Returns immediately if the profile is already initialized or the player has left.

Parameters:

- `player: Player` — player whose profile should be awaited.
- `timeout: number?` — maximum seconds to wait. Omit to wait until initialization, release failure, or player departure. Must not be negative.

Returns: `any?`; the underlying ProfileStore profile when initialization succeeds, otherwise `nil` after timeout, failure, or departure. The implementation retains `Profile<T>` internally, but the current exported `Server<T>` facade exposes this result as `any?`.

Example:

```luau
local profile = Data:WaitForProfile(player, 30)

if not profile then
	warn(`Profile was not ready for {player.Name}`)
	return
end

Data[player].Coins(100)
```

### `Data:GetData(player)`

```luau
Data:GetData(player: Player): T
```

**Execution:** Synchronous.

Parameters:

- `player: Player` — initialized player whose complete data should be read.

Returns: `T`, a deep copy of the player's current data.

Throws if the player does not have an initialized profile.

Example:

```luau
local snapshot = Data:GetData(player)
print(snapshot.Coins)
```

### `Data:WaitForData(player, timeout?)`

```luau
Data:WaitForData(player: Player, timeout: number?): T?
```

**Execution:** Asynchronous (may yield). Returns immediately if the player's data is already initialized or the player has left.

Parameters:

- `player: Player` — player whose data should be awaited.
- `timeout: number?` — maximum seconds to wait. Omit to wait until initialization, load failure, or player departure. Must not be negative.

Returns: `T?`; a deep copy of the player's current data when initialization succeeds, otherwise `nil` after timeout, failure, release, or departure.

Example:

```luau
local snapshot = Data:WaitForData(player, 30)

if not snapshot then
	warn(`Data was not ready for {player.Name}`)
	return
end

print(snapshot.Coins)
```

### `Data:GetRawProfile(player)`

```luau
Data:GetRawProfile(player: Player): any
```

**Execution:** Synchronous.

Parameters:

- `player: Player` — initialized player whose ProfileStore profile should be returned.

Returns: `any`, the live underlying ProfileStore profile. The implementation retains `Profile<T>` internally, but the current exported `Server<T>` facade exposes this result as `any`.

Throws if the player does not have an initialized profile. This is an advanced escape hatch; prefer value wrappers for ordinary reads and mutations.

Example:

```luau
local profile = Data:GetRawProfile(player)
print(profile:IsActive())
```

## Server value access

### `Data[player]`

```luau
Data[player: Player]: ValueType<T>
```

**Execution:** Synchronous.

Parameters:

- `player: Player` — initialized player whose root value wrapper should be returned.

Returns: `ValueType<T>`, a writable root wrapper generated from the configured template.

Throws if the player has no initialized profile.

Example:

```luau
local coins: number = Data[player].Coins()
```

### Root value call `Data[player]()`

```luau
Data[player](): T
```

**Execution:** Synchronous.

Parameters: none.

Returns: `T`, a deep copy of all current player data.

Example:

```luau
local snapshot = Data[player]()
print(snapshot.Settings.MusicVolume)
```

### Field getter `Data[player].Field()`

```luau
Data[player].Field(): FieldType
```

**Execution:** Synchronous.

Parameters: none.

Returns: `FieldType`, a copy of the current field value.

Example:

```luau
local coins: number = Data[player].Coins()
local volume: number = Data[player].Settings.MusicVolume()
local swords: number = Data[player].Inventory["Sword"]()
```

### Field setter `Data[player].Field(value, dontReplicate?)`

```luau
Data[player].Field(value: FieldType, dontReplicate: boolean?): FieldType
```

**Execution:** Synchronous.

Parameters:

- `value: FieldType` — replacement value. It must match the template field type.
- `dontReplicate: boolean?` — pass `true` to suppress this live mutation message; pass `false` or omit to replicate normally.

Returns: `FieldType`, the stored resulting value.

Example:

```luau
local newCoins: number = Data[player].Coins(200)

-- Save and fire server-side signals without sending this mutation live.
Data[player].Coins(250, true)
```

`dontReplicate` is not a permanent privacy filter. A future full snapshot includes the current stored value.

### Field updater `Data[player].Field(update, dontReplicate?)`

```luau
Data[player].Field(
	update: (current: FieldType) -> FieldType,
	dontReplicate: boolean?
): FieldType
```

**Execution:** Synchronous.

Parameters:

- `update: (current: FieldType) -> FieldType` — callback that receives the current value and returns its replacement.
- `dontReplicate: boolean?` — pass `true` to suppress this live mutation message; pass `false` or omit to replicate normally.

Returns: `FieldType`, the updated stored value.

Example:

```luau
local newCoins: number = Data[player].Coins(function(current)
	return current + 25
end)
```

### `Data[player].Field.Changed`

```luau
Changed: ChangedSignal<FieldType>
```

**Execution:** Event-driven.

Signal parameters:

- `newValue: FieldType` — value after the mutation.
- `oldValue: FieldType` — value before the mutation.

Returns from `Connect` or `Once`: `SignalConnection`. `Wait` returns `(FieldType, FieldType)`.

Example:

```luau
Data[player].Coins.Changed:Connect(function(newCoins, oldCoins)
	print(oldCoins, newCoins)
end)
```

## Server arrays

The following operations exist when the template field has a numeric indexer, such as `{} :: { number }`.

### `Data[player].Array.Insert(item, index?)`

```luau
Data[player].Array.Insert(item: Item, index: number?): Item
```

**Execution:** Synchronous.

Parameters:

- `item: Item` — item to insert.
- `index: number?` — insertion index. Omit to append to the array.

Returns: `Item`, the inserted stored item.

Example:

```luau
local appended: number = Data[player].Items.Insert(10)
local first: number = Data[player].Items.Insert(20, 1)
```

### `Data[player].Array.RemoveAt(index)`

```luau
Data[player].Array.RemoveAt(index: number): Item
```

**Execution:** Synchronous.

Parameters:

- `index: number` — index to remove.

Returns: `Item`, the removed item.

Example:

```luau
local removed: number = Data[player].Items.RemoveAt(1)
```

### `Data[player].Array.OnInsert`

```luau
OnInsert: ArraySignal<Item>
```

**Execution:** Event-driven.

Signal parameters:

- `index: number` — insertion index.
- `item: Item` — inserted item.

Returns from `Connect` or `Once`: `SignalConnection`. `Wait` returns `(number, Item)`.

Example:

```luau
Data[player].Items.OnInsert:Connect(function(index, item)
	print(`Inserted {item} at {index}`)
end)
```

### `Data[player].Array.OnRemove`

```luau
OnRemove: ArraySignal<Item>
```

**Execution:** Event-driven.

Signal parameters:

- `index: number` — former item index.
- `item: Item` — removed item.

Returns from `Connect` or `Once`: `SignalConnection`. `Wait` returns `(number, Item)`.

Example:

```luau
local index, removedItem = Data[player].Items.OnRemove:Wait()
print(index, removedItem)
```

# Client API

Acquire the client API with:

```luau
local Data = require(ReplicatedStorage.Data).client
```

Client value wrappers are read-only. They support getters and signals, but not setters, updater callbacks, `Insert`, or `RemoveAt`.

## Client methods

### `Data:IsReady()`

```luau
Data:IsReady(): boolean
```

**Execution:** Synchronous.

Parameters: none.

Returns: `boolean`; `true` after the initial snapshot has been installed.

Example:

```luau
if Data:IsReady() then
	print(Data.Coins())
end
```

The configured client currently requests its snapshot during construction, so requiring the shared module can yield before this API becomes available.

### `Data:GetData()`

```luau
Data:GetData(): T
```

**Execution:** Synchronous.

Parameters: none.

Returns: `T`, a deep copy of the complete replicated client data.

Throws if client data is not ready.

Example:

```luau
local snapshot = Data:GetData()
print(snapshot.Coins)
```

### `Data:WaitForData(timeout?)`

```luau
Data:WaitForData(timeout: number?): T?
```

**Execution:** Asynchronous (may yield). Waits until the original server snapshot has been installed.

Parameters:

- `timeout: number?` — maximum seconds to wait. Omit to wait indefinitely. Must not be negative.

Returns: `T?`; a deep copy of the replicated data after the original snapshot is ready, otherwise `nil` after the timeout.

Example:

```luau
local snapshot = Data:WaitForData(30)

if not snapshot then
	warn("Initial data snapshot was not ready")
	return
end

print(snapshot.Coins)
```

## Client value access

### Root value call `Data()`

```luau
Data(): T
```

**Execution:** Synchronous.

Parameters: none.

Returns: `T`, a deep copy of all replicated client data.

Throws if client data is not ready.

Example:

```luau
local snapshot = Data()
print(snapshot.Settings.MusicVolume)
```

### Field getter `Data.Field()`

```luau
Data.Field(): FieldType
```

**Execution:** Synchronous.

Parameters: none.

Returns: `FieldType`, a copy of the current replicated field value.

Example:

```luau
local coins: number = Data.Coins()
local volume: number = Data.Settings.MusicVolume()
local swords: number = Data.Inventory["Sword"]()
local firstItem: number = Data.Items[1]()
```

### `Data.Field.Changed`

```luau
Changed: ChangedSignal<FieldType>
```

**Execution:** Event-driven.

Signal parameters:

- `newValue: FieldType` — replicated value after the mutation.
- `oldValue: FieldType` — replicated value before the mutation.

Returns from `Connect` or `Once`: `SignalConnection`. `Wait` returns `(FieldType, FieldType)`.

Example:

```luau
Data.Coins.Changed:Once(function(newCoins, oldCoins)
	print(oldCoins, newCoins)
end)
```

## Client arrays

Client arrays can be read as complete arrays or through their numeric child wrappers. They expose insertion/removal signals but no mutation operations.

### `Data.Array()`

```luau
Data.Array(): { Item }
```

**Execution:** Synchronous.

Parameters: none.

Returns: `{ Item }`, a copy of the complete replicated array.

Example:

```luau
local items: { number } = Data.Items()
```

### `Data.Array[index]()`

```luau
Data.Array[index: number](): Item
```

**Execution:** Synchronous.

Parameters:

- `index: number` — array index to read.

Returns: `Item`, a copy of the item at the selected index.

Example:

```luau
local firstItem: number = Data.Items[1]()
```

### `Data.Array.OnInsert`

```luau
OnInsert: ArraySignal<Item>
```

**Execution:** Event-driven.

Signal parameters:

- `index: number` — replicated insertion index.
- `item: Item` — replicated inserted item.

Returns from `Connect` or `Once`: `SignalConnection`. `Wait` returns `(number, Item)`.

Example:

```luau
Data.Items.OnInsert:Connect(function(index, item)
	print(`Received {item} at {index}`)
end)
```

### `Data.Array.OnRemove`

```luau
OnRemove: ArraySignal<Item>
```

**Execution:** Event-driven.

Signal parameters:

- `index: number` — replicated removal index.
- `item: Item` — replicated removed item.

Returns from `Connect` or `Once`: `SignalConnection`. `Wait` returns `(number, Item)`.

Example:

```luau
Data.Items.OnRemove:Connect(function(index, item)
	print(`Removed {item} from {index}`)
end)
```

## Client replication behavior

The client receives an initial full snapshot followed by revisioned mutations. Out-of-order mutations are queued. If a revision gap remains, DataService requests a fresh snapshot.

A server mutation made with `dontReplicate = true` does not send a live mutation message and does not advance the public replication revision. A later snapshot can still expose the server's current stored value. Skipping structural or array-related state and later replicating dependent mutations can leave the client inconsistent until it receives a fresh snapshot.

## Runtime errors and restrictions

- Accessing a server wrapper before profile initialization throws `Player does not have a profile`.
- Accessing client fields before snapshot readiness throws `Client data is not ready`.
- Calling a client field with an argument is rejected by its generated type and by the runtime read-only guard.
- Assigning directly to a field wrapper throws. Call the wrapper to mutate server data.
- Public value signals do not expose `Fire`; only DataService dispatches them.
- Invalid array indexes and mismatched value types are rejected by the underlying data guards or Luau types.

For setup-oriented examples, see [Getting Started](GETTINGSTARTED.md).
