--!strict
-->> Dependencies

local Types = require(script.Parent.Types)
local Utils = require(script.Parent.Utils)
local GoodSignal = require(script.Parent.Parent.goodsignal)

-->> Class

local Data = {}
Data.__index = Data

-->> Types

export type SetMutation = {
	Operation: "Set" | "Update",
	Path: { Types.PathKey },
	Value: any,
	PreviousValue: any?,
}

export type ArrayInsertMutation = {
	Operation: "ArrayInsert",
	Path: { Types.PathKey },
	Value: any,
	Index: number,
}

export type ArrayRemoveMutation = {
	Operation: "ArrayRemoveAt",
	Path: { Types.PathKey },
	PreviousValue: any,
	Index: number,
}

export type Mutation = SetMutation | ArrayInsertMutation | ArrayRemoveMutation

export type Data<T> = typeof(setmetatable(
	{} :: {
		_data: T,
		_destroyed: boolean,
		_signals: {
			changed: { [string]: Types.MutableChangedSignal<any> },
			arrayInserted: { [string]: Types.MutableArraySignal<any> },
			arrayRemoved: { [string]: Types.MutableArraySignal<any> },
		},
	},
	Data
))

-->> Constructor

function Data.new<T>(data: T): Data<T>
	assert(typeof(data) == "table", "Data must be a table")

	local self = setmetatable({
		_data = data,
		_destroyed = false,
		_signals = {
			changed = {} :: { [string]: Types.MutableChangedSignal<any> },
			arrayInserted = {} :: { [string]: Types.MutableArraySignal<any> },
			arrayRemoved = {} :: { [string]: Types.MutableArraySignal<any> },
		},
	}, Data) :: Data<T>

	return self
end

-->> Internal lifecycle

function Data._assertAlive(self: Data<any>)
	assert(not self._destroyed, "Data has been destroyed")
end

function Data._destroy(self: Data<any>)
	self:_assertAlive()

	for _, signalHolder in self._signals do
		for _, signal in signalHolder do
			(signal :: any):DisconnectAll()
		end
	end

	self._destroyed = true
	self._data = nil :: any
	self._signals = nil :: any
end

-->> Internal signals

--// Creation

function Data._getChangedSignal(self: Data<any>, path: Types.Path): Types.MutableChangedSignal<any>
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local pathString = Utils.PathToString(normalizedPath)
	local signal = self._signals.changed[pathString]

	if not signal then
		signal = GoodSignal.new()
		self._signals.changed[pathString] = signal
	end

	return signal
end

function Data._getArrayInsertedSignal(self: Data<any>, path: Types.Path): Types.MutableArraySignal<any>
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local pathString = Utils.PathToString(normalizedPath)
	local signal = self._signals.arrayInserted[pathString]

	if not signal then
		signal = GoodSignal.new()
		self._signals.arrayInserted[pathString] = signal
	end

	return signal
end

function Data._getArrayRemovedSignal(self: Data<any>, path: Types.Path): Types.MutableArraySignal<any>
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local pathString = Utils.PathToString(normalizedPath)
	local signal = self._signals.arrayRemoved[pathString]

	if not signal then
		signal = GoodSignal.new()
		self._signals.arrayRemoved[pathString] = signal
	end

	return signal
end

--// Dispatch

function Data._fireChangedSignal(self: Data<any>, path: Types.Path, newValue: any, oldValue: any)
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local pathString = Utils.PathToString(normalizedPath)
	local signal = self._signals.changed[pathString]

	if signal then
		signal:Fire(newValue, oldValue)
	end
end

function Data._fireArrayInsertedSignal(self: Data<any>, path: Types.Path, index: number, value: any)
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local pathString = Utils.PathToString(normalizedPath)
	local signal = self._signals.arrayInserted[pathString]

	if signal then
		signal:Fire(index, value)
	end
end

function Data._fireArrayRemovedSignal(self: Data<any>, path: Types.Path, index: number, value: any)
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local pathString = Utils.PathToString(normalizedPath)
	local signal = self._signals.arrayRemoved[pathString]

	if signal then
		signal:Fire(index, value)
	end
end

-->> Reads

function Data.Get(self: Data<any>, path: Types.Path): any
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local parent, key = Utils.ResolveParent(self._data, normalizedPath)

	return Utils.DeepCopy(parent[key])
end

function Data.GetData<T>(self: Data<T>): T
	self:_assertAlive()
	return Utils.DeepCopy(self._data)
end

-->> Public signals

function Data.GetChangedSignal(self: Data<any>, path: Types.Path): Types.ChangedSignal<any>
	return self:_getChangedSignal(path)
end

function Data.GetArrayInsertedSignal(self: Data<any>, path: Types.Path): Types.ArraySignal<any>
	return self:_getArrayInsertedSignal(path)
end

function Data.GetArrayRemovedSignal(self: Data<any>, path: Types.Path): Types.ArraySignal<any>
	return self:_getArrayRemovedSignal(path)
end

-->> Mutations

function Data.Set(self: Data<any>, path: Types.Path, value: any): SetMutation
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local parent, key = Utils.ResolveParent(self._data, normalizedPath)
	local previousValue = Utils.DeepCopy(parent[key])
	local storedValue = Utils.DeepCopy(value)

	parent[key] = storedValue

	local mutation: SetMutation = {
		Operation = "Set",
		Path = normalizedPath,
		Value = Utils.DeepCopy(storedValue),
		PreviousValue = previousValue,
	}

	self:_fireChangedSignal(normalizedPath, Utils.DeepCopy(storedValue), Utils.DeepCopy(previousValue))

	return mutation
end

function Data.Update(self: Data<any>, path: Types.Path, callback: (currentValue: any) -> any): SetMutation
	self:_assertAlive()

	local currentValue = self:Get(path)
	local newValue = callback(currentValue)
	local mutation = self:Set(path, newValue)

	mutation.Operation = "Update"
	return mutation
end

function Data.ArrayInsert(self: Data<any>, path: Types.Path, value: any, index: number?): ArrayInsertMutation
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local parent, key = Utils.ResolveParent(self._data, normalizedPath)
	local array = parent[key]

	assert(Utils.IsArray(array), "Value at path is not an array")

	local previousArray = Utils.DeepCopy(array)
	local insertedValue = Utils.DeepCopy(value)
	local insertionIndex = index or (#array + 1)

	assert(insertionIndex >= 1 and insertionIndex <= #array + 1, "Array insertion index is out of bounds")

	table.insert(array, insertionIndex, insertedValue)

	local mutation: ArrayInsertMutation = {
		Operation = "ArrayInsert",
		Path = normalizedPath,
		Index = insertionIndex,
		Value = Utils.DeepCopy(insertedValue),
	}

	self:_fireArrayInsertedSignal(normalizedPath, insertionIndex, Utils.DeepCopy(insertedValue))
	self:_fireChangedSignal(normalizedPath, Utils.DeepCopy(array), previousArray)

	return mutation
end

function Data.ArrayRemoveAt(self: Data<any>, path: Types.Path, index: number): ArrayRemoveMutation
	self:_assertAlive()

	local normalizedPath = Utils.NormalizePath(path)
	local parent, key = Utils.ResolveParent(self._data, normalizedPath)
	local array = parent[key]

	assert(Utils.IsArray(array), "Value at path is not an array")
	assert(index >= 1 and index <= #array, "Array removal index is out of bounds")

	local previousArray = Utils.DeepCopy(array)
	local removedValue = table.remove(array, index)

	local mutation: ArrayRemoveMutation = {
		Operation = "ArrayRemoveAt",
		Path = normalizedPath,
		Index = index,
		PreviousValue = Utils.DeepCopy(removedValue),
	}

	self:_fireArrayRemovedSignal(normalizedPath, index, Utils.DeepCopy(removedValue))
	self:_fireChangedSignal(normalizedPath, Utils.DeepCopy(array), previousArray)

	return mutation
end

-->> Replication application

function Data.ApplyMutation(self: Data<any>, mutation: Mutation)
	self:_assertAlive()
	assert(type(mutation) == "table", "Mutation must be a table")
	assert(type(mutation.Path) == "table" and #mutation.Path > 0, "Mutation has an invalid path")

	if mutation.Operation == "Set" or mutation.Operation == "Update" then
		self:Set(mutation.Path, mutation.Value)
	elseif mutation.Operation == "ArrayInsert" then
		assert(type(mutation.Index) == "number" and mutation.Index % 1 == 0, "ArrayInsert mutation has an invalid index")
		self:ArrayInsert(mutation.Path, mutation.Value, mutation.Index)
	elseif mutation.Operation == "ArrayRemoveAt" then
		assert(type(mutation.Index) == "number" and mutation.Index % 1 == 0, "ArrayRemoveAt mutation has an invalid index")
		self:ArrayRemoveAt(mutation.Path, mutation.Index)
	else
		error(`Unknown mutation operation: {(mutation :: any).Operation}`)
	end
end

function Data.ReplaceData<T>(self: Data<T>, data: T)
	self:_assertAlive()
	assert(type(data) == "table", "Replacement data must be a table")

	self._data = Utils.DeepCopy(data)
end

-->> Cleanup

function Data.Destroy(self: Data<any>)
	self:_destroy()
end

-->> Return

return Data
