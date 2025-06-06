package;

import haxe.Exception;
import sasync.Async;

using haxe.macro.Expr;

abstract class ATest {
	public function new() {}

	@async abstract function testAbstract():Int;
}

class Tests extends ATest {
	public static function main() {
		var run = runTests();
		run.finally(() -> {
			trace('Tests finished with status ${run.status}');
		});
	}

	@async static function runTests():Void {
		@await testSimple();

		var ret = @await testReturn();
		trace('Return test: ${ret}\n');

		var nested = @await testNested();
		trace('Nested test: ${nested}\n');

		var parallel = testParallel();
		trace('Parallel test: ${@await parallel}\n');

		try {
			@await testError();
		} catch (e)
			trace('Caught error: $e\n');

		@await testLoop();

		@await testIfElse(true);
		@await testIfElse(false);
	}

	@async function testAbstract():Int {
		return @await testAdd(1, 2);
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
		throw "*some error message*";
	}

	@async static function testParallel():Array<Int> {
		var p1 = testAdd(1, 1);
		var p2 = testAdd(2, 2);
		var p3 = testAdd(3, 3);
		return @await Async.gather([p1, p2, p3]);
	}

	@async static function testLoop():Void {
		for (i in -5...15) {
			@await Async.sleep(0.3);
			if (i < 0) {
				trace('Loop continues');
				continue;
			}
			if (i >= 5) {
				trace('Loop breaks\n');
				break;
			}
			trace('Loop step: $i');
		}
	}

	@async static function testIfElse(flag:Bool):Void {
		@await Async.sleep(0.2);
		if (flag)
			trace("Branch: TRUE");
		else
			trace("Branch: FALSE\n");
	}
}
