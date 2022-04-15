//
//  SuperSonicLibrary.h
//  SuperSonic plugin
//
//  Copyright (c) 2016 Corona Labs. All rights reserved.
//

#ifndef _SupersonicLibrary_H_
#define _SupersonicLibrary_H_

#import "CoronaLua.h"
#import "CoronaMacros.h"

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
// where the '.' is replaced with '_'
CORONA_EXPORT int luaopen_plugin_supersonic(lua_State *L);

#endif // _SupersonicLibrary_H_
