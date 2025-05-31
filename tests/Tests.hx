package;

import sasync.Promise;

class Tests {
	public static function main() {
		trace("Start tests\n");
		runTests().finally(() -> trace("All tests finished"));
	}

	@async static function runTests() {
		@await testSimple();
		var result = @await testReturn();
		trace('Return test: ${result}\n');

		var nested = @await testNested();
		trace('Nested test: $nested\n');

		// testError().catchError(e -> trace('Caught error: $e\n'));

		var results = @await testParallel();
		trace('Parallel test: $results\n');

		@await testLoop();
		@await testIfElse(true);
		@await testIfElse(false);
	}

	@async static function testSimple():Void {
		trace("Simple test...");
		Sys.sleep(0.1);
		trace("Simple done.\n");
	}

	@async static function testReturn():String {
		Sys.sleep(0.05);
		return "Hello from async";
	}

	@async static function testNested():Int {
		var a = @await testAdd(1, 2);
		var b = @await testAdd(3, 4);
		return a + b;
	}

	@async static function testAdd(a:Int, b:Int):Int {
		Sys.sleep(0.05);
		return a + b;
	}

	@async static function testError():Void {
		Sys.sleep(0.05);
		throw "*some error message*";
	}

	@async static function testParallel():Array<Int> {
		var p1 = testAdd(1, 1);
		var p2 = testAdd(2, 2);
		var p3 = testAdd(3, 3);
		return [@await p1, @await p2, @await p3];
	}

	@async static function testLoop():Void {
		for (i in 0...3) {
			trace('Loop step: ' + i + (i == 2 ? "\n" : ""));
			Sys.sleep(0.03);
		}
	}

	@async static function testIfElse(flag:Bool):Void {
		if (flag) {
			trace("Branch: TRUE");
			Sys.sleep(0.02);
		} else {
			trace("Branch: FALSE\n");
			Sys.sleep(0.02);
		}
	}
}
