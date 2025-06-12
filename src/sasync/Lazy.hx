package sasync;

import haxe.Exception;

enum Status<T> {
	Pending;
	Resolved(value:T);
	Rejected(e:Exception);
}

class LazyError extends Exception {}

class Lazy<T:Any> {
	var onResolved:T->Void;
	var onRejected:Exception->Void;

	public var status(default, null):Status<T> = Pending;

	public function new(task:(?T->Void, Exception->Void)->Void) {
		#if (flash || js)
		var id = null;
		#elseif (target.threaded && !cppia)
		var thread:sys.thread.Thread = null;
		var eventHandler = null;
		#else
		var event:haxe.MainEvent = null;
		#end
		var run = () -> {
			#if (flash || js)
			if (id == null)
				return;
			#if flash
			untyped __global__["flash.utils.clearInterval"](id);
			#elseif js
			untyped clearInterval(id);
			#end
			id = null;
			#elseif (target.threaded && !cppia)
			thread.events.cancel(eventHandler);
			#else
			if (event != null) {
				event.stop();
				event = null;
			}
			#end
			try {
				task(resolve, reject);
			} catch (e)
				reject(e);
		}
		#if flash
		id = untyped __global__["flash.utils.setInterval"](run, 0);
		#elseif js
		id = untyped setInterval(run, 0);
		#elseif (target.threaded && !cppia)
		thread = sys.thread.Thread.current();
		if (thread.events == null)
			throw new LazyError("Can't run Lazy in a thread with no event loop");
		eventHandler = thread.events.repeat(run, 0);
		#else
		event = haxe.MainLoop.add(run);
		event.delay(0);
		#end
	}

	public function handle(onResolved:T->Void, ?onRejected:Exception->Void) {
		switch status {
			case Pending:
				this.onResolved = onResolved;
				this.onRejected = onRejected;
			case Resolved(value):
				handleResolve(value);
			case Rejected(e):
				handleReject(e);
		}
	}

	function resolve(?value:T) {
		switch status {
			case Pending:
				status = Resolved(value);
				handleResolve(value);
			default:
		}
	}

	function reject(e:Exception) {
		switch status {
			case Pending:
				status = Rejected(e);
				handleReject(e);
			default:
		}
	}

	function handleResolve(value:T) {
		if (onResolved != null)
			try {
				onResolved(value);
			} catch (e)
				handleReject(e);
	}

	function handleReject(e:Exception) {
		if (onRejected != null)
			onRejected(e);
		else
			throw e;
	}
}
