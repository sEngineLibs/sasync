package;

import sasync.Async;

@await class Tests {
	public static function main() {
		runTests().finally(() -> trace("All tests finished"));
	}

	@async static function runTests() {
		testError().catchError(e -> trace('Caught error: $e\n'));

		@await testSimple();

		var ret = @await testReturn();
		trace('Return test: $ret\n');

		var nested = @await testNested();
		trace('Nested test: $nested\n');

		var results = @await testParallel();
		trace('Parallel test: $results\n');

		@await testLoop();

		@await testIfElse(true);
		@await testIfElse(false);
	}

	@async static function testSimple():Void {
		trace("Simple test...");
		@await Async.sleep(0.1);
		trace("Simple done.\n");
	}

	@async static function testReturn():String {
		@await Async.sleep(0.5);
		return "Hello from async";
	}

	@async static function testNested():Int {
		var a = @await testAdd(1, 2);
		var b = @await testAdd(3, 4);
		return a + b;
	}

	@async static function testAdd(a:Int, b:Int):Int {
		@await Async.sleep(0.5);
		return a + b;
	}

	@async static function testError():Void {
		@await Async.sleep(0.5);
		if (@await testAdd(1, 2) > 0)
			throw "*some error message*";
	}

	@async static function testParallel():Array<Int> {
		var p1 = testAdd(1, 1);
		var p2 = testAdd(2, 2);
		var p3 = testAdd(3, 3);
		return @await Async.gather([p1, p2, p3]);
	}

	@async static function testLoop():Void {
		for (i in 0...10) {
			@await Async.sleep(0.3);
			trace('Loop step: $i');
			if (i >= 5) {
				trace('Loop break\n');
				break;
			}
		}
	}

	@async static function testIfElse(flag:Bool) {
		@await Async.sleep(0.2);
		if (flag)
			trace("Branch: TRUE");
		else
			trace("Branch: FALSE\n");
	}
}
