package sasync;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Compiler;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;

typedef AwaitContext = {
	awaitExpr:Expr,
	awaitCont:Expr
}

typedef AsyncContext = {
	ctx:AwaitContext,
	expr:Expr
}
#end

class Async<T> {
	public static function gather<T>(iterable:Array<Future<T>>):Future<Array<T>> {
		return new Future((resolve, reject) -> {
			var ret = [];
			for (i in iterable)
				i.handle(v -> {
					ret.push(v);
					if (ret.length == iterable.length)
						resolve(ret);
				}, reject);
		});
	}

	public static function race<T>(iterable:Array<Future<T>>):Future<T> {
		return new Future((resolve, reject) -> {
			for (i in iterable)
				i.handle(resolve, reject);
		});
	}

	public static function sleep(seconds:Float) {
		return new Future((resolve, reject) -> haxe.Timer.delay(() -> resolve(), Std.int(seconds * 1000)));
	}

	#if macro
	macro public static function init():Void {
		Compiler.addGlobalMetadata("", "@:build(sasync.Async.build())", true, true, true);
		Compiler.registerCustomMetadata({
			metadata: "async",
			doc: "Marks a function to be executed asynchronously"
		});
		Compiler.registerCustomMetadata({
			metadata: ":async",
			doc: "Marks a function to be executed asynchronously"
		});
		Compiler.registerCustomMetadata({
			metadata: "await",
			doc: "Marks an expression whose result should be awaited"
		});
		Compiler.registerCustomMetadata({
			metadata: ":await",
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
		f.expr = transform(t.transformed ? t.expr : concat(t.expr, macro __resolve__())).expr;
		f.expr = macro return new sasync.Future((__resolve__, __reject__) -> ${f.expr});
	}

	static function transformTask(expr:Expr) {
		var transformed = false;

		expr = switch expr.expr {
			case EFunction(_, _):
				expr;
			case EReturn(e):
				transformed = true;
				e == null ? macro __resolve__() : macro __resolve__($e);
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
		var ctx:AwaitContext = null;

		function await(e:Expr) {
			var name = '__ret${index++}__';
			var ctx = {
				awaitExpr: e,
				awaitCont: macro $i{name}
			}
			return {
				ctx: ctx,
				expr: macro ${ctx.awaitExpr}($name -> ${ctx.awaitCont}, __reject__)
			}
		}

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
				return await(macro $e.handle);

			case EBlock(exprs):
				var rest = exprs.copy();
				var ret = [];
				while (rest.length > 0) {
					var t = transform(rest.shift());
					ret.push(t.expr);
					if (t.ctx != null) {
						ctx = t.ctx;
						if (rest.length > 0)
							ctx.awaitCont.expr = concat(copy(ctx.awaitCont), transform(block(rest)).expr).expr;
						break;
					}
				}
				expr = block(ret);

			case EFor(it, expr):
				switch it.expr {
					case EBinop(_, e1, e2):
						switch e1.expr {
							case EConst(c):
								switch c {
									case CIdent(s):
										return transform(macro {
											final __iterable__ = $e2;
											while (__iterable__.hasNext()) {
												var $s = __iterable__.next();
												$expr;
											}
										});
									default:
								}
							default:
						}
					default:
				}

			case EWhile(econd, e, normalWhile):
				var tecond = transform(econd);

				if (tecond.ctx != null)
					econd.expr = tecond.ctx.awaitCont.expr;

				var te = transform(e);
				if (te.ctx != null) {
					var name = '__ret${index++}__';
					var fname = '__repeat${index}__';
					var fnameRef = macro $i{fname};

					te.ctx.awaitCont.expr = concat(copy(te.ctx.awaitCont), macro $fnameRef()).expr;
					var awaitCont = macro {};
					var awaitExpr = te.expr;
					var repeatExpr = macro if ($econd) $awaitExpr else $awaitCont;
					expr = macro {
						function $fname() $repeatExpr;
						$fnameRef();
					};

					if (tecond.ctx != null) {
						tecond.ctx.awaitCont.expr = copy(repeatExpr).expr;
						repeatExpr.expr = tecond.expr.expr;
					}

					ctx = {
						awaitExpr: te.expr,
						awaitCont: awaitCont
					}
				}

			case ETry(_, _), ESwitch(_, _, _), EIf(_, _, _), ETernary(_, _, _):
				var og = copy(expr);
				var ts:Map<Expr, AsyncContext> = [];
				var delayed = false;

				mapScoped(expr, append, e -> {
					if (e != null) {
						var t = transform(e);
						ts.set(e, t);
						e = t.expr;
						if (t.ctx != null)
							delayed = true;
					}
					e;
				});

				if (delayed) {
					var t = await(macro(__cont__ -> ${
						mapScoped(og, e -> e, e -> {
							if (e != null) {
								var c = ts.get(e);
								if (c.ctx != null)
									macro ${c.ctx.awaitExpr}(__cont__);
								else
									macro __cont__(untyped ${c.expr});
							} else
								macro __cont__();
						})
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
					}), s(edef));
				case EIf(econd, eif, eelse), ETernary(econd, eif, eelse):
					EIf(a(econd), s(eif), s(eelse));
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
	#end
}
