local M = {}

---Validates args for `throttle()` and  `debounce()`.
---@param fn function Function to validate
---@param ms number Timeout in ms
local function td_validate(fn, ms)
	vim.validate({
		fn = { fn, "f" },
		ms = {
			ms,
			---@param ms number
			---@return boolean
			---@diagnostic disable-next-line
			function(ms)
				return type(ms) == "number" and ms > 0
			end,
			"number > 0",
		},
	})
end

--- Throttles a function on the leading edge. Automatically `schedule_wrap()`s.
---
---@param fn function Function to throttle
---@param ms number Timeout in ms
---@returns (function, timer) throttled function and timer. Remember to call
---`timer:close()` at the end or you will leak memory!
function M.throttle_leading(fn, ms)
	td_validate(fn, ms)
	local timer = vim.loop.new_timer()
	local running = false

	local function wrapped_fn(...)
		if not timer then
			return
		end
		if not running then
			timer:start(ms, 0, function()
				running = false
			end)
			running = true
			pcall(vim.schedule_wrap(fn), select(1, ...))
		end
	end
	return wrapped_fn, timer
end

--- Throttles a function on the trailing edge. Automatically
--- `schedule_wrap()`s.
---@param ms number Timeout in ms
---@param last boolean|nil, optional Whether to use the arguments of the last
---call to `fn` within the timeframe. Default: Use arguments of the first call.
---@returns (function, timer) Throttled function and timer. Remember to call
---`timer:close()` at the end or you will leak memory!
function M.throttle_trailing(fn, ms, last)
	td_validate(fn, ms)
	local timer = vim.loop.new_timer()
	local running = false

	local wrapped_fn
	if not last then
		function wrapped_fn(...)
			if not timer then
				return
			end
			if not running then
				local argv = { ... }
				local argc = select("#", ...)

				timer:start(ms, 0, function()
					running = false
					pcall(vim.schedule_wrap(fn), unpack(argv, 1, argc))
				end)
				running = true
			end
		end
	else
		local argv, argc
		function wrapped_fn(...)
			argv = { ... }
			if not timer then
				return
			end
			argc = select("#", ...)

			if not running then
				timer:start(ms, 0, function()
					running = false
					pcall(vim.schedule_wrap(fn), unpack(argv, 1, argc))
				end)
				running = true
			end
		end
	end
	return wrapped_fn, timer
end

--- Debounces a function on the leading edge. Automatically `schedule_wrap()`s.
---
--@param fn (function) Function to debounce
--@param timeout (number) Timeout in ms
--@returns (function, timer) Debounced function and timer. Remember to call
---`timer:close()` at the end or you will leak memory!
function M.debounce_leading(fn, ms)
	td_validate(fn, ms)
	local timer = vim.loop.new_timer()
	local running = false

	local function wrapped_fn(...)
		if not timer then
			return
		end
		timer:start(ms, 0, function()
			running = false
		end)

		if not running then
			running = true
			pcall(vim.schedule_wrap(fn), select(1, ...))
		end
	end

	return wrapped_fn, timer
end

--- Debounces a function on the trailing edge. Automatically
--- `schedule_wrap()`s.
---
---@param fn function Function to debounce
---@param ms number Timeout in ms
---@param first boolean|nil Whether to use the arguments of the first
---call to `fn` within the timeframe. Default: Use arguments of the last call.
---@returns (function, timer) Debounced function and timer. Remember to call
---`timer:close()` at the end or you will leak memory!
function M.debounce_trailing(fn, ms, first)
	td_validate(fn, ms)
	local timer = vim.loop.new_timer()
	local wrapped_fn

	if not first then
		function wrapped_fn(...)
			if not timer then
				return
			end
			local argv = { ... }
			local argc = select("#", ...)

			timer:start(ms, 0, function()
				xpcall(vim.schedule_wrap(fn), function(err)
					vim.notify(debug.traceback(err), vim.log.levels.ERROR)
				end, unpack(argv, 1, argc))
			end)
		end
	else
		local argv, argc
		function wrapped_fn(...)
			if not timer then
				return
			end
			argv = argv or { ... }
			argc = argc or select("#", ...)

			timer:start(ms, 0, function()
				xpcall(vim.schedule_wrap(fn), function(err)
					vim.notifiy(debug.traceback(err), vim.log.levels.ERROR)
				end, unpack(argv, 1, argc))
			end)
		end
	end
	return wrapped_fn, timer
end

--- Test deferment methods (`{throttle,debounce}_{leading,trailing}()`).
---
--@param bouncer (string) Bouncer function to test
--@param ms (number, optional) Timeout in ms, default 2000.
--@param firstlast (bool, optional) Whether to use the 'other' fn call
---strategy.
function M.test_defer(bouncer, ms, firstlast)
	local bouncers = {
		tl = M.throttle_leading,
		tt = M.throttle_trailing,
		dl = M.debounce_leading,
		dt = M.debounce_trailing,
	}

	local timeout = ms or 2000

	local bounced = bouncers[bouncer](function(i)
		vim.cmd('echom "' .. bouncer .. ": " .. i .. '"')
	end, timeout, firstlast)

	for i, _ in ipairs({ 1, 2, 3, 4, 5 }) do
		bounced(i)
		vim.schedule(function()
			vim.cmd("echom " .. i)
		end)
		vim.fn.call("wait", { 1000, "v:false" })
	end
end

return M
