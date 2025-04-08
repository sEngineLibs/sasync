package sasync;

class Promise<T> {
	var error:Dynamic;

	public var result:T;

	public inline function new() {}

	#if (sys && target.threaded)
	public static inline function promise<T>(job:Promise<T>->Void):Promise<T> {
		static var pool = new sys.thread.ElasticThreadPool(12);
		var promise = new Promise();
		pool.run(() -> {
			job(promise);
			promise.lock.release();
		});
		return promise;
	}

	var lock = new sys.thread.Lock();

	public inline function await(?timeout:Float):T {
		lock.wait(timeout);
		if (error != null)
			throw error;
		return result;
	}
	#else
	public static inline function promise<T>(job:Promise<T>->Void):Promise<T> {
		return new Promise();
	}

	public inline function await():Void {}
	#end
}
