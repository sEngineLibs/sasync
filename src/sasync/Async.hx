package sasync;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Compiler;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;

typedef AsyncContext = {
	awaitCont:Expr,
	expr:Expr
}
#end

class Async<T> {
	public static function resolve<T>(value:T) {
		return new Future((resolve, _) -> resolve(value));
	}

	public static function reject<T>(value:T) {
		return new Future((_, reject) -> reject(value));
	}

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

	static var awaitIndex = 0;
	static var contIndex = 0;
	static var repeatIndex = 0;

	static function buildAsync(f:Function) {
		awaitIndex = 0;
		contIndex = 0;
		repeatIndex = 0;
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
		var awaitCont:Expr = null;

		function append(e:Expr) {
			var t = transform(e);
			if (t.awaitCont != null) {
				e.expr = t.awaitCont.expr;
				if (awaitCont == null) {
					awaitCont = t.awaitCont;
					awaitCont.expr = expr.expr;
					expr = t.expr;
				} else {
					t.awaitCont.expr = awaitCont.expr;
					awaitCont.expr = t.expr.expr;
					awaitCont = t.awaitCont;
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
				awaitCont = macro untyped $i{name};
				expr = macro $e.handle($name -> ${awaitCont}, __reject__);

			case EBlock(exprs):
				var rest = exprs.copy();
				var ret = [];
				while (rest.length > 0) {
					var t = transform(rest.shift());
					ret.push(t.expr);
					if (t.awaitCont != null) {
						awaitCont = t.awaitCont;
						if (rest.length > 0)
							awaitCont.expr = concat(copy(awaitCont), transform(block(rest)).expr).expr;
						break;
					}
				}
				expr = block(ret);

			case EFor(it, expr):
				return transformFor(it, expr);

			case EWhile(econd, e, normalWhile):
				var tecond = transform(econd);
				var te = transform(e);

				if (te.awaitCont != null) {
					var name = '__ret${awaitIndex++}__';
					var fname = '__repeat${repeatIndex++}__';
					var fnameRef = macro $i{fname};

					te.awaitCont.expr = concat(copy(te.awaitCont), macro $fnameRef($econd)).expr;
					awaitCont = macro {};
					var awaitExpr = unloop(te.expr, econd, fnameRef);
					var repeatExpr = macro if (__cond__) $awaitExpr else $awaitCont;
					expr = macro {
						function $fname(__cond__ : Bool) $repeatExpr;
						$fnameRef($econd);
					};

					if (tecond.awaitCont != null) {
						tecond.awaitCont.expr = copy(repeatExpr).expr;
						repeatExpr.expr = tecond.expr.expr;
					}
				}

			case ETry(_, _), ESwitch(_, _, _), EIf(_, _, _), ETernary(_, _, _):
				var og = copy(expr);
				var ts:Map<Expr, AsyncContext> = [];
				var delayed = false;

				mapScoped(og, append, e -> {
					if (e != null) {
						var t = transform(e);
						ts.set(e, t);
						e.expr = t.expr.expr;
						if (t.awaitCont != null)
							delayed = true;
					}
					e;
				});

				if (delayed) {
					var name = '__cont${contIndex++}__';
					var _awaitCont = macro $i{name}();
					var _expr = macro(__cont__ -> ${
						mapScoped(og, e -> e, e -> {
							if (e != null) {
								var t = ts.get(e);
								if (t.awaitCont != null) {
									t.awaitCont.expr = (macro __cont__(() -> ${copy(t.awaitCont)})).expr;
									macro ${t.expr};
								} else
									macro __cont__(() -> $e);
							} else
								macro __cont__(() -> {});
						})
					})($name -> $_awaitCont);

					if (awaitCont != null)
						awaitCont.expr = _expr.expr;
					else
						expr = _expr;
					awaitCont = _awaitCont;
				}

			default:
				expr.map(append);
		}

		return {
			awaitCont: awaitCont,
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
