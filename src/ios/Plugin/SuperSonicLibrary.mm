//
//  SuperSonicLibrary.mm
//  Supersonic plugin
//
//  Copyright (c) 2016 Corona Labs. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLibrary.h"
#import "CoronaLuaIOS.h"

#import "SuperSonicLibrary.h"
#import <IronSource/IronSource.h>
#import <IronSource/ISConfigurations.h>

#define PLUGIN_NAME        "plugin.supersonic"
#define PLUGIN_VERSION     "1.4.4"
#define PLUGIN_SDK_VERSION [IronSource sdkVersion]

const char EVENT_NAME[]    = "adsRequest";
const char PROVIDER_NAME[] = "supersonic";

// ad types
const char *TYPE_OFFER_WALL     = "offerWall";
const char *TYPE_INTERSTITIAL   = "interstitial";
const char *TYPE_REWARDED_VIDEO = "rewardedVideo";

// phases
const char *PHASE_LOADED_KEY         = "loaded";
const char *PHASE_FAILED_KEY         = "failed";
const char *PHASE_DISPLAYED_KEY      = "displayed";
const char *PHASE_CLICKED_KEY        = "clicked";
const char *PHASE_CLOSED_KEY         = "closed";
const char *PHASE_REWARDED_KEY       = "rewarded";
const char *PHASE_PLAYBACK_BEGAN_KEY = "playbackBegan";
const char *PHASE_PLAYBACK_ENDED_KEY = "playbackEnded";

// response codes
const char *RESPONSE_NO_FILL_KEY     = "noFill";

// ----------------------------------------------------------------------------
// plugin class and delegate definitions
// ----------------------------------------------------------------------------

@interface SupersonicDelegate : NSObject <ISRewardedVideoDelegate, ISOfferwallDelegate, ISInterstitialDelegate>

@property (nonatomic, assign) CoronaLuaRef coronaListener;           // Reference to the Lua listener
@property (nonatomic, assign) id<CoronaRuntime> coronaRuntime;         // Pointer to the Corona runtime

- (void)dispatchLuaEvent:(NSDictionary *)dict;

@end

// ----------------------------------------------------------------------------

class SupersonicLibrary
{
  public:
		typedef SupersonicLibrary Self;
		
  public:
		static const char kName[];
		
  protected:
		SupersonicLibrary();
		
  public:
		static int Open( lua_State *L );
		
  public:
		bool Initialize(void *platformContext);
		
  protected:
		static int Finalizer( lua_State *L );
		
  public:
		static Self *ToLibrary( lua_State *L );
		
  public:
		static int init(lua_State *L);
		static int load(lua_State *L);
		static int show(lua_State *L);
		static int isLoaded(lua_State *L);
  
  public:
		CoronaLuaRef GetListener() const { return fListener; }
		UIViewController* GetAppViewController() const { return fAppViewController; }
		
  private:
		CoronaLuaRef fListener;
		UIViewController *fAppViewController;
		
  protected:
		id<CoronaRuntime> fRuntime;
};

const char SupersonicLibrary::kName[] = PLUGIN_NAME;
SupersonicDelegate *supersonicDelegate = nil;

// ----------------------------------------------------------------------------
// plugin implementation
// ----------------------------------------------------------------------------

SupersonicLibrary::SupersonicLibrary()
:	fListener(NULL)
{
}

bool
SupersonicLibrary::Initialize(void *platformContext)
{
  bool result = (supersonicDelegate == nil);
  
  if (result)
  {
    id<CoronaRuntime> runtime = (__bridge id<CoronaRuntime>)platformContext;
    fAppViewController = runtime.appViewController;
    
    // Initialise the delegate
    supersonicDelegate = [SupersonicDelegate new];
    supersonicDelegate.coronaRuntime = runtime;
  }
  
  return result;
}

int
SupersonicLibrary::Open(lua_State *L)
{
  // Register __gc callback
  const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
  CoronaLuaInitializeGCMetatable(L, kMetatableName, Finalizer);
  
  //CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );
  void *platformContext = CoronaLuaGetContext(L);
  
  // Set library as upvalue for each library function
  Self *library = new Self;
  
  if (library->Initialize(platformContext))
  {
    // Functions in library
    static const luaL_Reg kFunctions[] =
    {
      {"init", init},
      {"load", load},
      {"show", show},
      {"isLoaded", isLoaded},
      {NULL, NULL}
    };
    
    // Register functions as closures, giving each access to the
    // 'library' instance via ToLibrary()
    {
      CoronaLuaPushUserdata(L, library, kMetatableName);
      luaL_openlib(L, kName, kFunctions, 1); // leave "library" on top of stack
    }
  }
  
  return 1;
}

int
SupersonicLibrary::Finalizer(lua_State *L)
{
  Self *library = (Self *)CoronaLuaToUserdata(L, 1);
  
  // Delete listener
  if (library->GetListener() != NULL) {
    CoronaLuaDeleteRef(L, library->GetListener());
  }
  
  // Remove the delegate
  supersonicDelegate = nil;
  
  delete library;
  
  return 0;
}

SupersonicLibrary *
SupersonicLibrary::ToLibrary( lua_State *L )
{
  // library is pushed as part of the closure
  Self *library = (Self *)CoronaLuaToUserdata(L, lua_upvalueindex(1));
  return library;
}

// [Lua] supersonic.init(listener [, options] )
int
SupersonicLibrary::init(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (context)
  {
    Self& library = *context;
    
    // If the listener is null
    if (library.GetListener() == NULL)
    {
      // Get the listener
      if (CoronaLuaIsListener(L, 1, PROVIDER_NAME))
      {
        // Assign the listener references
        library.fListener = CoronaLuaNewRef(L, 1);
        supersonicDelegate.coronaListener = library.GetListener();
      }
      // Listener not passed, throw error
      else
      {
        CoronaLuaError(L, "ERROR: supersonic.init(listener, options) listener expected, got %s", lua_typename(L, lua_type(L, 1)));
        return 0;
      }
      
      // Num args
      int numArgs = lua_gettop(L);
      
      // If the user passed too few, or too many arguments
      if (numArgs != 2)
      {
        CoronaLuaError(L, "ERROR: supersonic.init(listener, options) Expected two function arguments, listener, options - got %d function arguments", numArgs);
        return 0;
      }

      const char *appKey = NULL;
      const char *userId = NULL;
      bool clientSideCallbacks = true;
      bool testMode = false;
      bool hasUserConsent = false;
      
      // Get the options table
      if (lua_type(L, 2) == LUA_TTABLE)
      {
        // Get the appKey
        lua_getfield(L, 2, "appKey");
        
        // Ensure the appKey is a string
        if (lua_type(L, -1) == LUA_TSTRING)
        {
          appKey = lua_tostring(L, -1);
        }
        else
        {
          CoronaLuaError(L, "ERROR: supersonic.init(listener, options) options.appKey expected, got %s", lua_typename(L, lua_type(L, -1)));
          return 0;
        }
        lua_pop(L, 1);
        
        lua_getfield(L, 2, "userId");
        if (! lua_isnoneornil(L, -1)) {
          if (lua_type(L, -1) == LUA_TSTRING)
          {
            userId = lua_tostring(L, -1);
          }
          else
          {
            CoronaLuaError(L, "ERROR: supersonic.init(listener, options) options.userId (string) expected, got %s", lua_typename(L, lua_type(L, -1)));
            return 0;
          }
        }
        lua_pop(L, 1);
        
        lua_getfield(L, 2, "clientSideCallbacks");
        if (! lua_isnoneornil(L, -1)) {
          if (lua_type(L, -1) == LUA_TBOOLEAN)
          {
            clientSideCallbacks = lua_toboolean(L, -1);
          }
          else
          {
            CoronaLuaError(L, "ERROR: supersonic.init(listener, options) options.clientSideCallbacks (boolean) expected, got %s", lua_typename(L, lua_type(L, -1)));
            return 0;
          }
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "testMode");
        if (! lua_isnoneornil(L, -1)) {
          if (lua_type(L, -1) == LUA_TBOOLEAN)
          {
            testMode = lua_toboolean(L, -1);
          }
          else
          {
            CoronaLuaError(L, "ERROR: supersonic.init(listener, options) options.testMode (boolean) expected, got %s", lua_typename(L, lua_type(L, -1)));
            return 0;
          }
        }
        lua_pop(L, 1);
          
          lua_getfield(L, 2, "hasUserConsent");
          if (! lua_isnoneornil(L, -1)) {
              if (lua_type(L, -1) == LUA_TBOOLEAN)
              {
                  hasUserConsent = lua_toboolean(L, -1);
              }
              else
              {
                  CoronaLuaError(L, "ERROR: supersonic.init(listener, options) options.hasUserConsent (boolean) expected, got %s", lua_typename(L, lua_type(L, -1)));
                  return 0;
              }
          }
          lua_pop(L, 1);
      }
      else
      {
        CoronaLuaError(L, "supersonic.init(listener, options) options (table) expected, got %s", lua_typename(L, lua_type(L, 2)));
        return 0;
      }
      
      // get Corona version and set the configuration to attribute traffic to Corona
      lua_getglobal(L, "system");
      lua_getfield(L, -1, "getInfo");
      lua_pushstring(L, "build");
      lua_call(L, 1, 1);
      const char *buildVersion = lua_tostring(L, -1);
      lua_pop(L, 1);
      
      [ISConfigurations getConfigurations].plugin = @"Corona";
      [ISConfigurations getConfigurations].pluginVersion = @(PLUGIN_VERSION);
      [ISConfigurations getConfigurations].pluginFrameworkVersion = @(buildVersion);
      
      // log plugin version to device log
      NSLog(@"%s: %s (SDK: %@)", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_SDK_VERSION);
      
      // delegates and userId must be set before SDK iniialization
      [IronSource setOfferwallDelegate:supersonicDelegate];
      [IronSource setInterstitialDelegate:supersonicDelegate];
      [IronSource setRewardedVideoDelegate:supersonicDelegate];
      [ISSupersonicAdsConfiguration configurations].useClientSideCallbacks = @(clientSideCallbacks);
      if (userId != NULL) {
        [IronSource setUserId:@(userId)];
      }
      [IronSource setConsent:hasUserConsent];
      
      // initialize
      [IronSource initWithAppKey:@(appKey)];
      
      // Send Lua event
      NSDictionary *event = @{
        @(CoronaEventPhaseKey()): @"init"
      };
      [supersonicDelegate dispatchLuaEvent:event];
      
      if (testMode) {
        [ISIntegrationHelper validateIntegration];
      }
    }
  }
  
  return 0;
}

// [Lua] supersonic.load(adUnitType, userId)
int
SupersonicLibrary::load(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (context)
  {
    Self& library = *context;
    const char *adUnitType = NULL;
    const char *userId = NULL;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "ERROR: supersonic.load(adUnitType, userId) you must call supersonic.init() before making any other supersonic.* Api calls");
      return 0;
    }
    
    // Num args
    int numArgs = lua_gettop(L);
    
    // If the user passed too few, or too many arguments
    if (numArgs != 2)
    {
      CoronaLuaError(L, "ERROR: supersonic.load(adUnitType, userId) Expected two function arguments, adUnitType, userId - got %d function arguments", numArgs);
      return 0;
    }
    
    // Ensure the adUnitType is a string
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      adUnitType = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: supersonic.load(adUnitType, userId) adUnitType (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Ensure the userId is a string
    if (lua_type(L, 2) == LUA_TSTRING)
    {
      userId = lua_tostring(L, 2);
    }
    else
    {
      CoronaLuaError(L, "supersonic.load(adUnitType, userId) userId expected, got %s", lua_typename(L, lua_type(L, 2)));
      return 0;
    }
    
    [IronSource setDynamicUserId:@(userId)];
    
    if (strcmp(TYPE_INTERSTITIAL, adUnitType) == 0) {
      [IronSource loadInterstitial];
    }
    else if (strcmp(TYPE_OFFER_WALL, adUnitType) == 0) {
      // offer wall ads are fetched automatically by the SDK
      if ([IronSource hasOfferwall]) {
        [supersonicDelegate offerwallHasChangedAvailability:true];
      }
    }
    else if (strcmp(TYPE_REWARDED_VIDEO, adUnitType) == 0) {
      // rewarded videos are fetched automatically by the SDK
      if ([IronSource hasRewardedVideo]) {
        [supersonicDelegate rewardedVideoHasChangedAvailability:true];
      }
    }
    else
    {
      CoronaLuaError(L, "supersonic.load(adUnitType, userId) Unsupported adUnitType. Valid options are: %s, %s, %s", TYPE_OFFER_WALL, TYPE_INTERSTITIAL, TYPE_REWARDED_VIDEO);
      return 0;
    }
  }
  
  return 0;
}

// [Lua] supersonic.show(adUnitType [, placementId])
int
SupersonicLibrary::show(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (context)
  {
    Self& library = *context;
    const char *adUnitType = NULL;
    const char *placementId = NULL;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "ERROR: supersonic.show(adUnitType, [placementId]) you must call supersonic.init() before making any other supersonic.* Api calls");
      return 0;
    }
    
    // Num args
    int numArgs = lua_gettop(L);
    
    // If the user passed too few, or too many arguments
    if (numArgs > 2)
    {
      CoronaLuaError(L, "ERROR: supersonic.show(adUnitType, [placementId]) Expected one or two function arguments, adUnitType, [placementId] - got %d function arguments", numArgs);
      return 0;
    }
    
    // Ensure the adUnitType is a string
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      adUnitType = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: supersonic.show(adUnitType, [placementId]) adUnitType (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Ensure the placementId is a string (optional value)
    if (!lua_isnoneornil(L, 2))
    {
      if (lua_type(L, 2) == LUA_TSTRING)
      {
        placementId = lua_tostring(L, 2);
      }
      else
      {
        CoronaLuaError(L, "supersonic.show(adUnitType, [placementId]) placementId (string) expected, got %s", lua_typename(L, lua_type(L, 2)));
        return 0;
      }
    }
    
    // Get the app view controller
    UIViewController *appViewController = library.GetAppViewController();
    
    if (strcmp(TYPE_OFFER_WALL, adUnitType) == 0) {
      if (placementId != NULL) {
        [IronSource showOfferwallWithViewController:appViewController placement:@(placementId)];
      }
      else {
        [IronSource showOfferwallWithViewController:appViewController];
      }
    }
    else if (strcmp(TYPE_INTERSTITIAL, adUnitType) == 0) {
      if (placementId != NULL) {
        [IronSource showInterstitialWithViewController:appViewController placement:@(placementId)];
      }
      else {
        [IronSource showInterstitialWithViewController:appViewController];
      }
    }
    else if (strcmp(TYPE_REWARDED_VIDEO, adUnitType) == 0)
    {
      if (placementId != NULL) {
        [IronSource showRewardedVideoWithViewController:appViewController placement:@(placementId)];
      }
      else {
        [IronSource showRewardedVideoWithViewController:appViewController];
      }
    }
    else
    {
      CoronaLuaError(L, "supersonic.show(adUnitType, [placementId]) Unsupported adUnitType. Valid options are: %s, %s, %s", TYPE_OFFER_WALL, TYPE_INTERSTITIAL, TYPE_REWARDED_VIDEO);
      return 0;
    }
  }
  
  return 0;
}

// [Lua] supersonic.isLoaded(adUnitType)
int
SupersonicLibrary::isLoaded(lua_State *L)
{
  Self *context = ToLibrary(L);
  bool hasLoaded = false;
  
  if (context)
  {
    Self& library = *context;
    const char *adUnitType = NULL;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "ERROR: supersonic.isLoaded(adUnitType) you must call supersonic.init() before making any other supersonic.* Api calls");
      return 0;
    }
    
    // Num args
    int numArgs = lua_gettop(L);
    
    // If the user passed too few, or too many arguments
    if (numArgs != 1)
    {
      CoronaLuaError(L, "ERROR: supersonic.isLoaded(adUnitType) Expected one function argument, adUnitType - got %d function arguments", numArgs);
      return 0;
    }
    
    // Ensure the adUnitType is a string
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      adUnitType = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: supersonic.isLoaded(adUnitType) adUnitType (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Check if the ad has loaded
    if (strcmp(TYPE_OFFER_WALL, adUnitType) == 0) {
      hasLoaded = [IronSource hasOfferwall];
    }
    else if (strcmp(TYPE_INTERSTITIAL, adUnitType) == 0) {
      hasLoaded = [IronSource hasInterstitial];
    }
    else if (strcmp(TYPE_REWARDED_VIDEO, adUnitType) == 0) {
      hasLoaded = [IronSource hasRewardedVideo];
    }
    else {
      CoronaLuaError(L, "supersonic.isLoaded(adUnitType) Unsupported adUnitType. Valid options are: %s, %s, %s", TYPE_OFFER_WALL, TYPE_INTERSTITIAL, TYPE_REWARDED_VIDEO);
      return 0;
    }
  }
  
  // Is the ad loaded?
  lua_pushboolean(L, hasLoaded);
  
  return 1;
}

// --------------------------------------------------------------------------------
// Ironsource delegate implementation
// --------------------------------------------------------------------------------

@implementation SupersonicDelegate

- (instancetype)init {
  if (self = [super init]) {
    self.coronaListener = NULL;
    self.coronaRuntime = NULL;
  }
  
  return self;
}

// Dispatch a Lua event
- (void)dispatchLuaEvent:(NSDictionary *)dict
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    lua_State *L = self.coronaRuntime.L;
    CoronaLuaRef coronaListener = self.coronaListener;
    bool hasErrorKey = false;
    
    // create new event
    CoronaLuaNewEvent(L, EVENT_NAME);
    
    for (NSString *key in dict) {
      CoronaLuaPushValue(L, [dict valueForKey:key]);
      lua_setfield(L, -2, key.UTF8String);
      
      if (! hasErrorKey) {
        hasErrorKey = [key isEqualToString:@(CoronaEventIsErrorKey())];
      }
    }
    
    // add error key if not in dict
    if (! hasErrorKey) {
      lua_pushboolean(L, false);
      lua_setfield(L, -2, CoronaEventIsErrorKey());
    }
    
    // add provider
    lua_pushstring(L, PROVIDER_NAME );
    lua_setfield(L, -2, CoronaEventProviderKey());
    
    CoronaLuaDispatchEvent(L, coronaListener, 0);
  }];
}

// --------------------------------------------------------------------------------
// Interstitial ad delegate implementation

// Invoked when Interstitial Ad is ready to be shown after load function was //called.
-(void)interstitialDidLoad
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_LOADED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
  };
  
  [self dispatchLuaEvent:event];
  
}

// Called each time the Interstitial window has opened successfully.
-(void)interstitialDidShow
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_DISPLAYED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
  };
  
  [self dispatchLuaEvent:event];
}

// Called if showing the Interstitial for the user has failed.
// You can learn about the reason by examining the ‘error’ value
-(void)interstitialDidFailToShowWithError:(NSError *)error
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): [error description],
  };
  
  [self dispatchLuaEvent:event];
}

// Called each time the end user has clicked on the Interstitial ad.
-(void)didClickInterstitial
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_CLICKED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
  };
  
  [self dispatchLuaEvent:event];
}

// Called each time the Interstitial window is about to close
-(void)interstitialDidClose
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_CLOSED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
  };
  
  [self dispatchLuaEvent:event];
}

// Called each time the Interstitial window is about to open
-(void)interstitialDidOpen
{
  // NOP
  // We only need to implement the "displayed" event
}

// Invoked when there is no Interstitial Ad available after calling load
// function. @param error - will contain the failure code and description.
-(void)interstitialDidFailToLoadWithError:(NSError *)error
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): [error description],
  };
  
  [self dispatchLuaEvent:event];
}

// --------------------------------------------------------------------------------
// Rewarded video ad delegate implementation

// Called after a rewarded video has changed its availability.
// @param available The new rewarded video availability. YES if available
// and ready to be shown, NO otherwise.
- (void)rewardedVideoHasChangedAvailability:(BOOL)available
{
  NSMutableDictionary *event = [@{
    @(CoronaEventPhaseKey()): (available) ? @(PHASE_LOADED_KEY) : @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO),
    @(CoronaEventIsErrorKey()): @(! available)
  } mutableCopy];
  
  if (!available) {
    event[@(CoronaEventResponseKey())] = @(RESPONSE_NO_FILL_KEY);
  }
  
  [self dispatchLuaEvent:event];
}

// Called after a rewarded video has been viewed completely and the user is
// eligible for reward.@param placementInfo An object that contains the
// placement's reward name and amount.
- (void)didReceiveRewardForPlacement:(ISPlacementInfo *)placementInfo
{
  // create the placement data
  NSDictionary *dictionaryPlacement = @{
    @"placementName": [placementInfo placementName],
    @"rewardName": [placementInfo rewardName],
    @"rewardAmount": [NSString stringWithFormat:@"%@", [placementInfo rewardAmount]]
  };
  
  // convert the data to JSON
  NSData *info = [NSJSONSerialization dataWithJSONObject:dictionaryPlacement options:0 error:nil];
  
  // send the Lus event
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_REWARDED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO),
    @(CoronaEventResponseKey()): [[NSString alloc] initWithData:info encoding:NSUTF8StringEncoding],
  };
  [self dispatchLuaEvent:event];
}

// Called after a rewarded video has attempted to show but failed.
// @param error The reason for the error
- (void)rewardedVideoDidFailToShowWithError:(NSError *)error
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO),
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): [error description],
  };
  
  [self dispatchLuaEvent:event];
}

// Called after a rewarded video has been opened.
- (void)rewardedVideoDidOpen
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_DISPLAYED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO),
  };
  
  [self dispatchLuaEvent:event];
}

// Called after a rewarded video has been dismissed.
- (void)rewardedVideoDidClose
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_CLOSED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO),
  };
  
  [self dispatchLuaEvent:event];
}

// Note: the events below are not available for all supported rewarded video ad networks.
// Check which events are available per ad network you choose
// to include in your build. We recommend only using events which register to ALL ad networks you
// include in your build. Called after a rewarded video has started playing.
- (void)rewardedVideoDidStart
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_PLAYBACK_BEGAN_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO)
  };
  
  [self dispatchLuaEvent:event];
}

// Called after a rewarded video has finished playing.
- (void)rewardedVideoDidEnd
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_PLAYBACK_ENDED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_REWARDED_VIDEO)
  };
  
  [self dispatchLuaEvent:event];
}

- (void)didClickRewardedVideo:(ISPlacementInfo *)placementInfo {
}


// --------------------------------------------------------------------------------
// Offer Wall ad delegate implementation

// Invoked when there is a change in the Offerwall availability status.
// @param - available - value will change to YES when Offerwall are
// available. You can then show the video by calling showOfferwall(). Value will
// change to NO when Offerwall isn't available.
- (void)offerwallHasChangedAvailability:(BOOL)available
{
  NSMutableDictionary *event = [@{
    @(CoronaEventPhaseKey()): (available) ? @(PHASE_LOADED_KEY) : @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_OFFER_WALL),
    @(CoronaEventIsErrorKey()): @(! available)
  } mutableCopy];
  
  if (!available) {
    event[@(CoronaEventResponseKey())] = @(RESPONSE_NO_FILL_KEY);
  }
  
  [self dispatchLuaEvent:event];
}

// Called each time the Offerwall successfully loads for the user
-(void)offerwallDidShow
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_DISPLAYED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_OFFER_WALL)
  };
  
  [self dispatchLuaEvent:event];
}

// Called each time the Offerwall fails to show
// @param error - will contain the failure code and description
- (void)offerwallDidFailToShowWithError:(NSError *)error
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_OFFER_WALL),
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): [error description]
  };
  
  [self dispatchLuaEvent:event];
}

// Called each time the user completes an offer.
// @param creditInfo - A dictionary with the following key-value pairs:
// @"credits" - (integer) The number of credits the user has earned since
//     the last (void)didReceiveOfferwallCredits:(NSDictionary *)creditInfo event
//     that returned 'YES'. Note that the credits may represent multiple
//     completions (see return parameter).
// @"totalCredits" - (integer) The total number of credits ever earned by the user.
// @"totalCreditsFlag" - (boolean) In some cases, we won’t be able to
//     provide the exact amount of credits since the last event(specifically if the user
//     clears the app’s data). In this case the ‘credits’ will be equal to the @"totalCredits", and this flag will be @(YES).
// @return The publisher should return a boolean stating if he handled this call
//     (notified the user for example). if the return value is 'NO' the 'credits' value will be added to the next call.
- (BOOL)didReceiveOfferwallCredits:(NSDictionary *)creditInfo
{
  // get the credit data
  NSData *creditInfoData = [NSJSONSerialization dataWithJSONObject:creditInfo options:0 error:nil];
  
  // send the Lua event
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_REWARDED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_OFFER_WALL),
    @(CoronaEventResponseKey()): [[NSString alloc] initWithData:creditInfoData encoding:NSUTF8StringEncoding]
  };
  
  [self dispatchLuaEvent:event];
  
  return YES;
}

// Called when the method ‘-getOWCredits’
// failed to retrieve the users credit balance info.
// @param error - the error object with the failure info
- (void)didFailToReceiveOfferwallCreditsWithError:(NSError *)error
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_FAILED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_OFFER_WALL),
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): [error description],
  };
  
  [self dispatchLuaEvent:event];
}

// Called when the user closes the Offerwall
-(void)offerwallDidClose
{
  NSDictionary *event = @{
    @(CoronaEventPhaseKey()): @(PHASE_CLOSED_KEY),
    @(CoronaEventTypeKey()): @(TYPE_OFFER_WALL),
  };
  
  [self dispatchLuaEvent:event];
}

@end

// ----------------------------------------------------------------------------

CORONA_EXPORT int luaopen_plugin_supersonic(lua_State *L)
{
  return SupersonicLibrary::Open(L);
}
