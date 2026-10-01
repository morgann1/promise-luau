<h1 align="center">
  🤝
  <br>
  Roblox Lua Promise
</h1>

<div align="center">

  [![Docs](.github/assets/link-docs.svg)](https://morgann1.github.io/promise-luau/)
  [![Changelog](.github/assets/link-changelog.svg)](https://morgann1.github.io/promise-luau/changelog)
</div>

<p>An implementation of <code>Promise</code> similar to Promise/A+.</p>

<!--moonwave-hide-before-this-line-->


## Why you should use Promises

The way Roblox models asynchronous operations by default is by yielding (stopping) the thread and then resuming it when the future value is available. This model is not ideal because:

- Functions you call can yield without warning, or only yield sometimes, leading to unpredictable and surprising results. Accidentally yielding the thread is the source of a large class of bugs and race conditions that Roblox developers run into.
- It is difficult to deal with running multiple asynchronous operations concurrently and then retrieve all of their values at the end without extraneous machinery.
- When an asynchronous operation fails or an error is encountered, Lua functions usually either raise an error or return a success value followed by the actual value. Both of these methods lead to repeating the same tired patterns many times over for checking if the operation was successful.
- Yielding lacks easy access to introspection and the ability to cancel an operation if the value is no longer needed.

This Promise implementation attempts to satisfy these traits:

* An object that represents a unit of asynchronous work
* Composability
* Predictable timing

## Types

`Promise.new`, `Promise.resolve`, `Promise.fromEvent`, and `Promise.delay` return a `Promise<T...>`. Handlers passed to its methods get typed parameters, and `expect` returns `T...`. Methods that keep the values, such as `tap`, `finally`, `timeout`, and `now`, keep `T...`.

`andThen`, `catch`, and the list functions such as `Promise.all` return an `AnyPromise`. Luau can't type an alias that refers to itself with different arguments, and a handler can return a Promise that gets chained onto. Cast to type the result again:

```luau
local Promise = require(path.to.Promise)

local function fetchName(userId: number): Promise.Promise<string>
	return fetchUser(userId):andThen(function(user)
		return user.name
	end) :: Promise.Promise<string>
end
```

`await` returns `(boolean, ...any)`, since a rejection resolves with the error instead. Use `expect` for typed values, or annotate: `local ok, name: string = fetchName(1):await()`.

## Development

Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit), then the dev packages:

```bash
rokit install
lute scripts/install.luau
```

| Command | Purpose |
| --- | --- |
| `lute scripts/test.luau` | Runs the Jest specs in Roblox Studio through run-in-roblox. Studio must be installed and signed in. |
| `lute scripts/analyze.luau` | Type-checks `src` and `scripts` with luau-lsp. |
| `lute scripts/lint.luau` | Runs Selene and StyLua. |

Specs live next to the code as `*.spec.luau`.
