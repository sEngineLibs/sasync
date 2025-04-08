package sasync;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;
using sasync.Async;

class Async<T> {
	#if macro
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
					f.expr = f.expr.transformAwait();
					for (m in field.meta)
						if (m.name == "async") {
							if (f.ret != null)
								f.buildAsync();
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
		f.expr = f.expr.transformJob().transformAsync(t);
	}

	static function transformAwait(expr:Expr):Expr {
		return switch expr.expr {
			case EMeta(meta, inner):
				meta.name == "await" ? macro {$inner.await();} : expr;
			default: expr.map(transformAwait);
		}
	}

	static function transformJob(expr:Expr):Expr {
		return expr.map(e -> switch e.expr {
			case EReturn(inner): inner;
			default: e;
		});
	}

	static function transformAsync(expr:Expr, t:ComplexType):Expr {
		return macro {
			var p = new sasync.Promise();
			@:privateAccess sasync.Promise.post(() -> {
				try {
					${
						if (t.toString() != "Void")
							macro p.result = $expr
						else
							macro $expr
					}
				} catch (e)
					p.error = e;
				p.lock.release();
			});
			return p;
		};
	}
	#end
}
