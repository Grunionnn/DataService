--!strict
-->> Dependencies

local Data = require(script.Parent.Data)
local Types = require(script.Parent.Types)

local Value = {}
local ValueMethods = {}

-->> Types

type MutationCallback = (mutation: Data.Mutation, dontReplicate: boolean?) -> ()

type WritableInput<T> = T | ((current: T) -> T)

type WritableValueBase<T> = (value: WritableInput<T>?, dontReplicate: boolean?) -> T

type ReadOnlyValueBase<T> = () -> T

type RootValueBase<T> = ReadOnlyValueBase<T>

type ReadOnlyChildBase<T> = ReadOnlyValueBase<T> & {
	read Changed: Types.ChangedSignal<T>,
}

type WritableChildBase<T> = WritableValueBase<T> & {
	read Changed: Types.ChangedSignal<T>,
}

type ReadOnlyArrayBase<T, Item> = ReadOnlyChildBase<T> & {
	read OnInsert: Types.ArraySignal<Item>,
	read OnRemove: Types.ArraySignal<Item>,
}

type WritableArrayBase<T, Item> = WritableChildBase<T> & {
	read Insert: (item: Item, index: number?) -> Item,
	read RemoveAt: (index: number) -> Item,
	read OnInsert: Types.ArraySignal<Item>,
	read OnRemove: Types.ArraySignal<Item>,
}

export type RuntimeValue = typeof(setmetatable(
	{} :: {
		_data: Data.Data<any>,
		_path: { Types.PathKey },
		_children: { [Types.PathKey]: RuntimeValue },
		_onMutation: MutationCallback?,
		_destroyed: boolean,
		_readOnly: boolean,
	},
	Value
))

-- Generic type aliases are available as functions inside a user-defined type function.
-- selene: allow(undefined_variable)
type function BuildValueType(dataType, writableType)
	local writable = writableType:value()

	local function build(currentType, isRoot)
		local base = if isRoot
			then RootValueBase(currentType)
			elseif writable then WritableChildBase(currentType)
			else ReadOnlyChildBase(currentType)

		if not currentType:is("table") then
			return base
		end

		local children = types.newtable()

		for propertyKey, property in currentType:properties() do
			local childType = property.read or property.write

			if childType then
				children:setreadproperty(propertyKey, build(childType, false))
			end
		end

		local indexer = currentType:indexer()

		if indexer then
			local itemType = indexer.readresult or indexer.writeresult

			if itemType then
				-- Luau does not yet support separate read/write types for indexers.
				-- Runtime direct-assignment protection is enforced by Value.__newindex.
				children:setindexer(indexer.index, build(itemType, false))

				if not isRoot and indexer.index:is("number") then
					base = if writable
						then WritableArrayBase(currentType, itemType)
						else ReadOnlyArrayBase(currentType, itemType)
				end
			end
		end

		return types.intersectionof(base, children)
	end

	return build(dataType, true)
end

export type ValueType<T> = BuildValueType<T, true>
export type ReadOnlyValueType<T> = BuildValueType<T, false>

-->> Constructor

function Value.new<T>(dataObject: Data.Data<T>, path: { Types.PathKey }, mutationCallback: MutationCallback?, readOnly: boolean?): RuntimeValue
	local self = setmetatable({
		_data = dataObject,
		_path = table.clone(path),
		_children = {} :: { [Types.PathKey]: RuntimeValue },
		_onMutation = mutationCallback,
		_destroyed = false,
		_readOnly = readOnly == true,
	}, Value) :: RuntimeValue

	return self
end

-->> Guards

function ValueMethods._assertAlive(self: RuntimeValue)
	assert(not self._destroyed, "Value has been destroyed")
	self._data:_assertAlive()
end

function ValueMethods._assertHasPath(self: RuntimeValue)
	ValueMethods._assertAlive(self)
	assert(#self._path > 0, "Operation cannot be used on the root data value")
end

function ValueMethods._assertWritable(self: RuntimeValue)
	ValueMethods._assertAlive(self)
	assert(not self._readOnly, "Value is read-only")
end

-->> Internal helpers

function ValueMethods._getChild(self: RuntimeValue, key: Types.PathKey): RuntimeValue
	ValueMethods._assertAlive(self)

	local cachedChild = self._children[key]
	if cachedChild then
		return cachedChild
	end

	local childPath = table.clone(self._path)
	table.insert(childPath, key)

	local child = Value.new(self._data, childPath, self._onMutation, self._readOnly)
	self._children[key] = child

	return child
end

function ValueMethods._reportMutation(self: RuntimeValue, mutation: Data.Mutation, dontReplicate: boolean?): Data.Mutation
	ValueMethods._assertAlive(self)

	if self._onMutation then
		self._onMutation(mutation, dontReplicate)
	end

	return mutation
end

-->> Callable get, set, and update behavior

function ValueMethods._call(self: RuntimeValue, ...)
	ValueMethods._assertAlive(self)

	local argumentCount = select("#", ...)
	assert(argumentCount <= 2, "Value accepts at most two arguments")

	if argumentCount == 0 then
		if #self._path == 0 then
			return self._data:GetData()
		end

		return self._data:Get(self._path)
	end

	ValueMethods._assertWritable(self)
	ValueMethods._assertHasPath(self)

	local input = select(1, ...)
	local dontReplicate = select(2, ...)
	assert(dontReplicate == nil or type(dontReplicate) == "boolean", "dontReplicate must be a boolean")
	local mutation: Data.Mutation

	if type(input) == "function" then
		mutation = self._data:Update(self._path, input)
	else
		mutation = self._data:Set(self._path, input)
	end

	ValueMethods._reportMutation(self, mutation, dontReplicate)

	return mutation.Value
end

-->> Signal accessors

function ValueMethods._changed(self: RuntimeValue): Types.ChangedSignal<any>
	ValueMethods._assertHasPath(self)
	return self._data:GetChangedSignal(self._path)
end

function ValueMethods._onInsert(self: RuntimeValue): Types.ArraySignal<any>
	ValueMethods._assertHasPath(self)
	return self._data:GetArrayInsertedSignal(self._path)
end

function ValueMethods._onRemove(self: RuntimeValue): Types.ArraySignal<any>
	ValueMethods._assertHasPath(self)
	return self._data:GetArrayRemovedSignal(self._path)
end

-->> Array mutations

function ValueMethods._arrayInsert(self: RuntimeValue, item: any, index: number?): any
	ValueMethods._assertHasPath(self)

	ValueMethods._assertWritable(self)

	local mutation = self._data:ArrayInsert(self._path, item, index)
	return ValueMethods._reportMutation(self, mutation).Value
end

function ValueMethods._arrayRemoveAt(self: RuntimeValue, index: number): any
	ValueMethods._assertHasPath(self)
	ValueMethods._assertWritable(self)
	local mutation = self._data:ArrayRemoveAt(self._path, index)
	return ValueMethods._reportMutation(self, mutation).PreviousValue
end

-->> Cleanup

function ValueMethods._destroy(self: RuntimeValue)
	ValueMethods._assertAlive(self)

	for _, cachedChild in self._children do
		ValueMethods._destroy(cachedChild)
	end

	table.clear(self._children)
	self._destroyed = true
	self._data = nil :: any
	self._onMutation = nil
end

local ValueProperties = {
	Changed = ValueMethods._changed,
	OnInsert = ValueMethods._onInsert,
	OnRemove = ValueMethods._onRemove,
}

local InternalValueKeys: { [Types.PathKey]: boolean } = {
	_data = true,
	_path = true,
	_children = true,
	_onMutation = true,
	_destroyed = true,
	_readOnly = true,
}

local ValueOperations = {
	Insert = ValueMethods._arrayInsert,
	RemoveAt = ValueMethods._arrayRemoveAt,
	Destroy = ValueMethods._destroy,
}

-->> Metamethods

Value.__index = function(self: RuntimeValue, key: Types.PathKey)
	local method = ValueMethods[key]
	if method then
		return method
	end

	-- Optional internal fields, particularly _onMutation on client wrappers,
	-- may be nil and therefore absent from the table. Never interpret runtime
	-- state keys as generated data children.
	if InternalValueKeys[key] then
		return rawget(self, key)
	end

	local property = ValueProperties[key]
	if property then
		return property(self)
	end

	local operation = ValueOperations[key]
	if operation then
		assert(not self._readOnly or key ~= "Destroy", "Value is read-only")
		return operation
	end

	return ValueMethods._getChild(self, key)
end

Value.__newindex = function(_self: RuntimeValue, key: Types.PathKey, _value: any)
	error(`Cannot assign to data field "{key}". Call it instead: Data[player].{key}(newValue)`)
end

Value.__call = ValueMethods._call

-->> Return

return Value
