-->> Services

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsServer(), "DataServiceServer can only be used on the server")

-->> Dependencies

local goodsignal = require(script.Parent.Parent.goodsignal)
local networker = require(script.Parent.Parent.networker)
local profilestore = require(script.Parent.Parent.profilestore)
local Data = require(script.Parent.Data)
local Value = require(script.Parent.Value)

-->> Constants

local PLAYER_PREFIX = "Player_"
local DEFAULT_PROFILE_STORE_INDEX = "Default"
local SNAPSHOT_TIMEOUT = 30

-->> Class

local DataServiceServer = {}
DataServiceServer.__index = function(self, key)
	if typeof(key) == "Instance" and key:IsA("Player") then
		local rootValue = self._playerValues[key]
		
		assert(rootValue, "Player does not have a profile")

		return rootValue
	end

	return DataServiceServer[key]
end

-->> Types

export type DataServiceOptions<T> = {
	template: T,
	useMock: boolean?,
	profileStoreIndex: string?,
}

type ServerState<T> = {
	_template: T,
	_useMock: boolean,
	_playerStore: profilestore.ProfileStore<T>,
	_profiles: { [Player]: profilestore.Profile<T> },
	_playerData: { [Player]: Data.Data<T> },
	_playerValues: { [Player]: Value.RuntimeValue },
	_loadingPlayers: { [Player]: boolean },
	_waitSignals: { [Player]: goodsignal.Signal<profilestore.Profile<T>?> },
	_dataReplicationEvent: networker.NetworkerRemoteEvent,
	_dataSnapshotFunction: networker.NetworkerRemoteFunction,
	_revisions: { [Player]: number },
	
	PlayerInitialized: goodsignal.Signal<Player>,
	ProfileReleasing: goodsignal.Signal<Player, profilestore.Profile<T>>,
}

type ServerRuntime<T> = typeof(setmetatable({} :: ServerState<T>, DataServiceServer))

export type DataServiceServer<T> = ServerRuntime<T> & { read [Player]: Value.ValueType<T> }

-->> Constructor

function DataServiceServer.new<T>(options: DataServiceOptions<T>): DataServiceServer<T>
	assert(RunService:IsServer(), "DataServiceServer can only be used on the server")
	assert(type(options.template) == "table", "A data template is required")

	local profileStoreIndex = options.profileStoreIndex or DEFAULT_PROFILE_STORE_INDEX
	local useMock = options.useMock == true

	local playerStore = profilestore.New(profileStoreIndex, options.template :: any) :: profilestore.ProfileStore<T>

	if useMock then
		playerStore = playerStore.Mock :: any
	end

	local self = setmetatable({
		_template = options.template,
		_useMock = useMock,
		_playerStore = playerStore,
		_profiles = {} :: { [Player]: profilestore.Profile<T> },
		_playerData = {} :: { [Player]: Data.Data<T> },
		_playerValues = {} :: { [Player]: Value.RuntimeValue },
		_loadingPlayers = {} :: { [Player]: boolean },
		_waitSignals = {} :: { [Player]: goodsignal.Signal<profilestore.Profile<T>?> },
		_revisions = {} :: { [Player]: number },
		_dataReplicationEvent = networker.new("DataReplication"),
		_dataSnapshotFunction = networker.new("DataSnapshot", "RemoteFunction"),

		PlayerInitialized = goodsignal.new(),
		ProfileReleasing = goodsignal.new(),
	}, DataServiceServer) :: DataServiceServer<T>

	self._dataSnapshotFunction:OnServerInvoke(function(player: Player)
		return DataServiceServer._getSnapshot(self, player, SNAPSHOT_TIMEOUT)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(DataServiceServer._onPlayerAdded, self, player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		DataServiceServer._onPlayerRemoving(self, player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(DataServiceServer._onPlayerAdded, self, player)
	end

	return self
end

-->> Player lifecycle

--// Loading

function DataServiceServer._onPlayerAdded<T>(self: DataServiceServer<T>, player: Player)
	if self._profiles[player] or self._loadingPlayers[player] then
		return
	end

	self._loadingPlayers[player] = true

	local profile = self._playerStore:StartSessionAsync(PLAYER_PREFIX .. player.UserId, {})
	self._loadingPlayers[player] = nil

	if not profile then
		DataServiceServer._resolveProfileWaiters(self, player, nil)
		player:Kick("Unable to load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	if not player:IsDescendantOf(Players) then
		DataServiceServer._resolveProfileWaiters(self, player, nil)
		profile:EndSession()
		return
	end

	self._profiles[player] = profile
	self._playerData[player] = Data.new(profile.Data :: T)
	self._revisions[player] = 0
	self._playerValues[player] = Value.new(self._playerData[player], {}, function(mutation: Data.Mutation, dontReplicate: boolean?)
		if not dontReplicate then
			DataServiceServer._replicateMutation(self, player, mutation)
		end
	end)

	profile.OnSessionEnd:Connect(function()
		if self._profiles[player] ~= profile then
			return
		end

		DataServiceServer._cleanupPlayer(self, player, profile, false)

		if player:IsDescendantOf(Players) then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)

	self.PlayerInitialized:Fire(player)
	DataServiceServer._resolveProfileWaiters(self, player, profile)
end

--// Profile waiters

function DataServiceServer._resolveProfileWaiters<T>(self: DataServiceServer<T>, player: Player, profile: profilestore.Profile<T>?)
	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		return
	end

	self._waitSignals[player] = nil
	waitSignal:Fire(profile)
end

--// Cleanup

function DataServiceServer._cleanupPlayer<T>(self: DataServiceServer<T>, player: Player, expectedProfile: profilestore.Profile<T>?, endSession: boolean)
	if expectedProfile and self._profiles[player] ~= expectedProfile then
		return
	end
	
	local rootValue = self._playerValues[player]
	local dataObject = self._playerData[player]
	local profile = self._profiles[player]

	if profile then
		self.ProfileReleasing:Fire(player, profile)
	end

	DataServiceServer._resolveProfileWaiters(self, player, nil)

	self._playerValues[player] = nil
	self._loadingPlayers[player] = nil
	self._playerData[player] = nil
	self._profiles[player] = nil
	self._revisions[player] = nil

	if rootValue then
		rootValue:Destroy()
	end

	if dataObject then
		dataObject:Destroy()
	end

	if endSession and profile and profile:IsActive() then
		profile:EndSession()
	end
end

function DataServiceServer._onPlayerRemoving<T>(self: DataServiceServer<T>, player: Player)
	DataServiceServer._cleanupPlayer(self, player, self._profiles[player], true)
end

-->> Replication

--// Mutations

function DataServiceServer._replicateMutation<T>(self: DataServiceServer<T>, player: Player, mutation: Data.Mutation)
	local currentRevision = self._revisions[player]
	assert(currentRevision, "Cannot replicate before the player's profile is initialized")

	local revision = currentRevision + 1
	self._revisions[player] = revision

	self._dataReplicationEvent:FireClient(player, {
		Type = "Mutation",
		Revision = revision,
		Mutation = mutation,
	})
end

--// Snapshots

function DataServiceServer._getSnapshot<T>(self: DataServiceServer<T>, player: Player, timeout: number)
	local profile = DataServiceServer.WaitForProfile(self, player, timeout)
	if not profile then
		return nil
	end

	local playerData = self._playerData[player]
	if playerData then
		return {
			Data = playerData:GetData(),
			Revision = self._revisions[player] or 0,
		}
	end

	return nil
end

-->> Public API

function DataServiceServer.HasProfile<T>(self: DataServiceServer<T>, player: Player): boolean
	return self._profiles[player] ~= nil
end

function DataServiceServer.GetData<T>(self: DataServiceServer<T>, player: Player): T
	local playerData = self._playerData[player]
	assert(playerData, "Player does not have a profile")

	return playerData:GetData()
end

function DataServiceServer.WaitForData<T>(self: DataServiceServer<T>, player: Player, timeout: number?): T?
	local profile = DataServiceServer.WaitForProfile(self, player, timeout)
	if not profile then
		return nil
	end

	local playerData = self._playerData[player]
	if not playerData then
		return nil
	end

	return playerData:GetData()
end

function DataServiceServer.GetRawProfile<T>(self: DataServiceServer<T>, player: Player): profilestore.Profile<T>
	local profile = self._profiles[player]
	assert(profile, "Player does not have a profile")
	return profile
end

function DataServiceServer.WaitForProfile<T>(self: DataServiceServer<T>, player: Player, timeout: number?): profilestore.Profile<T>?
	local profile = self._profiles[player]
	if profile then
		return profile
	end

	if not player:IsDescendantOf(Players) then
		return nil
	end

	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		waitSignal = goodsignal.new()
		self._waitSignals[player] = waitSignal
	end

	profile = self._profiles[player]
	if profile then
		return profile
	end

	if timeout == nil then
		return waitSignal:Wait()
	end

	assert(timeout >= 0, "Timeout cannot be negative")

	local waitingThread = coroutine.running()
	local finished = false
	local connection: goodsignal.Connection?

	local function finish(result: profilestore.Profile<T>?)
		if finished then
			return
		end

		finished = true

		if connection then
			connection:Disconnect()
		end

		task.spawn(waitingThread, result)
	end

	connection = waitSignal:Connect(finish)

	profile = self._profiles[player]
	if profile then
		connection:Disconnect()
		return profile
	end

	task.delay(timeout, finish, nil)

	return coroutine.yield()
end

-->> Return

return DataServiceServer
