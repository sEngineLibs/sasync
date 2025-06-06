package sasync;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Compiler;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;

typedef AwaitContext = {
	res:Expr,
	rej:Expr,
}

typedef AsyncContext = {
	ctx:AwaitContext,
	expr:Expr
}
#end

class Async {
	public static function gather<T:Any>(iterable:Array<Future<T>>):Future<Array<T>> {
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

	public static function race<T:Any>(iterable:Array<Future<T>>):Future<T> {
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

	static var awaitIndex = 0;
	static var contIndex = 0;
	static var repeatIndex = 0;

	static function buildAsync(f:Function) {
		awaitIndex = 0;
		contIndex = 0;
		repeatIndex = 0;

		var fret = f.ret;
		if (fret != null) {
			if (fret.toString() == "Void")
				fret = macro :sasync.Future.None;
			f.ret = macro :sasync.Future<$fret>;
			var t = transformTask(f.expr);
			f.expr = transform(t.transformed ? t.expr : concat(t.expr, macro __resolve__())).expr;
			f.expr = macro return new sasync.Future((__resolve__, __reject__) -> ${f.expr});
		} else
			Context.error("Async functions must be type-hinted", f.expr.pos);
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

		function append(e:Expr) {
			var t = transform(e);
			if (t.ctx != null) {
				e.expr = t.ctx.res.expr;
				if (ctx == null) {
					t.ctx.res.expr = expr.expr;
					expr = t.expr;
					ctx = t.ctx;
				} else {
					t.ctx.res.expr = ctx.res.expr;
					ctx.res.expr = t.expr.expr;
					ctx.res = t.ctx.res;
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
				var name = '__await${awaitIndex++}__';
				ctx = {
					res: macro $i{name},
					rej: macro __reject__
				}
				expr = macro $e.handle($name -> ${ctx.res}, ${ctx.rej});

			case EBlock(exprs):
				var rest = exprs.copy();
				var ret = [];
				while (rest.length > 0) {
					var t = transform(rest.shift());
					ret.push(t.expr);
					if (t.ctx != null) {
						ctx = t.ctx;
						if (rest.length > 0)
							ctx.res.expr = concat(copy(ctx.res), transform(block(rest)).expr).expr;
						break;
					}
				}
				expr = block(ret);

			case EFor(it, expr):
				return transformFor(it, expr);

			case EWhile(econd, e, normalWhile):
				var tecond = transform(econd);
				var te = transform(e);

				if (te.ctx != null) {
					var name = '__ret${awaitIndex++}__';
					var fname = '__repeat${repeatIndex++}__';
					var fnameRef = macro $i{fname};

					te.ctx.res.expr = concat(copy(te.ctx.res), macro $fnameRef($econd)).expr;
					ctx = {
						res: macro {},
						rej: te.ctx.rej
					}
					var awaitExpr = unloop(te.expr, econd, fnameRef);
					var repeatExpr = macro if (__cond__) $awaitExpr else ${ctx.res};
					expr = macro {
						function $fname(__cond__ : Bool) $repeatExpr;
						$fnameRef($econd);
					};

					if (tecond.ctx != null) {
						tecond.ctx.res.expr = copy(repeatExpr).expr;
						repeatExpr.expr = tecond.expr.expr;
					}
				}

			case ETry(e, catches):
				var te = transform(e);
				if (te.ctx != null) {
					var i = awaitIndex++;
					var errName = '__error${i}__';
					var errRef = macro $i{errName};
					ctx = {
						res: macro __res__(),
						rej: {
							expr: {
								var omitted = false;
								var cases = [];
								for (c in catches) {
									var cname = c.name;
									var ctype = c.type;
									var tcexpr = transform(c.expr);
									var cexpr;
									if (tcexpr.ctx != null) {
										tcexpr.ctx.res.expr = (macro __cont__(() -> ${copy(tcexpr.ctx.res)})).expr;
										cexpr = tcexpr.expr;
									} else
										cexpr = macro __cont__(() -> ${c.expr});
									var values = [macro var $cname];
									if (ctype != null)
										cases.push({
											values: values,
											guard: macro $errRef is $ctype,
											expr: cexpr
										});
									else {
										omitted = true;
										cases.push({
											values: values,
											guard: null,
											expr: cexpr
										});
										break;
									}
								}
								var def = omitted ? null : macro __reject__($errRef);
								ESwitch(errRef, cases, def);
							},
							pos: expr.pos
						}
					}
					var _expr = macro(__cont__ -> {
						new sasync.Future.Present((__resolve__, __reject__) -> ${te.expr}).handle(__cont__, $errName -> ${ctx.rej});
					})(__res__ -> ${ctx.res});
					expr = macro $_expr;
				}

			case ESwitch(_, _, _), EIf(_, _, _), ETernary(_, _, _):
				var og = copy(expr);
				var ts:Map<Expr, AsyncContext> = [];
				var delayed = false;

				mapScoped(og, append, e -> {
					if (e != null) {
						var t = transform(e);
						ts.set(e, t);
						e.expr = t.expr.expr;
						if (t.ctx != null)
							delayed = true;
					}
					e;
				});

				if (delayed) {
					var name = '__cont${contIndex++}__';
					var _continuation = macro $i{name}();

					var _expr = macro(__cont__ -> ${
						mapScoped(og, e -> e, e -> {
							if (e != null) {
								var t = ts.get(e);
								if (t.ctx != null) {
									t.ctx.res.expr = (macro __cont__(() -> ${copy(t.ctx.res)})).expr;
									macro ${t.expr};
								} else
									macro __cont__(() -> untyped $e);
							} else
								macro __cont__(() -> {});
						})
					})($name -> $_continuation);

					if (ctx != null) {
						ctx.res.expr = _expr.expr;
						ctx.res = _continuation;
						ctx.rej = macro __reject__;
					} else {
						expr = _expr;
						ctx = {
							res: _continuation,
							rej: macro __reject__
						}
					}
				}

			default:
				expr.map(append);
		}

		return {
			ctx: ctx,
			expr: expr
		}
	}

	static function transformFor(it:Expr, expr:Expr) {
		return switch it.expr {
			case EBinop(_, e1, e2):
				switch e1.expr {
					case EConst(c):
						switch c {
							case CIdent(s):
								transform(macro {
									final __iterable__ = $e2;
									while (__iterable__.hasNext()) {
										var $s = __iterable__.next();
										$expr;
									}
								});
							default:
								null;
						}
					default:
						null;
				}
			default:
				null;
		}
	}

	static function unloop(expr:Expr, econd:Expr, ref:Expr) {
		return expr.map(e -> {
			switch e.expr {
				case EFor(_, _), EWhile(_, _, _):
					e;
				case EBreak:
					macro {
						$ref(false);
						return;
					}
				case EContinue:
					macro {
						$ref($econd);
						return;
					}
				default:
					unloop(e, econd, ref);
			}
		});
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
					ESwitch(a(e), cases.map(c -> {
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
