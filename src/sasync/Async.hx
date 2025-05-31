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

	macro static public function build():Array<Field> {
		return [
			for (field in Context.getBuildFields())
				buildField(field)
		];
	}

	static function buildField(field:Field):Field {
		for (m in field.meta)
			if (["async", ":async"].contains(m.name)) {
				switch field.kind {
					case FFun(f):
						buildAsync(f);
						trace(f.expr.toString());
					default:
						Context.warning("This has no effect", m.pos);
				}
				break;
			}
		return field;
	}

	static var index = 0;

	static function buildAsync(f:Function) {
		index = 0;
		f.ret = null;
		var t = transformTask(f.expr);
		if (!t.transformed)
			f.expr = concat(f.expr, macro __resolve__(null));
		else
			f.expr = t.expr;
		f.expr = transform(f.expr).expr;
		f.expr = macro return new sasync.Promise((__resolve__, __reject__) -> ${f.expr});
	}

	static function transformTask(expr:Expr) {
		var transformed = false;
		expr = switch expr.expr {
			case EFunction(_, _):
				expr;
			case EReturn(e):
				transformed = true;
				macro __resolve__($e);
			default:
				expr.map(e -> {
					var t = transformTask(e);
					transformed = t.transformed ? true : transformed;
					t.expr;
				});
		};
		return {
			transformed: transformed,
			expr: expr
		}
	}

	static function transform(expr:Expr):AsyncContext {
		function await(e:Expr):AsyncContext {
			var name = '__ret${index++}__';
			var ctx = {
				awaitExpr: e,
				awaitCont: macro $i{name}
			}
			return {
				ctx: ctx,
				expr: macro(__cont__ -> ${ctx.awaitExpr})($name -> {
					${ctx.awaitCont};
					return null;
				})
			}
		}

		var ctx:AwaitContext = null;

		function append(e:Expr) {
			var t = transform(e);
			if (t.ctx != null) {
				e.expr = t.ctx.awaitCont.expr;
				if (ctx == null) {
					ctx = t.ctx;
					ctx.awaitCont.expr = expr.expr;
					expr = t.expr;
				} else {
					t.ctx.awaitCont.expr = ctx.awaitCont.expr;
					ctx.awaitCont.expr = t.expr.expr;
					ctx.awaitCont = t.ctx.awaitCont;
				}
			}
			return t.expr;
		}

		switch expr.expr {
			case EMeta(s, e) if (["async", ":async"].contains(s.name)):
				switch e.expr {
					case EFunction(kind, f):
						buildAsync(f);
					default:
						Context.warning("This has no effect", s.pos);
				}

			case EMeta(s, e) if (["await", ":await"].contains(s.name)):
				return await(macro $e.then(v -> sasync.Promise.resolve(__cont__(v))));

			case EBlock(exprs):
				var ret = [];
				while (exprs.length > 0) {
					var t = transform(exprs.shift());
					ret.push(t.expr);
					if (t.ctx != null) {
						ctx = t.ctx;
						if (exprs.length > 0)
							ctx.awaitCont.expr = concat(copy(ctx.awaitCont), transform(block(exprs)).expr).expr;
						break;
					}
				}
				expr = block(ret);

			case EFor(it, expr):
				Context.warning("Async loops are not yet supported", expr.pos);

			case EWhile(econd, e, normalWhile):
				Context.warning("Async loops are not yet supported", expr.pos);

			case ETry(_, _), ESwitch(_, _, _), EIf(_, _, _), ETernary(_, _, _):
				var og = copy(expr);
				var ts:Map<Expr, AsyncContext> = [];
				var delayed = false;

				mapScoped(expr, append, e -> {
					var t = transform(e);
					ts.set(e, t);
					if (t.ctx != null)
						delayed = true;
					e;
				});

				if (delayed) {
					var t = await(mapScoped(og, e -> e, e -> {
						var c = ts.get(e);
						c.ctx?.awaitExpr ?? macro __cont__(${c.expr});
					}));
					if (ctx != null) {
						ctx.awaitCont.expr = t.expr.expr;
						ctx.awaitCont = t.ctx.awaitCont;
					} else
						return t;
				}

			default:
				expr.map(append);
		}

		return {
			ctx: ctx,
			expr: expr
		}
	}

	static function mapScoped(e:Expr, a:Expr->Expr, s:Expr->Expr):Expr {
		function opt(e:Expr, f:Expr->Expr)
			return e == null ? null : f(e);

		return {
			expr: switch e.expr {
				case ETry(e, catches):
					ETry(s(e), catches.map(c -> {
						name: c.name,
						type: c.type,
						expr: s(c.expr)
					}));
				case ESwitch(e, cases, edef):
					ESwitch(s(e), cases.map(c -> {
						values: c.values,
						guard: c.guard,
						expr: s(c.expr)
					}), opt(edef, s));
				case EIf(econd, eif, eelse), ETernary(econd, eif, eelse):
					EIf(a(econd), s(eif), opt(eelse, s));
				default:
					a(e).expr;
			},
			pos: e.pos
		}
	}

	static function copy(e:Expr) {
		return {
			expr: e.expr,
			pos: e.pos
		}
	}

	static function concat(...exprs:Expr) {
		var ret = [];
		for (e in exprs)
			ret = ret.concat(asBlock(e));
		return block(ret);
	}

	static function block(e:Array<Expr>):Expr {
		if (e.length > 0)
			return macro $b{e};
		return null;
	}

	static function asBlock(e:Expr):Array<Expr> {
		return switch e.expr {
			case EBlock(exprs):
				exprs;
			default:
				[e];
		}
	}

	static function transformWhile(cond:Expr, body:Expr) {
		cond = macro if ($cond) repeat();
		return {
			before: macro function repeat()
				$b{asBlock(body).concat([cond])},
			expr: cond
		}
	}

	// static function transformGenerator(cond:Expr, body:Expr) {
	// 	var init = tmp(macro []);
	// 	var fbody = flatten(body, true);
	// 	fbody.before.push(fbody.expr);
	// 	var bbody = fbody.before;
	// 	bbody[bbody.length - 1] = macro ${init.expr}.push(${bbody[bbody.length - 1]});
	// 	var loopBlock = transformWhile(cond, block(bbody));
	// 	return {
	// 		before: [init.before, loopBlock.before, loopBlock.expr],
	// 		expr: init.expr
	// 	}
	// }
	// static function tmp(?expr:Expr, isFinal:Bool = true) {
	// 	static var i = 0;
	// 	var name = '__tmp${i++}__';
	// 	var before;
	// 	if (expr != null)
	// 		if (isFinal)
	// 			before = macro final $name = $expr;
	// 		else
	// 			before = macro var $name = $expr;
	// 	else
	// 		before = macro var $name;
	// 	return {
	// 		before: before,
	// 		expr: macro $i{name}
	// 	}
	// }
}

typedef AwaitContext = {
	awaitExpr:Expr,
	awaitCont:Expr
}

typedef AsyncContext = {
	ctx:AwaitContext,
	expr:Expr
}
#end
