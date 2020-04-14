-- Supersonic plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name="plugin.supersonic", publisherId="com.coronalabs", version=2 }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local supersonic = require "plugin.supersonic"
--    supersonic.init()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The Supersonic plugin is only supported on Android & iOS devices. Please build for device")
end

function lib.init()
    showWarning("supersonic.init()")
end

function lib.load()
    showWarning("supersonic.load()")
end

function lib.isLoaded()
    showWarning("supersonic.isLoaded()")
end

function lib.show()
    showWarning("supersonic.show()")
end

function lib.hide()
    showWarning("supersonic.hide()")
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
