package sasync;

import haxe.MainLoop;

enum Status<T> {
	Pending;
	Resolved(value:T);
	Rejected(reason:Dynamic);
}

abstract None(Void) from Void {}

@:forward()
abstract Future<T:Any>(Present<T>) {
	public function new(task:(?T->Void, Dynamic->Void)->Void) {
		this = new Present<T>((resolve, reject) -> {
			var event = null;
			event = MainLoop.add(() -> {
				event.stop();
				try {
					task(resolve, reject);
				} catch (e)
					reject(e);
			});
		});
	}
}

class Present<T> {
	var handlers:Array<Handler<T>> = [];

	public var status:Status<T> = Pending;

	public function new(task:(?T->Void, Dynamic->Void)->Void) {
		try {
			task(resolve, reject);
		} catch (e)
			reject(e);
	}

	public function handle(onResolved:T->Void, ?onRejected:Dynamic->Void) {
		var handler = new Handler(onResolved, onRejected);
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

	function resolve(?value:T) {
		switch status {
			case Pending:
				status = Resolved(value);
				for (h in handlers)
					h.resolve(value);
			default:
		}
	}

	function reject(reason:Dynamic) {
		switch status {
			case Pending:
				status = Rejected(reason);
				for (h in handlers)
					h.reject(reason);
			default:
		}
	}
}

private class Handler<T> {
	var onResolved:T->Void;
	var onRejected:Dynamic->Void;

	public function new(onResolved:T->Void, ?onRejected:Dynamic->Void) {
		this.onResolved = onResolved;
		this.onRejected = onRejected;
	}

	public function resolve(?value:T) {
		if (onResolved != null)
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
