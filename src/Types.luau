--!strict
-->> Dependencies

local goodsignal = require(script.Parent.Parent.goodsignal)

-->> Module

local Types = {}

-->> Shared types

export type PathKey = string | number
export type Path = string | {PathKey}
export type SignalConnection = goodsignal.Connection

export type ReadOnlySignal<T...> = {
	Connect: (self: ReadOnlySignal<T...>, callback: (T...) -> ()) -> SignalConnection,
	Once: (self: ReadOnlySignal<T...>, callback: (T...) -> ()) -> SignalConnection,
	Wait: (self: ReadOnlySignal<T...>) -> T...,
}

export type ChangedSignal<T> = ReadOnlySignal<T, T>
export type ArraySignal<T> = ReadOnlySignal<number, T>
export type MutableChangedSignal<T> = goodsignal.Signal<T, T>
export type MutableArraySignal<T> = goodsignal.Signal<number, T>
export type PlayerSignal = goodsignal.Signal<Player>
export type ProfileSignal = goodsignal.Signal<Player, any>

export type ResolvedParent = {
	Key: string,
	Parent: { [any]: any },
}

-->> Return

return Types
