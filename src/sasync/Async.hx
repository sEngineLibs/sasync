package sasync;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Compiler;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;

class Async<T> {
	macro public static function init():Void {
		Compiler.addGlobalMetadata("", "@:build(sasync.Async.build())", true, true, true);
		Compiler.registerCustomMetadata({
			metadata: "async",
			doc: "Marks a function to be executed asynchronously"
		});
		Compiler.registerCustomMetadata({
			metadata: "await",
			doc: "Marks an expression whose result should be awaited"
		});
	}

	macro public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		for (field in fields)
			buildField(field);
		return fields;
	}

	static function buildField(field:Field):Field {
		switch (field.kind) {
			case FFun(f):
				if (f.expr != null) {
					f.expr = transformAwait(f.expr);
					for (m in field.meta)
						if (m.name == "async") {
							if (f.ret != null)
								buildAsync(f);
							else
								Context.error("Async functions must be type-hinted", field.pos);
							break;
						}
				}
			default:
		}
		return field;
	}

	static function buildAsync(f:Function) {
		var t = f.ret;
		f.ret = macro :sasync.Promise<$t>;
		f.expr = transformAsync(f.expr, t);
	}

	static function transformAwait(expr:Expr):Expr {
		return switch expr.expr {
			case EMeta(meta, inner):
				if (meta.name != "await") {
					expr;
				} else if (meta.params.length == 1) {
					switch (meta.params[0].expr) {
						case EConst(c): switch c {
								case CInt(v, s):
									macro ${inner.map(transformAwait)}.await($v{Std.parseFloat(v)});
								case CFloat(f, s):
									macro ${inner.map(transformAwait)}.await($v{Std.parseFloat(f)});
								default:
									Context.error("Number expected", meta.params[0].pos);
							}
						default:
							Context.error("Invalid number of parameters", meta.pos);
					}
				} else macro $inner.await();
			default: expr.map(transformAwait);
		}
	}

	static function transformAsync(expr:Expr, t:ComplexType):Expr {
		return macro @:privateAccess {
			function job()
				$expr;
			return sasync.Promise.promise(promise -> {
				try {
					${
						if (t.toString() != "Void")
							macro promise.result = job()
						else
							macro job()
					}
				} catch (e)
					promise.error = e;
			});
		}
	}
}
#end
