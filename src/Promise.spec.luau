--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
const Promise = require(script.Parent)

const describe = JestGlobals.describe
const expect = JestGlobals.expect
const it = JestGlobals.it

Promise.TEST = true

const timeDilationFactor = 1 / 50

const function advanceTime(t: number?): number
	return task.wait(if t ~= nil then t * timeDilationFactor else nil)
end

const oldDelay = Promise.delay
Promise.delay = function(t: number)
	return oldDelay(t * timeDilationFactor)
end

const function pack(...: any): (number, { any })
	return select("#", ...), { ... }
end

-- The internal state these specs check, which the public `Promise` type hides.
type Internals = {
	_status: Promise.Status,
	_values: { any },
	_parent: any,
	_consumers: { [any]: true? },
	_unwrap: (self: Internals) -> (boolean, ...any),
}

const function internals(promise: any): Internals
	return promise
end

-- Reads a settled promise's result without yielding.
const function unwrap(promise: any): (boolean, ...any)
	return internals(promise):_unwrap()
end

describe("Promise.Status", function()
	it("should error if indexing nil value", function()
		expect(function()
			const _ = (Promise.Status :: any).wrong
		end).toThrow()
	end)
end)

describe("Unhandled rejection signal", function()
	-- Using real time instead of our time simulation breaks this test because the tests run
	-- concurrently.
	it.skip("should call unhandled rejection callbacks", function()
		const badPromise = Promise.new(function(_resolve, reject)
			reject(1, 2)
		end)

		local callCount = 0

		const function callback(promise, rejectionA, rejectionB)
			callCount += 1

			expect(promise).toBe(badPromise)
			expect(rejectionA).toBe(1)
			expect(rejectionB).toBe(2)
		end

		const unregister = Promise.onUnhandledRejection(callback)

		advanceTime()

		expect(callCount).toBe(1)

		unregister()

		Promise.new(function(_resolve, reject)
			reject(3, 4)
		end)

		advanceTime()

		expect(callCount).toBe(1)
	end)
end)

describe("Promise.new", function()
	it("should instantiate with a callback", function()
		const promise = Promise.new(function() end)

		expect(promise).toBeDefined()
	end)

	it("should invoke the given callback with resolve and reject", function()
		local callCount = 0
		local resolveArg
		local rejectArg

		const promise = Promise.new(function(resolve, reject)
			callCount += 1
			resolveArg = resolve
			rejectArg = reject
		end)

		expect(callCount).toBe(1)
		expect(type(resolveArg)).toBe("function")
		expect(type(rejectArg)).toBe("function")
		expect(promise:getStatus()).toBe(Promise.Status.Started)
	end)

	it("should resolve promises on resolve()", function()
		local callCount = 0

		const promise = Promise.new(function(resolve)
			callCount += 1
			resolve()
		end)

		expect(callCount).toBe(1)
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
	end)

	it("should reject promises on reject()", function()
		local callCount = 0

		const promise = Promise.new(function(_resolve, reject)
			callCount += 1
			reject()
		end)

		expect(callCount).toBe(1)
		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
	end)

	it("should reject on error in callback", function()
		local callCount = 0

		const promise = Promise.new(function()
			callCount += 1
			error("hahah")
		end)

		expect(callCount).toBe(1)
		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(tostring(internals(promise)._values[1])).toContain("hahah")

		-- Loosely check for the pieces of the stack trace we expect
		expect(tostring(internals(promise)._values[1])).toContain("Promise.spec")
		expect(tostring(internals(promise)._values[1])).toContain("runExecutor")
	end)

	it("should work with C functions", function()
		expect(function()
			Promise.new(os.clock :: any):andThen(os.clock :: any)
		end).never.toThrow()
	end)

	it("should have a nice tostring", function()
		expect(tostring(Promise.resolve())).toBe("Promise(Resolved)")
	end)

	it("should allow yielding", function()
		const bindable = Instance.new("BindableEvent")
		const promise = Promise.new(function(resolve)
			bindable.Event:Wait()
			resolve(5)
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		bindable:Fire()
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe(5)
	end)

	it("should preserve stack traces of resolve-chained promises", function()
		const function nestedCall(text)
			error(text)
		end

		const promise = Promise.new(function(resolve)
			resolve(Promise.new(function()
				nestedCall("sample text")
			end))
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)

		const trace = tostring(internals(promise)._values[1])
		expect(trace).toContain("sample text")
		expect(trace).toContain("runExecutor")
		expect(trace).toContain("Promise.spec")
		expect(trace).toContain(
			"...Rejected because it was chained to the following Promise, which encountered an error:"
		)
	end)

	it("should report errors from Promises with _error (< v2)", function()
		const oldPromise: any = Promise.reject()
		oldPromise._error = "Sample error"

		const newPromise = Promise.resolve():andThenReturn(oldPromise)

		expect(newPromise:getStatus()).toBe(Promise.Status.Rejected)

		const trace = tostring(internals(newPromise)._values[1])
		expect(trace).toContain("Sample error")
		expect(trace).toContain(
			"...Rejected because it was chained to the following Promise, which encountered an error:"
		)
		expect(trace).toContain("[No stack trace available")
	end)

	it("should allow callable tables", function()
		const promise = Promise.new(setmetatable({}, {
			__call = function(_, resolve)
				resolve(1)
			end,
		}) :: any)

		local called = false
		promise:andThen(setmetatable({}, {
			__call = function(_, var)
				expect(var).toBe(1)
				called = true
			end,
		}) :: any)

		expect(called).toBe(true)
	end)

	it.skip("should close the thread after resolve", function()
		local count = 0
		Promise.new(function(resolve)
			count += 1
			resolve()
			Promise.delay(1):await()
			count += 1
		end)

		task.wait(1)

		expect(count).toBe(1)
	end)
end)

describe("Promise.defer", function()
	it("should execute after the time event", function()
		local callCount = 0
		const promise = Promise.defer(function(...)
			const resolve, reject, onCancel, nothing = ...

			expect(type(resolve)).toBe("function")
			expect(type(reject)).toBe("function")
			expect(type(onCancel)).toBe("function")
			expect(type(nothing)).toBe("nil")

			callCount += 1

			resolve("foo")
		end)

		expect(callCount).toBe(0)
		expect(promise:getStatus()).toBe(Promise.Status.Started)

		advanceTime()
		expect(callCount).toBe(1)
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)

		advanceTime()
		expect(callCount).toBe(1)
	end)
end)

describe("Promise.delay", function()
	it("should schedule promise resolution", function()
		const promise = Promise.delay(1)

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		advanceTime()
		expect(promise:getStatus()).toBe(Promise.Status.Started)

		advanceTime(1)
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
	end)

	it("should allow for delays to be cancelled", function()
		const promise = Promise.delay(2)

		Promise.delay(1):andThen(function()
			promise:cancel()
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		advanceTime()
		expect(promise:getStatus()).toBe(Promise.Status.Started)
		advanceTime(1)
		expect(promise:getStatus()).toBe(Promise.Status.Cancelled)
		advanceTime(1)
	end)
end)

describe("Promise.resolve", function()
	it("should immediately resolve with a value", function()
		const promise = Promise.resolve(5, 6)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe(5)
		expect(internals(promise)._values[2]).toBe(6)
	end)

	it("should chain onto passed promises", function()
		const promise = Promise.resolve(Promise.new(function(_, reject)
			reject(7)
		end))

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe(7)
	end)
end)

describe("Promise.reject", function()
	it("should immediately reject with a value", function()
		const promise = Promise.reject(6, 7)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe(6)
		expect(internals(promise)._values[2]).toBe(7)
	end)

	it("should pass a promise as-is as an error", function()
		const innerPromise = Promise.new(function(resolve)
			resolve(6)
		end)

		const promise = Promise.reject(innerPromise)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe(innerPromise)
	end)
end)

describe("Promise:andThen", function()
	it("should allow yielding", function()
		const bindable = Instance.new("BindableEvent")
		const promise = Promise.resolve():andThen(function()
			bindable.Event:Wait()
			return 5
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		bindable:Fire()
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe(5)
	end)

	it("should run andThens on a new thread", function()
		const bindable = Instance.new("BindableEvent")

		local resolve: (...any) -> ()
		const parentPromise = Promise.new(function(_resolve)
			resolve = _resolve
		end)

		const deadlockedPromise = parentPromise:andThen(function()
			bindable.Event:Wait()
			return 5
		end)

		const successfulPromise = parentPromise:andThen(function()
			return "foo"
		end)

		expect(parentPromise:getStatus()).toBe(Promise.Status.Started)
		resolve()
		expect(successfulPromise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(successfulPromise)._values[1]).toBe("foo")
		expect(deadlockedPromise:getStatus()).toBe(Promise.Status.Started)
	end)

	it("should chain onto resolved promises", function()
		local args: { any }
		local argsLength: number
		local callCount = 0
		local badCallCount = 0

		const promise = Promise.resolve(5)

		const chained = promise:andThen(function(...)
			argsLength, args = pack(...)
			callCount += 1
		end, function()
			badCallCount += 1
		end)

		expect(badCallCount).toBe(0)

		expect(callCount).toBe(1)
		expect(argsLength).toBe(1)
		expect(args[1]).toBe(5)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe(5)

		expect(chained).never.toBe(promise)
		expect(chained:getStatus()).toBe(Promise.Status.Resolved)
		expect(#internals(chained)._values).toBe(0)
	end)

	it("should chain onto rejected promises", function()
		local args: { any }
		local argsLength: number
		local callCount = 0
		local badCallCount = 0

		const promise = Promise.reject(5)

		const chained = promise:andThen(function()
			badCallCount += 1
		end, function(...)
			argsLength, args = pack(...)
			callCount += 1
		end)

		expect(badCallCount).toBe(0)

		expect(callCount).toBe(1)
		expect(argsLength).toBe(1)
		expect(args[1]).toBe(5)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe(5)

		expect(chained).never.toBe(promise)
		expect(chained:getStatus()).toBe(Promise.Status.Resolved)
		expect(#internals(chained)._values).toBe(0)
	end)

	it("should reject on error in callback", function()
		local callCount = 0

		const promise = Promise.resolve(1):andThen(function()
			callCount += 1
			error("hahah")
		end)

		expect(callCount).toBe(1)
		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(tostring(internals(promise)._values[1])).toContain("hahah")

		-- Loosely check for the pieces of the stack trace we expect
		expect(tostring(internals(promise)._values[1])).toContain("Promise.spec")
		expect(tostring(internals(promise)._values[1])).toContain("runExecutor")
	end)

	it("should chain onto asynchronously resolved promises", function()
		local args: { any }
		local argsLength: number
		local callCount = 0
		local badCallCount = 0

		local startResolution: (...any) -> ()
		const promise = Promise.new(function(resolve)
			startResolution = resolve
		end)

		const chained = promise:andThen(function(...)
			args = { ... }
			argsLength = select("#", ...)
			callCount += 1
		end, function()
			badCallCount += 1
		end)

		expect(callCount).toBe(0)
		expect(badCallCount).toBe(0)

		startResolution(6)

		expect(badCallCount).toBe(0)

		expect(callCount).toBe(1)
		expect(argsLength).toBe(1)
		expect(args[1]).toBe(6)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe(6)

		expect(chained).never.toBe(promise)
		expect(chained:getStatus()).toBe(Promise.Status.Resolved)
		expect(#internals(chained)._values).toBe(0)
	end)

	it("should chain onto asynchronously rejected promises", function()
		local args: { any }
		local argsLength: number
		local callCount = 0
		local badCallCount = 0

		local startResolution: (...any) -> ()
		const promise = Promise.new(function(_, reject)
			startResolution = reject
		end)

		const chained = promise:andThen(function()
			badCallCount += 1
		end, function(...)
			args = { ... }
			argsLength = select("#", ...)
			callCount += 1
		end)

		expect(callCount).toBe(0)
		expect(badCallCount).toBe(0)

		startResolution(6)

		expect(badCallCount).toBe(0)

		expect(callCount).toBe(1)
		expect(argsLength).toBe(1)
		expect(args[1]).toBe(6)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe(6)

		expect(chained).never.toBe(promise)
		expect(chained:getStatus()).toBe(Promise.Status.Resolved)
		expect(#internals(chained)._values).toBe(0)
	end)

	it("should propagate errors through multiple levels", function()
		local x, y, z
		Promise.new(function(_resolve, reject)
			reject(1, 2, 3)
		end)
			:andThen(function() end)
			:catch(function(a, b, c)
				x, y, z = a, b, c
			end)

		expect(x).toBe(1)
		expect(y).toBe(2)
		expect(z).toBe(3)
	end)

	it("should not call queued callbacks from a cancelled sub-promise", function()
		local resolve: (...any) -> ()
		local count = 0

		const root = Promise.new(function(r)
			resolve = r
		end)

		root:andThen(function()
			count += 1
		end)

		root:andThen(function()
			count += 1
		end):cancel()

		resolve("foo")

		expect(count).toBe(1)
	end)
end)

describe("Promise:cancel", function()
	it("should mark promises as cancelled and not resolve or reject them", function()
		local callCount = 0
		local finallyCallCount = 0
		const promise = Promise.new(function() end)
			:andThen(function()
				callCount += 1
			end)
			:finally(function()
				finallyCallCount += 1
			end)

		promise:cancel()
		promise:cancel() -- Twice to check call counts

		expect(callCount).toBe(0)
		expect(finallyCallCount).toBe(1)
		expect(promise:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should call the cancellation hook once", function()
		local callCount = 0

		const promise = Promise.new(function(_resolve, _reject, onCancel)
			onCancel(function()
				callCount += 1
			end)
		end)

		promise:cancel()
		promise:cancel() -- Twice to check call count

		expect(callCount).toBe(1)
	end)

	it("should propagate cancellations", function()
		const promise = Promise.new(function() end)

		const consumer1 = promise:andThen()
		const consumer2 = promise:andThen()

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(consumer1:getStatus()).toBe(Promise.Status.Started)
		expect(consumer2:getStatus()).toBe(Promise.Status.Started)

		consumer1:cancel()

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(consumer1:getStatus()).toBe(Promise.Status.Cancelled)
		expect(consumer2:getStatus()).toBe(Promise.Status.Started)

		consumer2:cancel()

		expect(promise:getStatus()).toBe(Promise.Status.Cancelled)
		expect(consumer1:getStatus()).toBe(Promise.Status.Cancelled)
		expect(consumer2:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should affect downstream promises", function()
		const promise = Promise.new(function() end)
		const consumer = promise:andThen()

		promise:cancel()

		expect(consumer:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should track consumers", function()
		const pending = Promise.new(function() end)
		const p0 = Promise.resolve()
		const p1 = p0:andThen(function()
			return pending
		end)
		const p2 = Promise.new(function(resolve)
			resolve(p1)
		end)
		const p3 = p2:andThen(function() end)

		expect(internals(p1)._parent).never.toBe(p0)
		expect(internals(p2)._parent).never.toBe(p1)
		expect(internals(p2)._consumers[p3]).toBe(true)
		expect(internals(p3)._parent).toBe(p2)
	end)

	it("should cancel resolved pending promises", function()
		const p1 = Promise.new(function() end)

		const p2 = Promise.new(function(resolve)
			resolve(p1)
		end):finally(function() end)

		p2:cancel()

		expect(internals(p1)._status).toBe(Promise.Status.Cancelled)
		expect(internals(p2)._status).toBe(Promise.Status.Cancelled)
	end)

	it("should close the promise thread", function()
		local count = 0
		const promise = Promise.new(function()
			count += 1
			Promise.delay(1):await()
			count += 1
		end)

		promise:cancel()
		advanceTime(2)

		expect(count).toBe(1)
	end)
end)

describe("Promise:finally", function()
	it("should be called upon resolve, reject, or cancel", function()
		local callCount = 0

		const function finally()
			callCount += 1
		end

		-- Resolved promise
		Promise.new(function(resolve)
			resolve()
		end):finally(finally)

		-- Chained promise
		Promise.resolve():andThen(function() end):finally(finally):finally(finally)

		-- Rejected promise
		Promise.reject():finally(finally)

		const cancelledPromise = Promise.new(function() end):finally(finally)
		cancelledPromise:cancel()

		expect(callCount).toBe(5)
	end)

	it("should not forward return values", function()
		local value

		Promise.resolve(2)
			:finally(function()
				return 1
			end)
			:andThen(function(v)
				value = v
			end)

		expect(value).toBe(2)
	end)

	it("should not consume rejections", function()
		local catchRan = false
		local thenRan = false
		Promise.reject(5)
			:finally(function()
				return 42
			end)
			:andThen(function()
				thenRan = true
			end)
			:catch(function(value)
				catchRan = true
				expect(value).toBe(5)
			end)

		expect(catchRan).toBe(true)
		expect(thenRan).toBe(false)
	end)

	it("should wait for returned promises", function()
		local resolve: (...any) -> ()
		const promise = Promise.reject("foo"):finally(function()
			return Promise.new(function(r)
				resolve = r
			end)
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		resolve()

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		const _, value = unwrap(promise)
		expect(value).toBe("foo")
	end)

	it("should reject with a returned rejected promise's value", function()
		local reject: (...any) -> ()
		const promise = Promise.reject("foo"):finally(function()
			return Promise.new(function(_, r)
				reject = r
			end)
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		reject("bar")

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		const _, value = unwrap(promise)
		expect(value).toBe("bar")
	end)

	it("should reject when handler errors", function()
		const errorValue = {}
		const promise = Promise.reject("bar"):finally(function()
			error(errorValue)
		end)

		const ok, value = unwrap(promise)

		expect(ok).toBe(false)
		expect(value).toBe(errorValue)
	end)

	it("should not prevent cancellation", function()
		const promise = Promise.new(function() end)

		local finallyRan = false
		promise:finally(function()
			finallyRan = true
		end)

		const consumer = promise:andThen(function() end)

		consumer:cancel()

		expect(promise:getStatus()).toBe(Promise.Status.Cancelled)
		expect(finallyRan).toBe(true)
	end)

	it("should propagate cancellation downwards", function()
		local finallyRan = false
		const andThenRan = false
		const root = Promise.new(function() end)

		const consumer = root:finally(function()
			finallyRan = true
		end)

		root:cancel()

		expect(root:getStatus()).toBe(Promise.Status.Cancelled)
		expect(consumer:getStatus()).toBe(Promise.Status.Cancelled)

		expect(finallyRan).toBe(true)
		expect(andThenRan).toBe(false)
	end)

	it("should propagate cancellation upwards", function()
		local finallyRan = false
		const andThenRan = false
		const root = Promise.new(function() end)

		const consumer = root:finally(function()
			finallyRan = true
		end)

		consumer:cancel()

		expect(root:getStatus()).toBe(Promise.Status.Cancelled)
		expect(consumer:getStatus()).toBe(Promise.Status.Cancelled)

		expect(finallyRan).toBe(true)
		expect(andThenRan).toBe(false)
	end)

	it("should cancel returned promise if cancelled", function()
		const internal = Promise.new(function() end)

		const promise = Promise.resolve():finally(function()
			return internal
		end)

		promise:cancel()

		expect(internal:getStatus()).toBe(Promise.Status.Cancelled)
	end)
end)

describe("Promise.all", function()
	it("should error if given something other than a table", function()
		expect(function()
			Promise.all(1 :: any)
		end).toThrow()
	end)

	it("should resolve instantly with an empty table if given no promises", function()
		const promise = Promise.all({})
		const success, value = unwrap(promise)

		expect(success).toBe(true)
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(type(value)).toBe("table")
		expect(value).toEqual({})
	end)

	it("should error if given non-promise values", function()
		expect(function()
			Promise.all({ {}, {}, {} } :: any)
		end).toThrow()
	end)

	it("should wait for all promises to be resolved and return their values", function()
		const resolveFunctions: { { any } } = {}

		const testValuesLength, testValues = pack(1, "A string", nil, false)

		const promises = {}

		for i = 1, testValuesLength do
			promises[i] = Promise.new(function(resolve)
				resolveFunctions[i] = { resolve, testValues[i] }
			end)
		end

		const combinedPromise = Promise.all(promises)

		for _, resolve in ipairs(resolveFunctions) do
			expect(combinedPromise:getStatus()).toBe(Promise.Status.Started)
			resolve[1](resolve[2])
		end

		const resultLength, result = pack(unwrap(combinedPromise))
		const success, resolved = table.unpack(result, 1, resultLength)

		expect(resultLength).toBe(2)
		expect(success).toBe(true)
		expect(type(resolved)).toBe("table")
		expect(#resolved).toBe(#promises)

		for i = 1, testValuesLength do
			expect(resolved[i]).toBe(testValues[i])
		end
	end)

	it("should reject if any individual promise rejected", function()
		local rejectA: (...any) -> ()
		local resolveB: (...any) -> ()

		const a = Promise.new(function(_, reject)
			rejectA = reject
		end)

		const b = Promise.new(function(resolve)
			resolveB = resolve
		end)

		const combinedPromise = Promise.all({ a, b })

		expect(combinedPromise:getStatus()).toBe(Promise.Status.Started)

		rejectA("baz", "qux")
		resolveB("foo", "bar")

		const resultLength, result = pack(unwrap(combinedPromise))
		const success, first, second = table.unpack(result, 1, resultLength)

		expect(resultLength).toBe(3)
		expect(success).toBe(false)
		expect(first).toBe("baz")
		expect(second).toBe("qux")
		expect(b:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should not resolve if resolved after rejecting", function()
		local rejectA: (...any) -> ()
		local resolveB: (...any) -> ()

		const a = Promise.new(function(_, reject)
			rejectA = reject
		end)

		const b = Promise.new(function(resolve)
			resolveB = resolve
		end)

		const combinedPromise = Promise.all({ a, b })

		expect(combinedPromise:getStatus()).toBe(Promise.Status.Started)

		rejectA("baz", "qux")
		resolveB("foo", "bar")

		const resultLength, result = pack(unwrap(combinedPromise))
		const success, first, second = table.unpack(result, 1, resultLength)

		expect(resultLength).toBe(3)
		expect(success).toBe(false)
		expect(first).toBe("baz")
		expect(second).toBe("qux")
	end)

	it("should only reject once", function()
		local rejectA: (...any) -> ()
		local rejectB: (...any) -> ()

		const a = Promise.new(function(_, reject)
			rejectA = reject
		end)

		const b = Promise.new(function(_, reject)
			rejectB = reject
		end)

		const combinedPromise = Promise.all({ a, b })

		expect(combinedPromise:getStatus()).toBe(Promise.Status.Started)

		rejectA("foo", "bar")

		expect(combinedPromise:getStatus()).toBe(Promise.Status.Rejected)

		rejectB("baz", "qux")

		const resultLength, result = pack(unwrap(combinedPromise))
		const success, first, second = table.unpack(result, 1, resultLength)

		expect(resultLength).toBe(3)
		expect(success).toBe(false)
		expect(first).toBe("foo")
		expect(second).toBe("bar")
	end)

	it("should error if a non-array table is passed in", function()
		const ok, err = pcall(function()
			Promise.all(Promise.new(function() end) :: any)
		end)

		expect(ok).toBe(false)
		expect(err).toContain("Non-promise")
	end)

	it("should cancel pending promises if one rejects", function()
		const p = Promise.new(function() end)
		expect(Promise.all({
			Promise.resolve(),
			Promise.reject(),
			p,
		}):getStatus()).toBe(Promise.Status.Rejected)
		expect(p:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should cancel promises if it is cancelled", function()
		const p = Promise.new(function() end)
		p:andThen(function() end)

		const promises = {
			Promise.new(function() end),
			Promise.new(function() end),
			p,
		}

		Promise.all(promises):cancel()

		expect(promises[1]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[2]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[3]:getStatus()).toBe(Promise.Status.Started)
	end)
end)

describe("Promise.fold", function()
	it("should return the initial value in a promise when the list is empty", function()
		const initialValue = {}
		const result = Promise.fold({}, function()
			error("should not be called")
		end, initialValue)

		expect(Promise.is(result)).toBe(true)
		expect(result:getStatus()).toBe(Promise.Status.Resolved)
		expect(result:expect()).toBe(initialValue)
	end)

	it("should accept promises in the list", function()
		local resolve: (...any) -> ()

		const sum = Promise.fold({ Promise.new(function(r)
			resolve = r
		end), 2, 3 }, function(total, element)
			return total + element
		end, 0)

		resolve(1)

		expect(Promise.is(sum)).toBe(true)
		expect(sum:getStatus()).toBe(Promise.Status.Resolved)
		expect(sum:expect()).toBe(6)
	end)

	it("should always return a promise even if the list or reducer don't use them", function()
		const sum = Promise.fold({ 1, 2, 3 }, function(total, element, index)
			if index == 2 then
				return Promise.delay(1):andThenReturn(total + element)
			else
				return total + element
			end
		end, 0)
		expect(Promise.is(sum)).toBe(true)
		expect(sum:getStatus()).toBe(Promise.Status.Started)
		advanceTime(2)
		expect(sum:getStatus()).toBe(Promise.Status.Resolved)
		expect(sum:expect()).toBe(6)
	end)

	it("should return the first rejected promise", function()
		const errorMessage = "foo"
		const sum = Promise.fold({ 1, 2, 3 }, function(total, element, index)
			if index == 2 then
				return Promise.reject(errorMessage)
			else
				return total + element
			end
		end, 0)
		expect(Promise.is(sum)).toBe(true)
		const status, rejection = sum:awaitStatus()
		expect(status).toBe(Promise.Status.Rejected)
		expect(rejection).toBe(errorMessage)
	end)

	it("should return the first canceled promise", function()
		local secondPromise: Promise.AnyPromise
		const sum = Promise.fold({ 1, 2, 3 }, function(total, element, index)
			if index == 1 then
				return total + element
			elseif index == 2 then
				secondPromise = Promise.delay(1):andThenReturn(total + element)
				return secondPromise
			else
				error("this should not run if the promise is cancelled")
			end
		end, 0)
		expect(Promise.is(sum)).toBe(true)
		expect(sum:getStatus()).toBe(Promise.Status.Started)
		secondPromise:cancel()
		expect(sum:getStatus()).toBe(Promise.Status.Cancelled)
	end)
end)

describe("Promise.race", function()
	it("should resolve with the first settled value", function()
		const promise = Promise.race({
			Promise.resolve(1),
			Promise.resolve(2),
		}):andThen(function(value)
			expect(value).toBe(1)
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
	end)

	it("should cancel other promises", function()
		const pending = Promise.new(function() end)
		pending:andThen(function() end)
		const promises = {
			pending,
			Promise.new(function() end),
			Promise.new(function(resolve)
				resolve(2)
			end),
		}

		const promise = Promise.race(promises)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe(2)
		expect(promises[1]:getStatus()).toBe(Promise.Status.Started)
		expect(promises[2]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[3]:getStatus()).toBe(Promise.Status.Resolved)

		const p = Promise.new(function() end)
		expect(Promise.race({
			Promise.reject(),
			Promise.resolve(),
			p,
		}):getStatus()).toBe(Promise.Status.Rejected)
		expect(p:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should error if a non-array table is passed in", function()
		const ok, err = pcall(function()
			Promise.race(Promise.new(function() end) :: any)
		end)

		expect(ok).toBe(false)
		expect(err).toContain("Non-promise")
	end)

	it("should cancel promises if it is cancelled", function()
		const p = Promise.new(function() end)
		p:andThen(function() end)

		const promises = {
			Promise.new(function() end),
			Promise.new(function() end),
			p,
		}

		Promise.race(promises):cancel()

		expect(promises[1]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[2]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[3]:getStatus()).toBe(Promise.Status.Started)
	end)
end)

describe("Promise.promisify", function()
	it("should wrap functions", function()
		const function test(n: number): number
			return n + 1
		end

		const promisified = Promise.promisify(test)
		const promise = promisified(1)
		const success, result = unwrap(promise)

		expect(success).toBe(true)
		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(result).toBe(2)
	end)

	it("should catch errors after a yield", function()
		const bindable = Instance.new("BindableEvent")
		const test = Promise.promisify(function()
			bindable.Event:Wait()
			error("errortext")
		end)

		const promise = test()

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		bindable:Fire()
		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(tostring(internals(promise)._values[1])).toContain("errortext")
	end)
end)

describe("Promise.tap", function()
	it("should thread through values", function()
		local first, second

		Promise.resolve(1)
			:andThen(function(v)
				return v + 1
			end)
			:tap(function(v)
				first = v
				return v + 1
			end)
			:andThen(function(v)
				second = v
			end)

		expect(first).toBe(2)
		expect(second).toBe(2)
	end)

	it("should chain onto promises", function()
		local resolveInner: (...any) -> ()
		local finalValue

		const promise = Promise.resolve(1)
			:tap(function()
				return Promise.new(function(resolve)
					resolveInner = resolve
				end)
			end)
			:andThen(function(v)
				finalValue = v
			end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(finalValue).toBeNil()

		resolveInner(1)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(finalValue).toBe(1)
	end)
end)

describe("Promise.try", function()
	it("should catch synchronous errors", function()
		local errorText
		Promise.try(function()
			error("errortext")
		end):catch(function(e)
			errorText = tostring(e)
		end)

		expect(errorText).toContain("errortext")
	end)

	it("should reject with error objects", function()
		const object = {}
		const success, value = unwrap(Promise.try(function()
			error(object)
		end))

		expect(success).toBe(false)
		expect(value).toBe(object)
	end)

	it("should catch asynchronous errors", function()
		const bindable = Instance.new("BindableEvent")
		const promise = Promise.try(function()
			bindable.Event:Wait()
			error("errortext")
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		bindable:Fire()
		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(tostring(internals(promise)._values[1])).toContain("errortext")
	end)
end)

describe("Promise:andThenReturn", function()
	it("should return the given values", function()
		local value1, value2

		Promise.resolve():andThenReturn(1, 2):andThen(function(one, two)
			value1 = one
			value2 = two
		end)

		expect(value1).toBe(1)
		expect(value2).toBe(2)
	end)
end)

describe("Promise:andThenCall", function()
	it("should call the given function with arguments", function()
		local value1, value2
		Promise.resolve():andThenCall(function(a, b)
			value1 = a
			value2 = b
		end, 3, 4)

		expect(value1).toBe(3)
		expect(value2).toBe(4)
	end)
end)

describe("Promise.some", function()
	it("should resolve once the goal is reached", function()
		const p = Promise.some({
			Promise.resolve(1),
			Promise.reject(),
			Promise.resolve(2),
		}, 2)
		expect(p:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(p)._values[1][1]).toBe(1)
		expect(internals(p)._values[1][2]).toBe(2)
	end)

	it("should error if the goal can't be reached", function()
		expect(Promise.some({
			Promise.resolve(),
			Promise.reject(),
		}, 2):getStatus()).toBe(Promise.Status.Rejected)

		local reject: (...any) -> ()
		const p = Promise.some({
			Promise.resolve(),
			Promise.new(function(_, r)
				reject = r
			end),
		}, 2)

		expect(p:getStatus()).toBe(Promise.Status.Started)
		reject("foo")
		expect(p:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(p)._values[1]).toBe("foo")
	end)

	it("should cancel pending Promises once the goal is reached", function()
		local resolve: (...any) -> ()
		const pending1 = Promise.new(function() end)
		const pending2 = Promise.new(function(r)
			resolve = r
		end)

		const some = Promise.some({
			pending1,
			pending2,
			Promise.resolve(),
		}, 2)

		expect(some:getStatus()).toBe(Promise.Status.Started)
		expect(pending1:getStatus()).toBe(Promise.Status.Started)
		expect(pending2:getStatus()).toBe(Promise.Status.Started)

		resolve()

		expect(some:getStatus()).toBe(Promise.Status.Resolved)
		expect(pending1:getStatus()).toBe(Promise.Status.Cancelled)
		expect(pending2:getStatus()).toBe(Promise.Status.Resolved)
	end)

	it("should error if passed a non-number", function()
		expect(function()
			Promise.some({}, "non-number" :: any)
		end).toThrow()
	end)

	it("should return an empty array if amount is 0", function()
		const p = Promise.some({
			Promise.resolve(2),
		}, 0)

		expect(p:getStatus()).toBe(Promise.Status.Resolved)
		expect(#internals(p)._values[1]).toBe(0)
	end)

	it("should not return extra values", function()
		const p = Promise.some({
			Promise.resolve(1),
			Promise.resolve(2),
			Promise.resolve(3),
			Promise.resolve(4),
		}, 2)

		expect(p:getStatus()).toBe(Promise.Status.Resolved)
		expect(#internals(p)._values[1]).toBe(2)
		expect(internals(p)._values[1][1]).toBe(1)
		expect(internals(p)._values[1][2]).toBe(2)
	end)

	it("should cancel promises if it is cancelled", function()
		const p = Promise.new(function() end)
		p:andThen(function() end)

		const promises = {
			Promise.new(function() end),
			Promise.new(function() end),
			p,
		}

		Promise.some(promises, 3):cancel()

		expect(promises[1]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[2]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[3]:getStatus()).toBe(Promise.Status.Started)
	end)

	describe("Promise.any", function()
		it("should return the value directly", function()
			const p = Promise.any({
				Promise.reject(),
				Promise.reject(),
				Promise.resolve(1),
			})

			expect(p:getStatus()).toBe(Promise.Status.Resolved)
			expect(internals(p)._values[1]).toBe(1)
		end)

		it("should error if all are rejected", function()
			expect(Promise.any({
				Promise.reject(),
				Promise.reject(),
				Promise.reject(),
			}):getStatus()).toBe(Promise.Status.Rejected)
		end)
	end)
end)

describe("Promise.allSettled", function()
	it("should resolve with an array of PromiseStatuses", function()
		local reject: (...any) -> ()
		const p = Promise.allSettled({
			Promise.resolve(),
			Promise.reject(),
			Promise.resolve(),
			Promise.new(function(_, r)
				reject = r
			end),
		})

		expect(p:getStatus()).toBe(Promise.Status.Started)
		reject()
		expect(p:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(p)._values[1][1]).toBe(Promise.Status.Resolved)
		expect(internals(p)._values[1][2]).toBe(Promise.Status.Rejected)
		expect(internals(p)._values[1][3]).toBe(Promise.Status.Resolved)
		expect(internals(p)._values[1][4]).toBe(Promise.Status.Rejected)
	end)

	it("should cancel promises if it is cancelled", function()
		const p = Promise.new(function() end)
		p:andThen(function() end)

		const promises = {
			Promise.new(function() end),
			Promise.new(function() end),
			p,
		}

		Promise.allSettled(promises):cancel()

		expect(promises[1]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[2]:getStatus()).toBe(Promise.Status.Cancelled)
		expect(promises[3]:getStatus()).toBe(Promise.Status.Started)
	end)
end)

describe("Promise:await", function()
	it("should return the correct values", function()
		const promise = Promise.resolve(5, 6, nil, 7)

		const a, b, c, d, e = promise:await()

		expect(a).toBe(true)
		expect(b).toBe(5)
		expect(c).toBe(6)
		expect(d).toBe(nil)
		expect(e).toBe(7)
	end)

	it("should work if yielding is needed", function()
		local ran = false
		task.spawn(function()
			const _, actualTime = Promise.delay(1):await()
			expect(type(actualTime)).toBe("number")
			ran = true
		end)

		advanceTime(2)
		expect(ran).toBe(true)
	end)
end)

describe("Promise:expect", function()
	it("should throw the correct values", function()
		const rejectionValue = {}
		const promise = Promise.reject(rejectionValue)

		const success, value = pcall(function()
			promise:expect()
		end)

		expect(success).toBe(false)
		expect(value).toBe(rejectionValue)
	end)
end)

describe("Promise:now", function()
	it("should resolve if the Promise is resolved", function()
		const success, value = unwrap(Promise.resolve("foo"):now())

		expect(success).toBe(true)
		expect(value).toBe("foo")
	end)

	it("should reject if the Promise is not resolved", function()
		const success, value = unwrap(Promise.new(function() end):now())

		expect(success).toBe(false)
		expect(Promise.Error.isKind(value, "NotResolvedInTime")).toBe(true)
	end)

	it("should reject with a custom rejection value", function()
		const success, value = unwrap(Promise.new(function() end):now("foo"))

		expect(success).toBe(false)
		expect(value).toBe("foo")
	end)
end)

describe("Promise.each", function()
	it("should iterate", function()
		const ok, result = unwrap(Promise.each({
			"foo",
			"bar",
			"baz",
			"qux",
		}, function(...)
			return { ... }
		end))

		expect(ok).toBe(true)
		expect(result[1][1]).toBe("foo")
		expect(result[1][2]).toBe(1)
		expect(result[2][1]).toBe("bar")
		expect(result[2][2]).toBe(2)
		expect(result[3][1]).toBe("baz")
		expect(result[3][2]).toBe(3)
		expect(result[4][1]).toBe("qux")
		expect(result[4][2]).toBe(4)
	end)

	it("should iterate serially", function()
		const resolves: { () -> () } = {}
		const callCounts: { number } = {}

		const function resolveNext()
			const resolve = table.remove(resolves, 1)
			assert(resolve ~= nil, "Luau")
			resolve()
		end

		const promise = Promise.each({
			"foo",
			"bar",
			"baz",
		}, function(value, index)
			callCounts[index] = (callCounts[index] or 0) + 1

			return Promise.new(function(resolve)
				table.insert(resolves, function()
					resolve(value:upper())
				end)
			end)
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(#resolves).toBe(1)
		expect(callCounts[1]).toBe(1)
		expect(callCounts[2]).toBeNil()

		resolveNext()

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(#resolves).toBe(1)
		expect(callCounts[1]).toBe(1)
		expect(callCounts[2]).toBe(1)
		expect(callCounts[3]).toBeNil()

		resolveNext()

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(callCounts[1]).toBe(1)
		expect(callCounts[2]).toBe(1)
		expect(callCounts[3]).toBe(1)

		resolveNext()

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(type(internals(promise)._values[1])).toBe("table")
		expect(type(internals(promise)._values[2])).toBe("nil")

		const result = internals(promise)._values[1]

		expect(result[1]).toBe("FOO")
		expect(result[2]).toBe("BAR")
		expect(result[3]).toBe("BAZ")
	end)

	it("should reject with the value if the predicate promise rejects", function()
		const promise = Promise.each({ 1, 2, 3 }, function()
			return Promise.reject("foobar")
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe("foobar")
	end)

	it("should allow Promises to be in the list and wait when it gets to them", function()
		local innerResolve: (...any) -> ()
		const innerPromise = Promise.new(function(resolve)
			innerResolve = resolve
		end)

		const promise = Promise.each({
			innerPromise,
		}, function(value)
			return value * 2
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		innerResolve(2)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1][1]).toBe(4)
	end)

	it("should reject with the value if a Promise from the list rejects", function()
		local called = false
		const promise = Promise.each({ 1, 2, Promise.reject("foobar") }, function()
			called = true
			return "never"
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe("foobar")
		expect(called).toBe(false)
	end)

	it("should reject immediately if there's a cancelled Promise in the list initially", function()
		const cancelled = Promise.new(function() end)
		cancelled:cancel()

		local called = false
		const promise = Promise.each({ 1, 2, cancelled }, function()
			called = true
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(called).toBe(false)
		expect(internals(promise)._values[1].kind).toBe(Promise.Error.Kind.AlreadyCancelled)
	end)

	it("should stop iteration if Promise.each is cancelled", function()
		const callCounts: { number } = {}

		const promise = Promise.each({
			"foo",
			"bar",
			"baz",
		}, function(_value, index)
			callCounts[index] = (callCounts[index] or 0) + 1

			return Promise.new(function() end)
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)
		expect(callCounts[1]).toBe(1)
		expect(callCounts[2]).toBeNil()

		promise:cancel()

		expect(promise:getStatus()).toBe(Promise.Status.Cancelled)
		expect(callCounts[1]).toBe(1)
		expect(callCounts[2]).toBeNil()
	end)

	it("should cancel the Promise returned from the predicate if Promise.each is cancelled", function()
		local innerPromise: Promise.AnyPromise

		const promise = Promise.each({
			"foo",
			"bar",
			"baz",
		}, function()
			innerPromise = Promise.new(function() end)
			return innerPromise
		end)

		promise:cancel()

		expect(innerPromise:getStatus()).toBe(Promise.Status.Cancelled)
	end)

	it("should cancel Promises in the list if Promise.each is cancelled", function()
		const innerPromise = Promise.new(function() end)

		const promise = Promise.each({ innerPromise }, function() end)

		promise:cancel()

		expect(innerPromise:getStatus()).toBe(Promise.Status.Cancelled)
	end)
end)

describe("Promise.retry", function()
	it("should retry N times", function()
		local counter = 0

		const promise = Promise.retry(function(parameter)
			expect(parameter).toBe("foo")

			counter += 1

			if counter == 5 then
				return Promise.resolve("ok")
			end

			return Promise.reject("fail")
		end, 5, "foo")

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe("ok")
	end)

	it("should reject if threshold is exceeded", function()
		const promise = Promise.retry(function()
			return Promise.reject("fail")
		end, 5)

		expect(promise:getStatus()).toBe(Promise.Status.Rejected)
		expect(internals(promise)._values[1]).toBe("fail")
	end)
end)

describe("Promise.retryWithDelay", function()
	it("should retry after a delay", function()
		local counter = 0

		const promise = Promise.retryWithDelay(function(parameter)
			expect(parameter).toBe("foo")

			counter += 1

			if counter == 3 then
				return Promise.resolve("ok")
			end

			return Promise.reject("fail")
		end, 3, 10, "foo")

		expect(counter).toBe(1)

		advanceTime(11)

		expect(counter).toBe(2)

		advanceTime(11)

		expect(counter).toBe(3)

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe("ok")
	end)
end)

describe("Promise.fromEvent", function()
	it("should convert a Promise into an event", function()
		const event = Instance.new("BindableEvent")

		const promise = Promise.fromEvent(event.Event)

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		event:Fire("foo")

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe("foo")
	end)

	it("should convert a Promise into an event with the predicate", function()
		const event = Instance.new("BindableEvent")

		const promise = Promise.fromEvent(event.Event, function(param)
			return param == "foo"
		end)

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		event:Fire("bar")

		expect(promise:getStatus()).toBe(Promise.Status.Started)

		event:Fire("foo")

		expect(promise:getStatus()).toBe(Promise.Status.Resolved)
		expect(internals(promise)._values[1]).toBe("foo")
	end)
end)

describe("Promise.is", function()
	it("should work with current version", function()
		const promise = Promise.resolve(1)

		expect(Promise.is(promise)).toBe(true)
	end)

	it("should work with any object with an andThen", function()
		const obj = {
			andThen = function()
				return 1
			end,
		}

		expect(Promise.is(obj)).toBe(true)
	end)

	it("should work with older promises", function()
		const OldPromise = {}
		OldPromise.prototype = {}
		OldPromise.__index = OldPromise.prototype

		function OldPromise.prototype:andThen() end

		const oldPromise = setmetatable({}, OldPromise)

		expect(Promise.is(oldPromise)).toBe(true)
	end)
end)
