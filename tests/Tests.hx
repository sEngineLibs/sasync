package;

import sasync.Async;
import slog.Log;

abstract class ATest {
	public function new() {}

	@async abstract function testAbstract():Int;
}

class Tests extends ATest {
	public static function main() {
		runTests();
	}

	@async static function runTests():Void {
		@await testSimple();

		var ret = @await testReturn();
		Log.debug('Return test: ${ret}\n');

		var nested = @await testNested();
		Log.debug('Nested test: ${nested}\n');

		var parallel = testParallel();
		Log.debug('Parallel test: ${@await parallel}\n');

		Log.debug('Abstract test: ${@await new Tests().testAbstract()}\n');

		try {
			@await testError();
		} catch (e)
			Log.debug('Error test: $e\n');

		@await testLoop();

		@await testIfElse(true);
		@await testIfElse(false);

		Log.debug('Tests finished');
	}

	@async function testAbstract() {
		return @await testAdd(1, 2) + 3;
	}

	@async static function testSimple():Void {
		Log.debug("Simple test...");
		@await Async.sleep(0.1);
		Log.debug("Simple done.\n");
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
				Log.debug('Loop continues');
				continue;
			}
			if (i >= 5) {
				Log.debug('Loop breaks\n');
				break;
			}
			Log.debug('Loop step: $i');
		}
	}

	@async static function testIfElse(flag:Bool):Void {
		@await Async.sleep(0.2);
		if (flag)
			Log.debug("Branch: TRUE");
		else
			Log.debug("Branch: FALSE\n");
	}
}
