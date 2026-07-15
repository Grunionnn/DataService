local RunService = game:GetService("RunService")

local Types = require(script.Types)
local Value = require(script.Value)

-->> Types

export type Options<T> = {
	template: T,
	useMock: boolean?,
	profileStoreIndex: string?,
}

export type Server<T> = {
	read [Player]: Value.ValueType<T>,
	PlayerInitialized: Types.PlayerSignal,
	ProfileReleasing: Types.ProfileSignal,
	HasProfile: (self: any, player: Player) -> boolean,
	WaitForProfile: (self: any, player: Player, timeout: number?) -> any?,
	WaitForData: (self: any, player: Player, timeout: number?) -> T?,
	GetRawProfile: (self: any, player: Player) -> any,
	GetData: (self: any, player: Player) -> T,
}

export type Client<T> = Value.ReadOnlyValueType<T> & {
	IsReady: (self: any) -> boolean,
	WaitForData: (self: any, timeout: number?) -> T?,
	GetData: (self: any) -> T,
}

export type ConfiguredData<T> = {
	server: Server<T>,
	client: Client<T>,
}

-->> Factory

local created = false

-- Keep this type structural at the public call site so Studio can display the
-- available fields and infer T directly from the supplied template.
return function<T>(options: {
	template: T,
	useMock: boolean?,
	profileStoreIndex: string?,
}): ConfiguredData<T>
	assert(not created, "Only one DataService can be created per game runtime")
	assert(type(options) == "table", "DataService options are required")
	assert(type(options.template) == "table", "A data template is required")

	created = true

	if RunService:IsServer() then
		local DataServiceServer = require(script.DataServiceServer)

		return {
			server = DataServiceServer.new(options),
		} :: any
	end

	local DataServiceClient = require(script.DataServiceClient)

	return {
		client = DataServiceClient.new(),
	} :: any
end
