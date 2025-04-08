package;

class Tests {
	public static function main() {
		#if (target.threaded)
		log("Start tests\n");
		
		@await testSimple();
		var result = @await testReturn();
		log('Return test: $result\n');

		var nested = @await testNested();
		log('Nested test: $nested\n');

		try {
			@await testError();
		} catch (e)
			log('Caught error: $e\n');

		var results = @await testParallel();
		log('Parallel test: $results\n');

		@await testLoop();
		@await testIfElse(true);
		@await testIfElse(false);

		log("All tests finished");
		#else
		trace("Target is not threaded");
		#end
	}

	@async static function testSimple():Void {
		log("Simple test...");
		Sys.sleep(0.1);
		log("Simple done.\n");
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
			log('Loop step: ' + i + (i == 2 ? "\n" : ""));
			Sys.sleep(0.03);
		}
	}

	@async static function testIfElse(flag:Bool):Void {
		if (flag) {
			log("Branch: TRUE\n");
			Sys.sleep(0.02);
		} else {
			log("Branch: FALSE\n");
			Sys.sleep(0.02);
		}
	}

	static function log(s:String) {
		trace('[ASYNC] ' + s);
	}
}
