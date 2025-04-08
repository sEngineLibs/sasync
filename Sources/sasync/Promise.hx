package sasync;

class Promise<T> {
	public var result:T;

	#if (sys && target.threaded)
	var error:Dynamic;
	var lock = new sys.thread.Lock();

	public inline function new(job:Promise<T>->Void) {
		static var pool = new sys.thread.ElasticThreadPool(12);
		pool.run(() -> {
			try {
				job(this);
			} catch (e)
				error = e;
			lock.release();
		});
	}

	public inline function await():T {
		lock.wait();
		if (error != null)
			throw error;
		return result;
	}
	#else
	public inline function new() {}

	public inline function await():Void {}
	#end
}
