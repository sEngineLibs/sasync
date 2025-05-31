package sasync;

#if js
typedef Promise = js.lib.Promise;

#else
import haxe.MainLoop;

/**
	A value with a `then` method.
**/
interface Thenable<T> {
	@:overload(function<TOut>(?onFulfilled:T->TOut, ?onRejected:Dynamic->TOut):Promise<TOut> {})
	function then<TOut>(?onFulfilled:T->Thenable<TOut>, ?onRejected:Dynamic->Thenable<TOut>):Promise<TOut>;
}

typedef PromiseSettleOutcome<T> = {
	var status:PromiseSettleStatus;
	var ?value:T;
	var ?reason:Dynamic;
}

enum abstract PromiseSettleStatus(String) to String {
	var Fulfilled = "fulfilled";
	var Rejected = "rejected";
}

class Promise<T> {
	/**
		Returns a Promise object that is resolved with the given value. If the
		value is Thenable, the returned promise will "follow" that
		thenable, adopting its eventual state;
		otherwise the returned promise will be fulfilled with the value.
		Generally, when it's unknown when value is a promise or not,
		use `Promise.resolve(value)` instead and work with the return value as
		a promise.
	**/
	overload extern public static inline function resolve<T>(?value:T):Promise<T> {
		return new Promise((resolve, _) -> resolve(value));
	}

	/**
		Returns a Promise object that is resolved with the given value. If the
		value is Thenable, the returned promise will "follow" that
		thenable, adopting its eventual state;
		otherwise the returned promise will be fulfilled with the value.
		Generally, when it's unknown when value is a promise or not,
		use `Promise.resolve(value)` instead and work with the return value as
		a promise.
	**/
	overload extern public static inline function resolve<T>(thenable:Thenable<T>):Promise<T> {
		return new Promise((resolve, _) -> thenable.then(resolve));
	}

	/**
		Returns a Promise object that is rejected with the given reason.
	**/
	public static inline function reject<T>(?reason:Dynamic):Promise<T> {
		return new Promise((_, reject) -> reject(reason));
	}

	/**
		Returns a promise that either fulfills when all of the promises in the
		iterable argument have fulfilled or rejects as soon as one of the
		promises in the iterable argument rejects. If the returned promise
		fulfills, it is fulfilled with an array of the values from the
		fulfilled promises in the same order as defined in the iterable.
		If the returned promise rejects, it is rejected with the reason from
		the first promise in the iterable that rejected. This method can be
		useful for aggregating results of multiple promises.
	**/
	overload extern public static inline function all(iterable:Array<Dynamic>):Promise<Array<Dynamic>> {
		return all(iterable.map(i -> Promise.resolve(i)));
	}

	/**
		Returns a promise that either fulfills when all of the promises in the
		iterable argument have fulfilled or rejects as soon as one of the
		promises in the iterable argument rejects. If the returned promise
		fulfills, it is fulfilled with an array of the values from the
		fulfilled promises in the same order as defined in the iterable.
		If the returned promise rejects, it is rejected with the reason from
		the first promise in the iterable that rejected. This method can be
		useful for aggregating results of multiple promises.
	**/
	overload extern public static inline function all<T>(iterable:Array<Promise<T>>):Promise<Array<T>> {
		return new Promise((resolve, reject) -> {
			var ret:Array<T> = [];
			for (p in iterable)
				p.then(v -> {
					ret.push(v);
					if (ret.length == iterable.length)
						resolve(ret);
				}, reject);
		});
	}

	/**
		Returns a promise that resolves after all of the given promises have either fulfilled or rejected,
		with an array of objects that each describes the outcome of each promise.

		It is typically used when you have multiple asynchronous tasks that are not dependent on one another
		to complete successfully, or you'd always like to know the result of each promise.

		In comparison, the Promise returned by `Promise.all` may be more appropriate if the tasks are dependent
		on each other / if you'd like to immediately reject upon any of them rejecting.
	**/
	// @:overload(function(iterable:Array<Dynamic>):Promise<Array<PromiseSettleOutcome<Dynamic>>> {})
	public static inline function allSettled<T>(iterable:Array<Promise<T>>):Promise<Array<PromiseSettleOutcome<T>>> {
		return new Promise((resolve, reject) -> {
			var ret:Array<PromiseSettleOutcome<T>> = [];
			for (p in iterable)
				p.finally(() -> {
					ret.push(p.outcome);
					if (ret.length == iterable.length)
						resolve(ret);
				});
		});
	}

	/**
		Returns a promise that fulfills or rejects as soon as one of the
		promises in the iterable fulfills or rejects, with the value or reason
		from that promise.
	**/
	overload extern public static inline function race<T>(iterable:Array<Dynamic>):Promise<Dynamic> {
		return race(iterable.map(i -> Promise.resolve(i)));
	}

	/**
		Returns a promise that fulfills or rejects as soon as one of the
		promises in the iterable fulfills or rejects, with the value or reason
		from that promise.
	**/
	overload extern public static inline function race<T>(iterable:Array<Promise<T>>):Promise<T> {
		return new Promise((resolve, reject) -> {
			for (p in iterable)
				p.then(resolve, reject);
		});
	}

	var event:MainEvent;
	var outcome:PromiseSettleOutcome<T>;

	var resolvedHandlers:Array<T->Void> = [];
	var rejectedHandlers:Array<Dynamic->Void> = [];

	public function new(init:(resolve:(value:T) -> Void, reject:(reason:Dynamic) -> Void) -> Void):Void {
		event = MainLoop.add(() -> {
			event.stop();
			try {
				init(_resolve, _reject);
			} catch (e) {
				_reject(e);
			}
		});
	}

	/**
		Appends fulfillment and rejection handlers to the promise and returns a
		new promise resolving to the return value of the called handler, or to
		its original settled value if the promise was not handled
		(i.e. if the relevant handler onFulfilled or onRejected is not a function).
	**/
	overload extern public inline function then<TOut>(?onFulfilled:T->TOut, ?onRejected:Dynamic->TOut):Promise<TOut> {
		return _then(onFulfilled == null ? null : (resolve, reject, v) -> resolve(onFulfilled(v)),
			onRejected == null ? null : (resolve, reject, e) -> resolve(onRejected(e)));
	}

	/**
		Appends fulfillment and rejection handlers to the promise and returns a
		new promise resolving to the return value of the called handler, or to
		its original settled value if the promise was not handled
		(i.e. if the relevant handler onFulfilled or onRejected is not a function).
	**/
	overload extern public inline function then<TOut>(?onFulfilled:T->Thenable<TOut>, ?onRejected:Dynamic->Thenable<TOut>):Promise<TOut> {
		return _then(onFulfilled == null ? null : (resolve, reject, v) -> onFulfilled(v).then(resolve, reject),
			onRejected == null ? null : (resolve, reject, e) -> onRejected(e).then(resolve, reject)); // error: sasync.Thenable.T should be then.TOut
	}

	/**
		Appends a rejection handler callback to the promise, and returns a new
		promise resolving to the return value of the callback if it is called,
		or to its original fulfillment value if the promise is instead fulfilled.
	**/
	overload extern public inline function catchError<TOut>(onRejected:Dynamic->TOut):Promise<TOut> {
		return then(null, onRejected);
	}

	/**
		Appends a rejection handler callback to the promise, and returns a new
		promise resolving to the return value of the callback if it is called,
		or to its original fulfillment value if the promise is instead fulfilled.
	**/
	overload extern public inline function catchError(onRejected:Dynamic->T):Promise<T> {
		return then(null, onRejected);
	}

	/**
		Returns a Promise. When the promise is settled, i.e either fulfilled or rejected,
		the specified callback function is executed. This provides a way for code to be run
		whether the promise was fulfilled successfully or rejected once the Promise has been dealt with.
	**/
	public function finally(onFinally:() -> Void):Promise<T> {
		return new Promise((resolve, reject) -> {
			onFinally = () -> {
				onFinally();
				resolve(null);
			};
			switch outcome?.status {
				case Fulfilled, Rejected:
					onFinally();
				default:
					resolvedHandlers.push(_ -> onFinally());
					rejectedHandlers.push(_ -> onFinally());
			}
		});
	}

	function _then<TOut>(ret:(resolve:TOut->Void, reject:Dynamic->Void, v:T)->Void, rej:(resolve:TOut->Void, reject:Dynamic->Void, e:Dynamic)->Void) {
		return new Promise((resolve, reject) -> {
			var s = v -> {
				try {
					ret(resolve, reject, v);
				} catch (e)
					reject(e);
			};

			var r = (e:Dynamic) -> {
				try {
					rej(resolve, reject, e);
				} catch (ex)
					reject(ex);
			};

			switch outcome?.status {
				case Fulfilled:
					if (ret != null) s(outcome.value);
				case Rejected:
					if (rej != null) r(outcome.reason);
				default:
					if (ret != null)
						resolvedHandlers.push(s);
					if (rej != null) rejectedHandlers.push(r);
			}
		});
	}

	function _resolve(value:T):Void {
		_finally(() -> {
			outcome = {
				status: PromiseSettleStatus.Fulfilled,
				value: value
			}
			for (f in resolvedHandlers)
				f(value);
		});
	}

	function _reject(reason:Dynamic):Void {
		_finally(() -> {
			outcome = {
				status: PromiseSettleStatus.Rejected,
				reason: reason
			}
			for (f in rejectedHandlers)
				f(reason);
		});
	}

	function _finally(f:() -> Void) {
		switch outcome?.status {
			case Fulfilled, Rejected:
			default:
				f();
		}
	}
}
#end
