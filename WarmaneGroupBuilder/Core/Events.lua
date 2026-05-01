-- Core/Events.lua
-- Lightweight pub/sub event bus. Modules NEVER call into each other directly;
-- they fire events and listen for events. This is the spine of the addon.
--
-- Usage:
--   WGB.Events:Register("REQUIREMENTS_CHANGED", self, function(self, req) ... end)
--   WGB.Events:Fire("REQUIREMENTS_CHANGED", reqTable)
--   WGB.Events:Unregister("REQUIREMENTS_CHANGED", self)

local WGB = _G.WGB

local Events = {}
WGB.Events = Events

-- listeners[event] = { [owner] = handlerFn, ... }
local listeners = {}

function Events:Register(event, owner, handler)
    assert(type(event) == "string", "event must be a string")
    assert(owner ~= nil, "owner required (any unique key)")
    assert(type(handler) == "function", "handler must be a function")
    listeners[event] = listeners[event] or {}
    listeners[event][owner] = handler
end

function Events:Unregister(event, owner)
    if listeners[event] then
        listeners[event][owner] = nil
    end
end

function Events:UnregisterAll(owner)
    for ev, t in pairs(listeners) do
        t[owner] = nil
    end
end

function Events:Fire(event, ...)
    local t = listeners[event]
    if not t then return end
    -- Snapshot owners + handlers so listeners that (un)register themselves
    -- inside a handler don't corrupt the iteration.
    local owners, handlers, n = {}, {}, 0
    for owner, handler in pairs(t) do
        n = n + 1
        owners[n] = owner
        handlers[n] = handler
    end
    for i = 1, n do
        local ok, err = pcall(handlers[i], owners[i], ...)
        if not ok then
            WGB.Print("|cFFFF0000Event handler error|r [" .. event .. "]: " .. tostring(err))
            if WGB_Settings and WGB_Settings.debug then
                local stack = debugstack and debugstack() or "(no stack)"
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[WGB-DBG stack]|r " .. stack)
            end
        end
    end
end

-- Diagnostic
function Events:CountListeners(event)
    local t = listeners[event]
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Prints every registered event and its listener count to chat.
function Events:ListEvents()
    local evts = {}
    for ev in pairs(listeners) do
        evts[#evts + 1] = ev
    end
    table.sort(evts)
    WGB.Print("Registered events (" .. #evts .. "):")
    for _, ev in ipairs(evts) do
        WGB.Print("  " .. ev .. " (" .. Events:CountListeners(ev) .. " listeners)")
    end
end
