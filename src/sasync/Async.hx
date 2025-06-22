package sasync;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Compiler;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.MacroStringTools;
using haxe.macro.ComplexTypeTools;

typedef AwaitContext = {
	res:Expr,
	rej:Expr
}

typedef AsyncContext = {
	ctx:AwaitContext,
	expr:Expr
}
#end

typedef None = {}

class Async {
	/**
	 * Executes all given `Lazy` tasks in parallel and returns a new `Lazy`
	 * that resolves once all tasks are complete.
	 * The result is an array of values in the order they complete (not the original order).
	 *
	 * @param iterable Array of `Lazy<T>` tasks to run.
	 * @return A `Lazy` that resolves with an array of results.
	 */
	public static function gather<T:Any>(iterable:Array<Lazy<T>>):Lazy<Array<T>> {
		return new Lazy((resolve, reject) -> {
			var ret = [];
			for (i in iterable)
				i.handle(v -> {
					ret.push(v);
					if (ret.length == iterable.length)
						resolve(ret);
				}, reject);
		});
	}

	/**
	 * Returns a new `Lazy` that resolves or rejects as soon as the first
	 * of the provided `Lazy` tasks does.
	 * Similar to JavaScript's `Promise.race`.
	 *
	 * @param iterable Array of `Lazy<T>` tasks to race.
	 * @return A `Lazy` that resolves with the result of the first completed task.
	 */
	public static function race<T:Any>(iterable:Array<Lazy<T>>):Lazy<T> {
		return new Lazy((resolve, reject) -> {
			for (i in iterable)
				i.handle(resolve, reject);
		});
	}

	/**
	 * Returns a `Lazy` that resolves after a specified delay.
	 *
	 * @param seconds Number of seconds to wait.
	 * @return A `Lazy` that completes after the given time.
	 */
	public static function sleep(seconds:Float):Lazy<None> {
		return new Lazy((resolve, reject) -> haxe.Timer.delay(() -> resolve(), Std.int(seconds * 1000)));
	}

	/**
	 * Runs a synchronous task in the background (threaded target only),
	 * and returns a `Lazy` with the result.
	 *
	 * @param task A function returning a result to run in the background.
	 * @return A `Lazy` that resolves with the task’s result.
	 */
	overload extern public static inline function background<T:Any>(task:Void->T) {
		return new Lazy((resolve, reject) -> {
			#if target.threaded
			var events = sys.thread.Thread.current().events;
			sys.thread.Thread.createWithEventLoop(() -> {
				try {
					var res = task();
					events.runPromised(() -> resolve(res));
				} catch (e)
					events.runPromised(() -> reject(e));
			});
			events.promise();
			#else
			resolve(task());
			#end
		}, false);
	}

	/**
	 * Runs a void background task (no result). If the platform supports threads,
	 * it runs in a separate thread; otherwise, it runs immediately.
	 *
	 * @param task A background function without a return value.
	 * @return A `Lazy` that completes once the task is finished.
	 */
	overload extern public static inline function background(task:Void->Void) {
		return new Lazy((resolve, reject) -> {
			#if target.threaded
			var events = sys.thread.Thread.current().events;
			sys.thread.Thread.createWithEventLoop(() -> {
				try {
					task();
					events.runPromised(() -> resolve());
				} catch (e)
					events.runPromised(() -> reject(e));
			});
			events.promise();
			#else
			task();
			resolve();
			#end
		}, false);
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
						buildAsync(f, field.access.contains(AAbstract));
					default:
						Context.warning("This has no effect", m.pos);
				}
				break;
			}
		return field;
	}

	static var futureIndex = 0;
	static var awaitIndex = 0;
	static var contIndex = 0;
	static var repeatIndex = 0;

	static function buildAsync(f:Function, isAbstract:Bool = false) {
		awaitIndex = 0;
		contIndex = 0;
		repeatIndex = 0;
		futureIndex = 0;

		var void = false;
		var fret = f.ret;

		if (fret != null) {
			if (fret.toString() == "Void") {
				void = true;
				fret = macro :sasync.Async.None;
			}
			f.ret = macro :sasync.Lazy<$fret>;
		}

		if (!isAbstract && f.expr != null) {
			var i = ++futureIndex;
			var resName = '__res${i}__';
			var resRef = macro $i{resName};
			var rejName = '__rej${i}__';
			var t = transformTask(f.expr);

			if (fret != null && !void && !t.transformed)
				Context.error('Missing return: ${fret.toString()}', f.expr.pos);
			else {
				f.expr = t.transformed ? t.expr : concat(t.expr, macro $resRef());
				f.expr = transform(f.expr).expr;
				f.expr = macro return new sasync.Lazy(($resName, $rejName) -> ${f.expr});
			}
		}
	}

	static function transformTask(expr:Expr) {
		var transformed = false;

		expr = switch expr.expr {
			case EFunction(_, _):
				expr;
			case EReturn(e):
				transformed = true;
				var name = '__res${futureIndex}__';
				e == null ? macro $i{name}() : macro $i{name}($e);
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
				var name = '__await${++awaitIndex}__';
				ctx = {
					res: macro $i{name},
					rej: macro $i{'__rej${futureIndex}__'}
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
					var name = '__ret${++awaitIndex}__';
					var fname = '__repeat${++repeatIndex}__';
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
				var pfutureIndex = futureIndex++;

				var te = transform(e);
				if (te.ctx != null) {
					var errName = '__error${++awaitIndex}__';
					var errRef = macro $i{errName};
					var contName = '__cont${++contIndex}__';
					var contRef = macro $i{contName};
					var resName = '__res${futureIndex}__';
					var resRef = macro $i{resName};
					var rejName = '__rej${futureIndex}__';
					var rejRef = macro $i{rejName};
					var prejRef = macro $i{'__rej${pfutureIndex}__'};

					te.ctx.res.expr = (macro $resRef(() -> ${copy(te.ctx.res)})).expr;
					te.ctx.rej.expr = rejRef.expr;

					ctx = {
						res: macro $contRef(),
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
										tcexpr.ctx.res.expr = (macro $resRef(() -> ${copy(tcexpr.ctx.res)})).expr;
										tcexpr.ctx.rej.expr = prejRef.expr;
										cexpr = tcexpr.expr;
									} else
										cexpr = macro $resRef(() -> ${c.expr});
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
								var def = null;
								if (!omitted)
									def = macro $prejRef($errRef);
								ESwitch(errRef, cases, def);
							},
							pos: expr.pos
						}
					}

					expr = macro {
						function $resName<T>($contName:Void -> T) ${ctx.res}
						function $rejName($errName:Dynamic) ${ctx.rej}
						try
							${te.expr} catch ($errName)
							$rejRef($errRef);
					}
					ctx.rej = macro null;
					futureIndex = pfutureIndex;
				}

			case ESwitch(_, _, _), EIf(_, _, _), ETernary(_, _, _):
				var og = copy(expr);
				var ts:Map<Expr, AsyncContext> = [];
				var delayed = false;

				mapScoped(og, append, e -> e);

				var pfutureIndex = futureIndex++;
				mapScoped(og, e -> e, e -> {
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
					var errName = '__error${++awaitIndex}__';
					var errRef = macro $i{errName};
					var prejRef = macro $i{'__rej${pfutureIndex}__'};

					var resName = '__res${futureIndex}__';
					var resRef = macro $i{resName};
					var rejName = '__rej${futureIndex}__';
					var rejRef = prejRef;

					var contName = '__cont${++contIndex}__';
					var contRef = macro $i{contName}();

					var _expr = mapScoped(og, e -> e, e -> {
						if (e != null) {
							var t = ts.get(e);
							if (t.ctx != null) {
								t.ctx.res.expr = (macro $resRef(() -> ${copy(t.ctx.res)})).expr;
								macro ${t.expr};
							} else
								macro $resRef(() -> $e);
						} else
							macro $resRef(() -> null);
					});

					var og = expr;
					expr = macro {
						function $resName<T>($contName:Void -> T) $contRef;
						final $rejName = $rejRef;
						$og;
					}

					var rej = macro $i{'__rej${futureIndex}__'};

					if (ctx != null) {
						ctx.res.expr = _expr.expr;
						ctx.res = contRef;
					} else {
						og.expr = _expr.expr;
						ctx = {
							res: contRef,
							rej: rej
						}
					}
				}
				futureIndex = pfutureIndex;

			// string interpolation
			case EConst(CString(s, kind)):
				switch kind {
					case SingleQuotes:
						return transform(s.formatString(expr.pos));
					default:
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
					case EConst(CIdent(s)):
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
