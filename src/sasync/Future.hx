package sasync;

import haxe.MainLoop;

enum FutureStatus<T> {
	Pending;
	Resolved(value:T);
	Rejected(reason:Dynamic);
}

@:structInit
class FutureHandler<T> {
	var onResolved:T->Void;
	var onRejected:Dynamic->Void;

	public function new(onResolved:T->Void, ?onRejected:Dynamic->Void) {
		this.onResolved = onResolved;
		this.onRejected = onRejected;
	}

	public function resolve(?value:T) {
		try {
			onResolved(value);
		} catch (e)
			reject(e);
	}

	public function reject(reason:Dynamic) {
		if (onRejected != null)
			onRejected(reason);
	}
}

class Future<T> {
	var handlers:Array<FutureHandler<T>> = [];

	public var status:FutureStatus<T> = Pending;

	public function new(task:(?T->Void, Dynamic->Void)->Void) {
		var event = null;
		event = MainLoop.add(() -> {
			event.stop();
			try {
				task(_resolve, _reject);
			} catch (e)
				_reject(e);
		});
	}

	overload extern public inline function handle(onResolved:T->Void, ?onRejected:Dynamic->Void) {
		handle({onResolved: onResolved, onRejected: onRejected});
	}

	overload extern public inline function handle(handler:FutureHandler<T>) {
		switch status {
			case Resolved(value):
				handler.resolve(value);
			case Rejected(reason):
				handler.reject(reason);
			default:
				handlers.push(handler);
		}
	}

	public function catchError(onRejected:Dynamic->Void) {
		handle(null, onRejected);
	}

	public function finally(onFinally:Void->Void) {
		handle(_ -> onFinally(), _ -> onFinally());
	}

	function _resolve(?value:T) {
		switch status {
			case Pending:
				status = Resolved(value);
				for (h in handlers)
					h.resolve(value);
			default:
		}
	}

	function _reject(reason:Dynamic) {
		switch status {
			case Pending:
				status = Rejected(reason);
				for (h in handlers)
					h.reject(reason);
			default:
		}
	}
}