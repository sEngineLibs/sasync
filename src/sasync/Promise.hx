package sasync;

import haxe.MainLoop;

enum PromiseState<T> {
	Pending;
	Cancelled;
	Resolved(result:T);
	Rejected(error:Dynamic);
}

@:allow(sasync.Async)
class Promise<T> {
	var event:MainEvent;

	public var state(default, null):PromiseState<T>;

	var resolveTasks:Array<T->Void> = [];
	var rejectTasks:Array<Dynamic->Void> = [];

	public function new() {}

	public function run(job:Void->Void) {
		event = MainLoop.add(() -> {
			event.stop();
			job();
		});
		state = Pending;
	}

	public function cancel() {
		event.stop();
		state = Cancelled;
	}

	public function then(task:T->Void):Promise<T> {
		switch state {
			case Resolved(result):
				task(result);
			default:
				resolveTasks.push(task);
		}
		return this;
	}

	public function catchError(task:Dynamic->Void):Promise<T> {
		switch state {
			case Rejected(error):
				task(error);
			default:
				rejectTasks.push(task);
		}
		return this;
	}

	public function resolve(?result:T) {
		state = Resolved(result);
		for (task in resolveTasks)
			task(result);
	}

	public function reject(error:Dynamic) {
		state = Rejected(error);
		for (task in rejectTasks)
			task(error);
	}
}
