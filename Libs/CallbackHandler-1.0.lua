--[[ $Id: CallbackHandler-1.0.lua 22 2018-07-21 14:17:22Z funkydude $ ]]
local MAJOR, MINOR = "CallbackHandler-1.0", 7
local CallbackHandler = LibStub:NewLibrary(MAJOR, MINOR)

if not CallbackHandler then return end -- No upgrade needed

local meta = {
  __index = function(tbl, key)
    tbl[key] = {}
    return tbl[key]
  end
}

-- Lua APIs
local tconcat = table.concat
local assert, error, loadstring = assert, error, loadstring
local setmetatable, rawset, rawget = setmetatable, rawset, rawget
local next, select, pairs, type, tostring = next, select, pairs, type, tostring

-- Global vars/functions that we don't upvalue since they might get hooked, or upgraded
-- List them here for Mikk's FindGlobals script
-- GLOBALS: geterrorhandler

local xpcall = xpcall

local function errorhandler(err)
  return geterrorhandler()(err)
end

local function CreateDispatcher(argCount)
  local code = [[
	local next, xpcall, eh = ...

	local method, ARGS
	local function call() method(ARGS) end

	local function dispatch(handlers, ...)
		local index, method = next(handlers)
		if not method then return end
		repeat
			ARGS = ...
			if not xpcall(call, eh) then
				handlers[index] = nil
			end
			index, method = next(handlers, index)
		until not method
	end

	return dispatch
	]]

  local ARGS = {}
  for i = 1, argCount do ARGS[i] = "arg" .. i end
  code = code:gsub("ARGS", tconcat(ARGS, ", "))

  return assert(loadstring(code, "safecall Dispatcher[" .. argCount .. "]"))(next, xpcall, errorhandler)
end

local Dispatchers = setmetatable({}, {
  __index = function(self, argCount)
    local dispatcher = CreateDispatcher(argCount)
    rawset(self, argCount, dispatcher)
    return dispatcher
  end
})

--------------------------------------------------------------------------
-- CallbackHandler:New
--
--   target            - target object to embed public APIs in
--   RegisterName      - name of the callback registration API, default "RegisterCallback"
--   UnregisterName    - name of the callback unregistration API, default "UnregisterCallback"
--   UnregisterAllName - name of the API to unregister all callbacks, default "UnregisterAllCallbacks". false == don't publish this API.

function CallbackHandler:New(target, RegisterName, UnregisterName, UnregisterAllName)
  RegisterName = RegisterName or "RegisterCallback"
  UnregisterName = UnregisterName or "UnregisterCallback"
  if UnregisterAllName == nil then -- false is used to indicate "don't want this method"
    UnregisterAllName = "UnregisterAllCallbacks"
  end

  -- we could call the methods directly on the target disregarding the registry, but we don't
  -- 1) less Performance (only noticeable with high frequency use)
  -- 2) Not Blizzard-API compliant (can't be used in places where a blizzard-api object is expected)

  local events = setmetatable({}, meta)
  local registry = { recurse = 0, events = events }

  -- CallbackHandler:Fire() - fires the given event/message into the registry
  local function Fire(self, eventname, ...)
    if type(eventname) ~= "string" then
      error("Usage: Fire(eventname, ...): 'eventname' - string expected.", 2)
    end

    local oldrecurse = registry.recurse
    registry.recurse = oldrecurse + 1

    Dispatchers[select('#', ...) + 1](events[eventname], eventname, ...)

    registry.recurse = oldrecurse

    if registry.recurse == 0 and registry.insertQueue and next(registry.insertQueue) then
      -- Something in one of our callbacks wanted to register more callbacks; they got queued
      for eventname, callbacks in pairs(registry.insertQueue) do
        local first = not rawget(events, eventname) or
            not next(events[eventname]) -- test for empty before. not test for one member after. that one member may have been overwritten.
        for self, func in pairs(callbacks) do
          events[eventname][self] = func
          -- fire OnUsed callback?
          if first and registry.OnUsed then
            registry.OnUsed(registry, target, eventname)
            first = nil
          end
        end
      end
      registry.insertQueue = nil
    end
  end

  -- Registration of a callback, handles:
  --   self["method"], leads to self["method"](self, ...)
  --   self with function ref, leads to functionref(...)
  --   "addonId" (instead of self) with function ref, leads to functionref(...)
  -- all with an optional arg, which, if present, gets passed as first argument (after self if present)
  target[RegisterName] = function(self, eventname, method, ... --[[actually just a single arg]])
    if type(eventname) ~= "string" then
      error("Usage: " .. RegisterName .. "(eventname, method[, arg]): 'eventname' - string expected.", 2)
    end

    method = method or eventname

    local first = not rawget(events, eventname) or
        not next(events[eventname]) -- test for empty before. not test for one member after. that one member may have been overwritten.

    if type(method) ~= "string" and type(method) ~= "function" then
      error("Usage: " .. RegisterName .. "(\"eventname\", \"methodname\"): 'methodname' - string or function expected.",
        2)
    end

    local regfunc

    if type(method) == "string" then
      -- self["method"] calling style
      if type(self) ~= "table" then
        error("Usage: " .. RegisterName .. "(\"eventname\", \"methodname\"): self was not a table?", 2)
      elseif self == target then
        error(
          "Usage: " ..
          RegisterName .. "(\"eventname\", \"methodname\"): do not use Library:" .. RegisterName ..
          "(), use your own 'self'", 2)
      elseif type(self[method]) ~= "function" then
        error(
          "Usage: " ..
          RegisterName ..
          "(\"eventname\", \"methodname\"): 'methodname' - method '" .. tostring(method) .. "' not found on self.", 2)
      end

      if select("#", ...) >= 1 then -- this is not the same as testing for arg==nil!
        local arg = select(1, ...)
        regfunc = function(...) self[method](self, arg, ...) end
      else
        regfunc = function(...) self[method](self, ...) end
      end
    else
      -- function ref with self=object or self="addonId" or self=thread
      if select("#", ...) >= 1 then -- this is not the same as testing for arg==nil!
        local arg = select(1, ...)
        if type(self) == "table" then
          regfunc = function(...) method(self, arg, ...) end
        else
          regfunc = function(...) method(arg, ...) end
        end
      else
        if type(self) == "table" then
          regfunc = function(...) method(self, ...) end
        else
          regfunc = method
        end
      end
    end


    if events[eventname][self] or registry.recurse < 1 then
      -- if registry.recurse<1 then
      -- we're overwriting an existing entry, or not currently recursing. just set it.
      events[eventname][self] = regfunc
      -- fire OnUsed callback?
      if registry.OnUsed and first then
        registry.OnUsed(registry, target, eventname)
      end
    else
      -- we're currently processing a callback in this registry, so delay the registration of this new entry!
      -- yes, we do this EVEN if you are replacing an existing entry, this is to avoid unregistering wildly from within a callback handler
      -- it WILL get overwritten, but any currently-executing iterator in the registry will get the old value, avoiding undefined behavior
      registry.insertQueue = registry.insertQueue or setmetatable({}, meta)
      registry.insertQueue[eventname][self] = regfunc
    end
  end

  -- Unregister a callback
  target[UnregisterName] = function(self, eventname)
    if not self or self == target then
      error("Usage: " .. UnregisterName .. "(eventname): bad 'self'", 2)
    end
    if type(eventname) ~= "string" then
      error("Usage: " .. UnregisterName .. "(eventname): 'eventname' - string expected.", 2)
    end
    if rawget(events, eventname) and events[eventname][self] then
      events[eventname][self] = nil
      -- Fire OnUnused callback?
      if registry.OnUnused and not next(events[eventname]) then
        registry.OnUnused(registry, target, eventname)
      end
    end
    if registry.insertQueue and rawget(registry.insertQueue, eventname) and registry.insertQueue[eventname][self] then
      registry.insertQueue[eventname][self] = nil
    end
  end

  -- OPTIONAL: Unregister all callbacks for given selfs/addonIds
  if UnregisterAllName then
    target[UnregisterAllName] = function(...)
      if select("#", ...) < 1 then
        error("Usage: " .. UnregisterAllName .. "([whatFor]): missing 'self' or \"addonId\" to unregister events for.", 2)
      end
      if select("#", ...) == 1 and ... == target then
        error("Usage: " .. UnregisterAllName .. "([whatFor]): supply a meaningful 'self' or \"addonId\"", 2)
      end


      for i = 1, select("#", ...) do
        local self = select(i, ...)
        if registry.insertQueue then
          for eventname, callbacks in pairs(registry.insertQueue) do
            if callbacks[self] then
              callbacks[self] = nil
            end
          end
        end
        for eventname, callbacks in pairs(events) do
          if callbacks[self] then
            callbacks[self] = nil
            -- Fire OnUnused callback?
            if registry.OnUnused and not next(callbacks) then
              registry.OnUnused(registry, target, eventname)
            end
          end
        end
      end
    end
  end

  target.Fire = Fire

  registry.Fire = Fire
  registry.target = target
  return registry
end

function CallbackHandler:Embed(target)
  return CallbackHandler:New(target)
end

CallbackHandler.embeds = CallbackHandler.embeds or {}

for target, v in pairs(CallbackHandler.embeds) do
  CallbackHandler:Embed(target)
end
