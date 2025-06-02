package;

import haxe.Timer;
import sasync.Future;

class Tests {
	public static function main() {
		trace("Start tests\n");

		runTests().finally(() -> trace("All tests finished"));
	}

	static function get() {
		return;
	}

	@async static function runTests() {
		// @await testSimple();

		// var ret = @await testReturn();
		// trace('Return test: $ret\n');

		// var nested = @await testNested();
		// trace('Nested test: $nested\n');

		// var results = @await testParallel();
		// trace('Parallel test: $results\n');

		// testError().catchError(e -> trace('Caught error: $e'));

		// @await testIfElse(true);
		// @await testIfElse(false);

		// var i = 0;
		// while (i++ < {
		// 	var a = 4;
		// 	@await testAdd(a, 1);
		// }) {
		// 	var b = 0;
		// 	trace(@await testAdd(b, 1));
		// }
		for (i in 0...5) {
			var b = 0;
			trace(@await testAdd(b, 1));
		}
		trace("loop done");
	}

	// @async static function testSimple():Void {
	// 	trace("Simple test...");
	// 	Sys.sleep(0.1);
	// 	trace("Simple done.\n");
	// }
	// @async static function testReturn():String {
	// 	Sys.sleep(0.05);
	// 	return "Hello from async";
	// }
	// @async static function testNested():Int {
	// 	var a = @await testAdd(1, 2);
	// 	var b = @await testAdd(3, 4);
	// 	return a + b;
	// }

	@async static function testAdd(a:Int, b:Int):Int {
		Sys.sleep(0.05);
		return a + b;
	}

	// @async static function testError():Void {
	// 	Sys.sleep(0.05);
	// 	throw "*some error message*";
	// }
	// @async static function testParallel():Array<Int> {
	// 	var p1 = testAdd(1, 1);
	// 	var p2 = testAdd(2, 2);
	// 	var p3 = testAdd(3, 3);
	// 	return @await Future.gather([p1, p2, p3]);
	// }
	// @async static function testLoop():Void {
	// 	for (i in 0...3) {
	// 		trace('Loop step: ' + i + (i == 2 ? "\n" : ""));
	// 		Sys.sleep(0.03);
	// 	}
	// }
	// @async static function testIfElse(flag:Bool) {
	// 	if (flag)
	// 		@await new Future((resolve, reject) -> {
	// 			Timer.delay(() -> {
	// 				trace("Branch: TRUE\n");
	// 				resolve();
	// 			}, 200);
	// 		});
	// 	else
	// 		trace("Branch: FALSE\n");
	// }
}
