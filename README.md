# Haxe Async Library (`@async` / `@await`)

A lightweight macro-based asynchronous programming model for Haxe, inspired by `async/await` syntax found in modern languages.

## Installation

```
haxelib install sasync
```

---

## Features

-   Useful for IO-bound or CPU-bound async tasks.
-   Custom metadata:
    -   #### **`@async`**
        Marks a function to be executed asynchronously. The function `<T>` will automatically return a `Lazy<T>`. The body of the function will be run in a background thread. If an exception is thrown during execution, it will be captured and stored in the lazy operation. If the function completes successfully, the result will be assigned to the lazy operation.
    -   #### **`@await`**
        Marks an expression whose result should be awaited. The annotated expression must be a `Lazy<T>`. At runtime, the current thread will wait for the result of the lazy operation. If the awaited lazy operation has an error, it will throw that error.

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
    @await Async.sleep(0.5); // simulate delay
}
```

### 3. Use `@await` to wait for the result

```haxe
@async static function load():Void {
    var data = @await fetchData();
    trace('Received: $data');
}
```

> **Note:** You can't use `@await` outside an `@async` function.

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
function getInt():Lazy<Int>
```

And returns a `Lazy<T>` (injected automatically)

---

## Error Handling

Exceptions thrown inside `@async` functions can be caught when awaited just like synchronous:

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
var results = @await Async.gather([p1, p2]);
```

---

## Example

```haxe
class Example {
    static function main() {
        run();
    }

    @async static function run():Void {
        var value = compute();
        trace("Value = " + @await value);
    }

    @async static function compute():Int {
        @await Async.sleep(0.1);
        return 1234;
    }
}
```

---

## Requirements

-   Haxe 4.2+
