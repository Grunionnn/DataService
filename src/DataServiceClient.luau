local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "DataServiceClient can only be used on the client")

local Data = require(script.Parent.Data)
local Value = require(script.Parent.Value)
local networker = require(script.Parent.Parent.networker)

local GAP_RESYNC_DELAY = 2

-->> Types

type MutationPayload = {
	Type: "Mutation",
	Revision: number,
	Mutation: Data.Mutation,
}

type SnapshotPayload<T> = {
	Data: T,
	Revision: number,
}

type ClientState<T> = {
	_data: Data.Data<T>?,
	_rootValue: Value.RuntimeValue?,
	_ready: boolean,
	_revision: number,
	_pendingMutations: { [number]: Data.Mutation },
	_resyncing: boolean,
	_gapCheckScheduled: boolean,
	_dataReplicationEvent: networker.NetworkerRemoteEvent,
	_dataSnapshotFunction: networker.NetworkerRemoteFunction,
}

local DataServiceClient = {}

type ClientRuntime<T> = typeof(setmetatable({} :: ClientState<T>, DataServiceClient))

export type DataServiceClient<T> = ClientRuntime<T> & Value.ReadOnlyValueType<T>

-->> Metamethods

DataServiceClient.__index = function(self, key)
	local method = DataServiceClient[key]
	if method then
		return method
	end

	-- These optional fields start as nil, so they are absent and reach
	-- __index. Return nil directly instead of recursively reading _rootValue.
	if key == "_data" or key == "_rootValue" then
		return rawget(self, key)
	end

	local rootValue = rawget(self, "_rootValue")
	assert(rootValue, "Client data is not ready")

	return rootValue[key]
end

DataServiceClient.__call = function(self)
	local rootValue = rawget(self, "_rootValue")
	assert(rootValue, "Client data is not ready")

	return rootValue()
end

DataServiceClient.__newindex = function(_self, key, _value)
	error(`Cannot assign to client data field "{key}". Client data is read-only`)
end

-->> Constructor

function DataServiceClient.new<T>(): DataServiceClient<T>
	local self = setmetatable({
		_data = nil,
		_rootValue = nil,
		_ready = false,
		_revision = 0,
		_pendingMutations = {} :: { [number]: Data.Mutation },
		_resyncing = false,
		_gapCheckScheduled = false,
		_dataReplicationEvent = networker.new("DataReplication"),
		_dataSnapshotFunction = networker.new("DataSnapshot", "RemoteFunction"),
	}, DataServiceClient) :: DataServiceClient<T>

	self._dataReplicationEvent:OnClientEvent(function(payload)
		DataServiceClient._receiveMutation(self, payload)
	end)

	DataServiceClient._requestSnapshot(self)
	assert(self._ready and rawget(self, "_data") and rawget(self, "_rootValue"), "Client snapshot failed to initialize")

	return self
end

-->> Snapshot handling

function DataServiceClient._requestSnapshot<T>(self: DataServiceClient<T>)
	if self._resyncing then
		return
	end

	self._resyncing = true

	local snapshot = self._dataSnapshotFunction:InvokeServer()
	assert(type(snapshot) == "table", "Unable to retrieve the data snapshot")
	assert(type(snapshot.Data) == "table", "Data snapshot has invalid data")
	assert(DataServiceClient._isRevision(snapshot.Revision), "Data snapshot has an invalid revision")

	local typedSnapshot = snapshot :: SnapshotPayload<T>
	local dataObject = self._data

	if dataObject then
		dataObject:ReplaceData(typedSnapshot.Data)
	else
		dataObject = Data.new(typedSnapshot.Data)
		-- These fields begin as nil and are therefore absent from the table.
		-- Bypass the public read-only __newindex guard for internal setup only.
		rawset(self, "_data", dataObject)
		rawset(self, "_rootValue", Value.new(dataObject, {}, nil, true))
	end

	self._revision = typedSnapshot.Revision
	self._ready = true
	self._resyncing = false

	DataServiceClient._discardIncludedMutations(self)
	DataServiceClient._drainMutations(self)
end

-->> Mutation handling

function DataServiceClient._receiveMutation<T>(self: DataServiceClient<T>, payload: any)
	assert(type(payload) == "table", "Mutation payload must be a table")
	assert(payload.Type == "Mutation", "Unknown replication payload type")
	assert(DataServiceClient._isRevision(payload.Revision), "Mutation payload has an invalid revision")
	assert(type(payload.Mutation) == "table", "Mutation payload is missing its mutation")

	local typedPayload = payload :: MutationPayload

	if typedPayload.Revision <= self._revision then
		return
	end

	self._pendingMutations[typedPayload.Revision] = typedPayload.Mutation

	if self._ready then
		DataServiceClient._drainMutations(self)
	end
end

function DataServiceClient._discardIncludedMutations<T>(self: DataServiceClient<T>)
	for revision in self._pendingMutations do
		if revision <= self._revision then
			self._pendingMutations[revision] = nil
		end
	end
end

function DataServiceClient._drainMutations<T>(self: DataServiceClient<T>)
	local dataObject = self._data
	if not dataObject then
		return
	end

	while true do
		local nextRevision = self._revision + 1
		local mutation = self._pendingMutations[nextRevision]

		if not mutation then
			break
		end

		self._pendingMutations[nextRevision] = nil
		dataObject:ApplyMutation(mutation)
		self._revision = nextRevision
	end

	DataServiceClient._scheduleGapCheck(self)
end

function DataServiceClient._scheduleGapCheck<T>(self: DataServiceClient<T>)
	if self._gapCheckScheduled or self._resyncing then
		return
	end

	local expectedRevision = self._revision + 1
	local hasLaterRevision = false

	for revision in self._pendingMutations do
		if revision > expectedRevision then
			hasLaterRevision = true
			break
		end
	end

	if not hasLaterRevision then
		return
	end

	self._gapCheckScheduled = true

	task.delay(GAP_RESYNC_DELAY, function()
		self._gapCheckScheduled = false

		if self._pendingMutations[self._revision + 1] then
			DataServiceClient._drainMutations(self)
			return
		end

		for revision in self._pendingMutations do
			if revision > self._revision + 1 then
				task.spawn(DataServiceClient._requestSnapshot, self)
				return
			end
		end
	end)
end

-->> Public API

function DataServiceClient.IsReady<T>(self: DataServiceClient<T>): boolean
	return self._ready
end

function DataServiceClient.GetData<T>(self: DataServiceClient<T>): T
	local dataObject = self._data
	assert(dataObject, "Client data is not ready")

	return dataObject:GetData()
end

-->> Validation

function DataServiceClient._isRevision(value: any): boolean
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

return DataServiceClient
