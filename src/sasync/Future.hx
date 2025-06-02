package sasync;

import haxe.MainLoop;

enum FutureStatus<T> {
	Pending;
	Resolved(value:T);
	Rejected(reason:Dynamic);
}

class Future<T> {
	public static function gather<T>(iterable:Array<Future<T>>):Future<Array<T>> {
		return new Future((resolve, reject) -> {
			var ret = [];
			for (i in iterable)
				i.handle(v -> {
					ret.push(v);
					if (ret.length == iterable.length)
						resolve(ret);
				}, reject);
		});
	}

	public static function race<T>(iterable:Array<Future<T>>):Future<T> {
		return new Future((resolve, reject) -> {
			for (i in iterable)
				i.handle(resolve, reject);
		});
	}

	var onResolved:Array<T->Void> = [];
	var onRejected:Array<Dynamic->Void> = [];

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

	public function handle(onResolved:T->Void, ?onRejected:Dynamic->Void) {
		switch status {
			case Resolved(value) if (onResolved != null):
				onResolved(value);
			case Rejected(reason) if (onRejected != null):
				onRejected(reason);
			default:
				if (onResolved != null)
					this.onResolved.push(onResolved);
				if (onRejected != null)
					this.onRejected.push(onRejected);
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
				for (f in onResolved)
					f(value);
			default:
		}
	}

	function _reject(reason:Dynamic) {
		switch status {
			case Pending:
				status = Rejected(reason);
				for (f in onRejected)
					f(reason);
			default:
		}
	}
}
