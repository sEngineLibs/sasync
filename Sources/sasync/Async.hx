package sasync;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;

class Async<T> {
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
		f.expr = transformAsync(transformJob(f.expr), t);
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
			return new sasync.Promise(p -> ${
				if (t.toString() != "Void")
					macro p.result = $expr
				else
					macro $expr
			});
		};
	}
}
#end
