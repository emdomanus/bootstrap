--!strict
export type BootstrapTelemetryNotification = { depth: number }
export type BootstrapTelemetrySignal<T...> = {
	connect: (self: BootstrapTelemetrySignal<T...>, callback: (T...) -> ()) -> () -> (),
	replay: (self: BootstrapTelemetrySignal<T...>, callback: (T...) -> (), T...) -> (),
	emit: (self: BootstrapTelemetrySignal<T...>, T...) -> (),
	close: (self: BootstrapTelemetrySignal<T...>) -> (),
}
export type BootstrapTelemetrySignalImpl<T...> = BootstrapTelemetrySignal<T...> & {
	_notification: BootstrapTelemetryNotification,
	_listeners: { [number]: (T...) -> () },
	_nextId: number,
	_closed: boolean,
}
return {}
