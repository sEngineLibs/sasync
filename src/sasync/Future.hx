package sasync;

import haxe.Exception;
import slog.Log;

enum Status<T> {
	Pending;
	Resolved(value:T);
	Rejected(error:Exception);
}

class Future<T:Any> {
	static var callstack:Array<haxe.PosInfos> = [];

	var handler:Handler<T>;

	public var status:Status<T> = Pending;

	public function new(task:(?T->Void, Exception->Void)->Void, ?pos:haxe.PosInfos) {
		callstack.push(pos);
		haxe.Timer.delay(() -> try {
			task(resolve, reject);
		} catch (e)
			reject(e), 0);
	}

	public function handle(onResolved:T->Void, ?onRejected:Exception->Void) {
		this.handler = new Handler(onResolved, onRejected);
	}

	function resolve(?value:T) {
		switch status {
			case Pending:
				status = Resolved(value);
				callstack.pop();
				if (handler != null)
					handler.resolve(value);
			default:
		}
	}

	function reject(error:Exception) {
		switch status {
			case Pending:
				status = Rejected(error);
				if (handler != null)
					handler.reject(error);
				else
					throwError(error);
			default:
		}
	}

	function throwError(error:Exception) {
		var pos = callstack.shift();
		Log.trace('Uncaught exception $error in ${pos.className}.${pos.methodName}', Log.Red, Log.ERROR, pos);
		while (callstack.length > 0) {
			var pos = callstack.shift();
			var next = callstack.shift();
			if (next != null)
				Log.trace('Called from ${next.className}.${next.methodName}', Log.Red, Log.ERROR, pos);
			else
				Log.trace('Called from here', Log.Red, Log.ERROR, pos);
		}
	}
}

private class Handler<T> {
	var onResolved:T->Void;
	var onRejected:Exception->Void;

	public function new(onResolved:T->Void, ?onRejected:Exception->Void) {
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

	public function reject(error:Exception) {
		if (onRejected != null)
			onRejected(error);
	}
}
