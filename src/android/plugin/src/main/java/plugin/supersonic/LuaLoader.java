//
//  LuaLoader.java
//  Supersonic plugin
//
//  Copyright (c) 2016 Corona Labs. All rights reserved.
//

// @formatter:off

package plugin.supersonic;

import java.util.HashMap;

import org.json.JSONObject;

import android.util.Log;

import com.naef.jnlua.LuaState;
import com.naef.jnlua.LuaType;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.NamedJavaFunction;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaLuaEvent;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;

// SDK provider imports
import com.ironsource.mediationsdk.config.ConfigFile;
import com.ironsource.mediationsdk.logger.IronSourceError;
import com.ironsource.mediationsdk.model.Placement;
import com.ironsource.mediationsdk.sdk.OfferwallListener;
import com.ironsource.mediationsdk.sdk.InterstitialListener;
import com.ironsource.mediationsdk.sdk.RewardedVideoListener;
import com.ironsource.mediationsdk.IronSource;
import com.ironsource.mediationsdk.integration.IntegrationHelper;
import com.ironsource.adapters.supersonicads.SupersonicConfig;

/**
 * Implements the Lua interface for a Corona plugin.
 * <p>
 * Only one instance of this class will be created by Corona for the lifetime of the application. This instance will be re-used for every new Corona activity
 * that gets created.
 */
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
    private final String PLUGIN_NAME = "plugin.supersonic";
    private final String PLUGIN_VERSION = "1.4.3";
    private final String PLUGIN_SDK_VERSION = "6.8.0"; // no API to get SDK version (yet)

    private final String EVENT_NAME = "adsRequest";
    private final String PROVIDER_NAME = "supersonic";

    private final String CORONA_LOG_TAG = "Corona";

    // ad types
    private final String TYPE_OFFER_WALL = "offerWall";
    private final String TYPE_INTERSTITIAL = "interstitial";
    private final String TYPE_REWARDED_VIDEO = "rewardedVideo";

    // phases
    private final String PHASE_INIT = "init";
    private final String PHASE_LOADED = "loaded";
    private final String PHASE_FAILED = "failed";
    private final String PHASE_DISPLAYED = "displayed";
    private final String PHASE_CLICKED = "clicked";
    private final String PHASE_CLOSED = "closed";
    private final String PHASE_REWARDED_KEY = "rewarded";
    private final String PHASE_PLAYBACK_BEGAN = "playbackBegan";
    private final String PHASE_PLAYBACK_ENDED = "playbackEnded";

    // responses
    private final String RESPONSE_NO_FILL_KEY = "noFill";

    // missing Corona Event Keys
    private static final String EVENT_PHASE_KEY = "phase";
    private static final String EVENT_TYPE_KEY = "type";
    private static final String EVENT_DATA_KEY = "data";

    private CoronaRuntimeTaskDispatcher fRuntimeTaskDispatcher;
    private int fListener = CoronaLua.REFNIL;

    // -------------------------------------------------------------------
    // Delegates
    // -------------------------------------------------------------------

    // Dispatch a Lua event to our callback
    public void dispatchLuaEvent(final HashMap<String, Object> event) {
        if (fRuntimeTaskDispatcher != null) {
            fRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
                @Override
                public void executeUsing(CoronaRuntime runtime) {
                    try {
                        LuaState L = runtime.getLuaState();
                        CoronaLua.newEvent(L, EVENT_NAME);
                        boolean hasErrorKey = false;

                        // add event parameters from map
                        for (String key : event.keySet()) {
                            CoronaLua.pushValue(L, event.get(key));           // push value
                            L.setField(-2, key);                              // push key

                            if (!hasErrorKey) {
                                hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
                            }
                        }

                        // add error key if not in map
                        if (!hasErrorKey) {
                            L.pushBoolean(false);
                            L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
                        }

                        // add provider
                        L.pushString(PROVIDER_NAME);
                        L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

                        CoronaLua.dispatchEvent(L, fListener, 0);
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            });
        }
    }

    // Supersonic offer wall listener class
    private class SupersonicOfferWallListenerClass implements OfferwallListener {
        @Override
        public void onOfferwallAvailable(boolean offerAvailable) {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, offerAvailable ? PHASE_LOADED : PHASE_FAILED);
            event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);
            event.put(CoronaLuaEvent.ISERROR_KEY, !offerAvailable);

            if (!offerAvailable) {
                event.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_NO_FILL_KEY);
            }

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onOfferwallOpened() {
            // NOP
            // This event arrives *after* the Corona activity has been suspended
            // the 'displayed' event is therefore sent in show()
        }

        @Override
        public void onOfferwallShowFailed(IronSourceError supersonicError) {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_FAILED);
            event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);
            event.put(CoronaLuaEvent.ISERROR_KEY, true);
            event.put(CoronaLuaEvent.RESPONSE_KEY, supersonicError.getErrorMessage());

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public boolean onOfferwallAdCredited(int credits, int totalCredits, boolean totalCreditsFlag) {
            // The credit info object
            JSONObject creditInfo = new JSONObject();

            // Get the credit info
            try {
                creditInfo.putOpt("credits", credits);
                creditInfo.putOpt("totalCredits", totalCredits);
                creditInfo.putOpt("totalCreditsFlag", totalCreditsFlag);
            } catch (Exception ex) {
                //ex.printStackTrace();
            }

            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_REWARDED_KEY);
            event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);
            event.put(CoronaLuaEvent.RESPONSE_KEY, creditInfo.toString());

            // Dispatch the event
            dispatchLuaEvent(event);

            return true;
        }

        @Override
        public void onGetOfferwallCreditsFailed(IronSourceError supersonicError) {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_FAILED);
            event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);
            event.put(CoronaLuaEvent.ISERROR_KEY, true);
            event.put(CoronaLuaEvent.RESPONSE_KEY, supersonicError.getErrorMessage());

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onOfferwallClosed() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_CLOSED);
            event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);

            // Dispatch the event
            dispatchLuaEvent(event);
        }
    }

    // Supersonic interstitial listener class
    private class SupersonicInterstitialListenerClass implements InterstitialListener {
        @Override
        public void onInterstitialAdReady() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_LOADED);
            event.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onInterstitialAdLoadFailed(IronSourceError supersonicError) {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_FAILED);
            event.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            event.put(CoronaLuaEvent.ISERROR_KEY, true);
            event.put(CoronaLuaEvent.RESPONSE_KEY, supersonicError.getErrorMessage());

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onInterstitialAdOpened() {
            // NOP
            // This event arrives *after* the Corona activity has been suspended
            // the 'displayed' event is therefore sent in show()
        }

        @Override
        public void onInterstitialAdClosed() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_CLOSED);
            event.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onInterstitialAdShowSucceeded() {
            // NOP
        }

        @Override
        public void onInterstitialAdShowFailed(IronSourceError supersonicError) {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_FAILED);
            event.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            event.put(CoronaLuaEvent.ISERROR_KEY, true);
            event.put(CoronaLuaEvent.RESPONSE_KEY, supersonicError.getErrorMessage());

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onInterstitialAdClicked() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_CLICKED);
            event.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);

            // Dispatch the event
            dispatchLuaEvent(event);
        }
    }

    // Supersonic rewarded video listener class
    private class SupersonicRewardedVideoListenerClass implements RewardedVideoListener {
        @Override
        public void onRewardedVideoAdClicked(Placement placement) {
        }

        @Override
        public void onRewardedVideoAdOpened() {
            // NOP
            // This event arrives *after* the Corona activity has been suspended
            // the 'displayed' event is therefore sent in show()
        }

        @Override
        public void onRewardedVideoAdClosed() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_CLOSED);
            event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onRewardedVideoAvailabilityChanged(boolean hasAvailableAds) {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, (hasAvailableAds) ? PHASE_LOADED : PHASE_FAILED);
            event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
            event.put(CoronaLuaEvent.ISERROR_KEY, !hasAvailableAds);

            if (!hasAvailableAds) {
                event.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_NO_FILL_KEY);
            }

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onRewardedVideoAdStarted() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_PLAYBACK_BEGAN);
            event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onRewardedVideoAdEnded() {
            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_PLAYBACK_ENDED);
            event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onRewardedVideoAdRewarded(Placement placement) {
            // The placement info object
            JSONObject placementInfo = new JSONObject();

            // Get the placement info
            try {
                placementInfo.putOpt("placementName", placement.getPlacementName());
                placementInfo.putOpt("rewardName", placement.getRewardName());
                placementInfo.putOpt("rewardAmount", placement.getRewardAmount());
            } catch (Exception ex) {
                //ex.printStackTrace();
            }

            HashMap<String, Object> event = new HashMap<>();
            event.put(EVENT_PHASE_KEY, PHASE_REWARDED_KEY);
            event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
            event.put(CoronaLuaEvent.RESPONSE_KEY, placementInfo.toString());

            // Dispatch the event
            dispatchLuaEvent(event);
        }

        @Override
        public void onRewardedVideoAdShowFailed(IronSourceError supersonicError) {
            // NOP - Event not available on iOS
        }
    }


    // -------------------------------------------------------
    // plugin implementation
    // -------------------------------------------------------

    /**
     * Creates a new Lua interface to this plugin.
     * <p>
     * Note that a new LuaLoader instance will not be created for every CoronaActivity instance. That is, only one instance of this class will be created for
     * the lifetime of the application process. This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
     */
    public LuaLoader() {
        // Set up this plugin to listen for Corona runtime events to be received by methods
        // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
        CoronaEnvironment.addRuntimeListener(this);
    }

    /**
     * Called when this plugin is being loaded via the Lua require() function.
     * <p>
     * Note that this method will be called everytime a new CoronaActivity has been launched. This means that you'll need to re-initialize this plugin here.
     * <p>
     * Warning! This method is not called on the main UI thread.
     *
     * @param L Reference to the Lua state that the require() function was called from.
     * @return Returns the number of values that the require() function will return.
     * <p>
     * Expected to return 1, the library that the require() function is loading.
     */
    @Override
    public int invoke(LuaState L) {
        // Register this plugin into Lua with the following functions.
        NamedJavaFunction[] luaFunctions = new NamedJavaFunction[]
                {
                        new Init(),
                        new Load(),
                        new Show(),
                        new IsLoaded(),
                };
        String libName = L.toString(1);
        L.register(libName, luaFunctions);

        // Returning 1 indicates that the Lua require() function will return the above Lua library.
        return 1;
    }

    // [Lua] supersonic.init(listener, options)
    private class Init implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "init";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            // If the listener is null
            if (fListener == CoronaLua.REFNIL) {
                // Set the delegate's listenerRef to reference the Lua listener function (if it exists)
                if (CoronaLua.isListener(L, 1, PROVIDER_NAME)) {
                    // Assign the listener reference
                    fListener = CoronaLua.newRef(L, 1);
                }
                // Listener not passed, throw error
                else {
                    Log.i(CORONA_LOG_TAG, String.format("ERROR: supersonic.init(listener, options) listener expected, got %s", L.typeName(1)));
                    return 0;
                }

                // Num args
                int numArgs = L.getTop();

                // If the user passed too few, or too many arguments
                if (numArgs != 2) {
                    Log.i(CORONA_LOG_TAG, "ERROR: supersonic.init(listener, options) Expected 2 arguments, got " + numArgs);
                    return 0;
                }

                String appKey = null;
                String userId = null;
                boolean clientSideCallbacks = true;
                boolean testMode = false;
                boolean hasUserConsent = false;

                // Get the options table
                if (L.type(2) == LuaType.TABLE) {
                    L.getField(2, "appKey");
                    if (L.type(-1) == LuaType.STRING) {
                        appKey = L.toString(-1);
                    } else {
                        Log.i(CORONA_LOG_TAG, "ERROR: supersonic.init(listener, options) options.appKey (string) expected, got " + L.typeName(-1));
                        return 0;
                    }
                    L.pop(1);

                    L.getField(2, "userId");
                    if (!L.isNoneOrNil(-1)) {
                        if (L.type(-1) == LuaType.STRING) {
                            userId = L.toString(-1);
                        } else {
                            Log.i(CORONA_LOG_TAG, "ERROR: supersonic.init(listener, options) options.userId (string) expected, got " + L.typeName(-1));
                            return 0;
                        }
                    }
                    L.pop(1);

                    L.getField(2, "clientSideCallbacks");
                    if (!L.isNoneOrNil(-1)) {
                        if (L.type(-1) == LuaType.BOOLEAN) {
                            clientSideCallbacks = L.toBoolean(-1);
                        } else {
                            Log.i(CORONA_LOG_TAG, "ERROR: supersonic.init(listener, options) options.clientSideCallbacks (boolean) expected, got " + L.typeName(-1));
                            return 0;
                        }
                    }
                    L.pop(1);

                    L.getField(2, "testMode");
                    if (!L.isNoneOrNil(-1)) {
                        if (L.type(-1) == LuaType.BOOLEAN) {
                            testMode = L.toBoolean(-1);
                        } else {
                            Log.i(CORONA_LOG_TAG, "ERROR: supersonic.init(listener, options) options.testMode (boolean) expected, got " + L.typeName(-1));
                            return 0;
                        }
                    }
                    L.pop(1);

                    L.getField(2, "hasUserConsent");
                    if (!L.isNoneOrNil(-1)) {
                        if (L.type(-1) == LuaType.BOOLEAN) {
                            hasUserConsent = L.toBoolean(-1);
                        } else {
                            Log.i(CORONA_LOG_TAG, "ERROR: supersonic.init(listener, options) options.hasUserConsent (boolean) expected, got " + L.typeName(-1));
                            return 0;
                        }
                    }
                    L.pop(1);
                } else {
                    Log.i(CORONA_LOG_TAG, "supersonic.init(listener, options) options (table) expected, got " + L.typeName(2));
                    return 0;
                }

                // validation
                if (appKey == null) {
                    Log.i(CORONA_LOG_TAG, "supersonic.init(listener, options) options.appKey is missing");
                    return 0;
                }

                // Get the corona version
                L.getGlobal("system");
                L.getField(-1, "getInfo");
                L.pushString("build");
                L.call(1, 1);
                final String buildVersion = L.toString(-1);
                L.pop(1);

                // log plugin version to device console
                Log.i(CORONA_LOG_TAG, PLUGIN_NAME + ": " + PLUGIN_VERSION + " (SDK: " + PLUGIN_SDK_VERSION + ")");

                final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
                final boolean fClientSideCallbacks = clientSideCallbacks;
                final String fUserId = userId;
                final String fAppKey = appKey;
                final boolean fTestMode = testMode;
                final boolean fHasUserConsent = hasUserConsent;

                if (coronaActivity != null) {
                    coronaActivity.runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            IronSource.setOfferwallListener(new SupersonicOfferWallListenerClass());
                            IronSource.setInterstitialListener(new SupersonicInterstitialListenerClass());
                            IronSource.setRewardedVideoListener(new SupersonicRewardedVideoListenerClass());

                            // Set the configuration to attribute traffic to Corona
                            ConfigFile.getConfigFile().setPluginData("Corona", PLUGIN_VERSION, buildVersion);
                            SupersonicConfig.getConfigObj().setClientSideCallbacks(fClientSideCallbacks);
                            if (fUserId != null) {
                                IronSource.setUserId(fUserId);
                            }
                            IronSource.setConsent(fHasUserConsent);

                            IronSource.init(coronaActivity, fAppKey);

                            // Dispatch the init event
                            HashMap<String, Object> event = new HashMap<>();
                            event.put(EVENT_PHASE_KEY, PHASE_INIT);
                            dispatchLuaEvent(event);

                            if (fTestMode) {
                                IntegrationHelper.validateIntegration(coronaActivity);
                            }
                        }
                    });
                }
            }

            return 0;
        }
    }

    // [Lua] supersonic.load(adUnitType, userId)
    private class Load implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "load";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
            if (fListener == CoronaLua.REFNIL) {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.load(adUnitType, userId) you must call supersonic.init() before making any other supersonic.* Api calls");
                return 0;
            }

            // If the user passed too few, or too many arguments
            int numArgs = L.getTop();
            if (numArgs != 2) {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.load(adUnitType, userId) Expected two function arguments, adUnitType, userId - got " + String.valueOf(numArgs) + " function arguments");
                return 0;
            }

            final String adUnitType;
            final String userId;

            // Ensure the adUnitType is a string
            if (L.type(1) == LuaType.STRING) {
                adUnitType = L.toString(1);
            } else {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.load(adUnitType, userId) adUnitType (string) expected, got " + L.typeName(1));
                return 0;
            }

            // Ensure the userId is a string
            if (L.type(2) == LuaType.STRING) {
                userId = L.toString(2);
            } else {
                Log.i(CORONA_LOG_TAG, "supersonic.load(adUnitType, userId) userId expected, got " + L.typeName(2));
                return 0;
            }

            // Get the corona activity
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

            // If the corona activity isn't null
            if (coronaActivity != null) {
                // Create a new runnable object to invoke our activity
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        IronSource.setDynamicUserId(userId);

                        // Load the correct ad based on the adUnitType
                        if (adUnitType.equalsIgnoreCase(TYPE_OFFER_WALL)) {
                            // Offer walls are automatically loaded by the SDK
                            if (IronSource.isOfferwallAvailable()) {
                                HashMap<String, Object> event = new HashMap<>();
                                event.put(EVENT_PHASE_KEY, PHASE_LOADED);
                                event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);
                                dispatchLuaEvent(event);
                            }
                        } else if (adUnitType.equalsIgnoreCase(TYPE_REWARDED_VIDEO)) {
                            // rewarded videos are automatically loaded by the SDK
                            if (IronSource.isRewardedVideoAvailable()) {
                                HashMap<String, Object> event = new HashMap<>();
                                event.put(EVENT_PHASE_KEY, PHASE_LOADED);
                                event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
                                dispatchLuaEvent(event);
                            }
                        } else if (adUnitType.equalsIgnoreCase(TYPE_INTERSTITIAL)) {
                            IronSource.loadInterstitial();
                        } else {
                            Log.i(CORONA_LOG_TAG, String.format("supersonic.load(adUnitType, userId) Unsupported adUnitType. Valid options are: %s, %s, %s", TYPE_OFFER_WALL, TYPE_INTERSTITIAL, TYPE_REWARDED_VIDEO));
                        }
                    }
                };

                // Run the activity on the uiThread
                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] supersonic.show(adUnitType, [placementId])
    private class Show implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "show";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
            if (fListener == CoronaLua.REFNIL) {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.show(adUnitType, [placementId]) you must call supersonic.init() before making any other supersonic.* Api calls");
                return 0;
            }

            // If the user passed too few, or too many arguments
            int numArgs = L.getTop();
            if (numArgs > 2) {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.show(adUnitType, [placementId]) Expected one or two function arguments, adUnitType, [placementId] - got " + String.valueOf(numArgs) + " function arguments");
                return 0;
            }

            final String adUnitType;
            String placementId = null;

            // Ensure the adUnitType is a string
            if (L.type(1) == LuaType.STRING) {
                adUnitType = L.toString(1);
            } else {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.show(adUnitType, [placementId]) adUnitType (string) expected, got " + L.typeName(1));
                return 0;
            }

            // Ensure the placementId is a string
            if (!L.isNoneOrNil(2)) {
                if (L.type(2) == LuaType.STRING) {
                    placementId = L.toString(2);
                } else {
                    Log.i(CORONA_LOG_TAG, "supersonic.show(adUnitType, [placementId]) placementId (string) expected, got " + L.typeName(2));
                    return 0;
                }
            }

            // Get the corona activity
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String kPlacementId = placementId;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        // Load the correct ad based on the adUnitType
                        if (adUnitType.equalsIgnoreCase(TYPE_OFFER_WALL)) {
                            HashMap<String, Object> event = new HashMap<>();
                            event.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
                            event.put(EVENT_TYPE_KEY, TYPE_OFFER_WALL);
                            dispatchLuaEvent(event);

                            IronSource.showOfferwall();
                        } else if (adUnitType.equalsIgnoreCase(TYPE_INTERSTITIAL)) {
                            HashMap<String, Object> event = new HashMap<>();
                            event.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
                            event.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
                            dispatchLuaEvent(event);

                            if (kPlacementId != null) {
                                IronSource.showInterstitial(kPlacementId);
                            } else {
                                IronSource.showInterstitial();
                            }
                        } else if (adUnitType.equalsIgnoreCase(TYPE_REWARDED_VIDEO)) {
                            HashMap<String, Object> event = new HashMap<>();
                            event.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
                            event.put(EVENT_TYPE_KEY, TYPE_REWARDED_VIDEO);
                            dispatchLuaEvent(event);

                            if (kPlacementId != null) {
                                IronSource.showRewardedVideo(kPlacementId);
                            } else {
                                IronSource.showRewardedVideo();
                            }
                        } else {
                            Log.i(CORONA_LOG_TAG, String.format("supersonic.show(adUnitType, [placementId]) Unsupported adUnitType. Valid options are: %s, %s, %s", TYPE_OFFER_WALL, TYPE_INTERSTITIAL, TYPE_REWARDED_VIDEO));
                        }
                    }
                };

                // Run the activity on the uiThread
                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] supersonic.isLoaded(adUnitType)
    private class IsLoaded implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "isLoaded";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
            if (fListener == CoronaLua.REFNIL) {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.isLoaded(adUnitType) you must call supersonic.init() before making any other supersonic.* Api calls");
                return 0;
            }

            // If the user passed too few, or too many arguments
            int numArgs = L.getTop();
            if (numArgs != 1) {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.isLoaded(adUnitType) Expected one function arguments, adUnitType - got " + String.valueOf(numArgs) + " function arguments");
                return 0;
            }

            final String adUnitType;
            boolean hasLoaded = false;

            // Ensure the adUnitType is a string
            if (L.type(1) == LuaType.STRING) {
                adUnitType = L.toString(1);
            } else {
                Log.i(CORONA_LOG_TAG, "ERROR: supersonic.isLoaded(adUnitType) adUnitType (string) expected, got " + L.typeName(1));
                return 0;
            }

            // Check if the ad has loaded
            if (adUnitType.equalsIgnoreCase(TYPE_OFFER_WALL)) {
                hasLoaded = IronSource.isOfferwallAvailable();
            } else if (adUnitType.equalsIgnoreCase(TYPE_INTERSTITIAL)) {
                hasLoaded = IronSource.isInterstitialReady();
            } else if (adUnitType.equalsIgnoreCase(TYPE_REWARDED_VIDEO)) {
                hasLoaded = IronSource.isRewardedVideoAvailable();
            } else {
                Log.i(CORONA_LOG_TAG, String.format("supersonic.isLoaded(adUnitType) Unsupported adUnitType. Valid options are: %s, %s, %s", TYPE_OFFER_WALL, TYPE_INTERSTITIAL, TYPE_REWARDED_VIDEO));
                return 0;
            }

            // Is the ad loaded?
            L.pushBoolean(hasLoaded);

            return 1;
        }
    }

    // -------------------------------------------------------
    // Plugin lifecycle events
    // -------------------------------------------------------

    /**
     * Called after the Corona runtime has been created and just before executing the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
     *                Provides a LuaState object that allows the application to extend the Lua API.
     */
    @Override
    public void onLoaded(CoronaRuntime runtime) {
        // Note that this method will not be called the first time a Corona activity has been launched.
        // This is because this listener cannot be added to the CoronaEnvironment until after
        // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
        // However, this method will be called when a 2nd Corona activity has been created.
        if (fRuntimeTaskDispatcher == null) {
            fRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);
        }
    }

    /**
     * Called just after the Corona runtime has executed the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been started.
     */
    @Override
    public void onStarted(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
     * and other Corona related operations. This can happen when another Android activity (ie: window) has
     * been displayed, when the screen has been powered off, or when the screen lock is shown.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been suspended.
     */
    @Override
    public void onSuspended(CoronaRuntime runtime) {
        // Get the corona activity
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        // If the corona activity & the supersonic instance are not null
        if (coronaActivity != null) {
            // Create a new runnable object to invoke our activity
            Runnable runnableActivity = new Runnable() {
                @Override
                public void run() {
                    // Pause supersonic
                    IronSource.onPause(coronaActivity);
                }
            };

            // Run the activity on the uiThread
            coronaActivity.runOnUiThread(runnableActivity);
        }
    }

    /**
     * Called just after the Corona runtime has been resumed after a suspend.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been resumed.
     */
    @Override
    public void onResumed(CoronaRuntime runtime) {
        // Get the corona activity
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        // If the corona activity & the supersonic instance are not null
        if (coronaActivity != null) {
            // Create a new runnable object to invoke our activity
            Runnable runnableActivity = new Runnable() {
                @Override
                public void run() {
                    IronSource.onResume(coronaActivity);
                }
            };

            // Run the activity on the uiThread
            coronaActivity.runOnUiThread(runnableActivity);
        }
    }

    /**
     * Called just before the Corona runtime terminates.
     * <p>
     * This happens when the Corona activity is being destroyed which happens when the user presses the Back button on the activity, when the
     * native.requestExit() method is called in Lua, or when the activity's finish() method is called. This does not mean that the application is exiting.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that is being terminated.
     */
    @Override
    public void onExiting(CoronaRuntime runtime) {
        // Remove the Lua listener reference.
        CoronaLua.deleteRef(runtime.getLuaState(), fListener);
        fListener = CoronaLua.REFNIL;

        fRuntimeTaskDispatcher = null;
    }
}
