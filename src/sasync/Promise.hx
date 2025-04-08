package sasync;

class Promise<T> {
	#if (target.threaded)
	var lock = new sys.thread.Lock();

	var result:T;
	var error:Dynamic;

	public function new() {}

	public function await():T {
		lock.wait();
		if (error != null)
			throw error;
		return result;
	}

	static function post(job:Void->Void) {
		static var pool = new sys.thread.ElasticThreadPool(12);
		pool.run(job);
	}
	#end
}
