# Haxe Async Library (`@async` / `@await`)

A lightweight macro-based asynchronous programming model for Haxe, inspired by `async/await` syntax found in modern languages.

## Features

-   Works with `sys.thread` and `ElasticThreadPool` on threaded targets.
-   Useful for IO-bound or CPU-bound async tasks.
-   Custom metadata:
    -   #### **`@async`**
        Marks a function to be executed asynchronously. The function `<T>` will automatically return a `Promise<T>`. The body of the function will be run in a background thread. If an exception is thrown during execution, it will be captured and stored in the promise. If the function completes successfully, the result will be assigned to the promise.
    -   #### **`@await`**
        Marks an expression whose result should be awaited. The annotated expression must be a `Promise<T>`. At runtime, the current thread will wait for the result of the promise. If the awaited promise has an error, it will throw that error.

---

## Usage

### 1. Add the library to your project

**build.hxml:**

```hxml
-L sasync
```

**khafile.js:**

```js
project.addLibrary("sasync");
```

### 2. Annotate your class methods or modules functions with `@async` metadata

```haxe
...

    @async static function fetchData():String {
        @await tick();
        return "Data";
    }
}

@async function tick():Void {
    Sys.sleep(0.5); // simulate delay
}
```

### 3. Use `@await` to wait for the result

```haxe
@async static function load():Void {
    var data = @await fetchData();
    trace('Received: $data');
}
```

> **Note:** You can use `@await` outside an `@async` function.

---

## Return Values

All `@async` functions must be **explicitly type-hinted** (no type inference):

```haxe
@async static function getInt():Int {
    return 42;
}
```

This becomes:

```haxe
function getInt():Promise<Int>
```

And returns a `Promise<T>` (injected automatically)

---

## Error Handling

Exceptions thrown inside `@async` functions will be caught and re-thrown when awaited:

```haxe
@async function mightFail():Void {
    throw "Something went wrong!";
}

@async function run():Void {
    try {
        @await mightFail();
    } catch (e)
        trace('Caught: ' + e);
}
```

---

## Parallel Execution

You can launch multiple async jobs and await them independently:

```haxe
var p1 = fetchData();
var p2 = fetchData();
var results = [@await p1, @await p2];
```

---

## Example

```haxe
class Example {
    static function main() {
        @await run();
    }

    @async static function run():Void {
        var value = @await compute();
        trace("Value = " + value);
    }

    @async static function compute():Int {
        Sys.sleep(0.1);
        return 1337;
    }
}
```

---

## Requirements

-   `sys.thread` target (e.g., C++, HashLink, Java, etc.)
-   Haxe 4.2+
