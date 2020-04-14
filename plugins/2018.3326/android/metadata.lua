local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest =
        {
            permissions = {},
            usesPermissions =
            {
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
                "android.permission.WRITE_EXTERNAL_STORAGE"
            },
            usesFeatures =
            {
            },
            applicationChildElements =
            {
                [[
                <activity
                    android:name="com.ironsource.sdk.controller.ControllerActivity"
                    android:configChanges="orientation|screenSize"
                    android:hardwareAccelerated="true" />
                <activity
                    android:name="com.ironsource.sdk.controller.InterstitialActivity"
                    android:configChanges="orientation|screenSize"
                    android:hardwareAccelerated="true"
                    android:theme="@android:style/Theme.Translucent" />
                <activity
                    android:name="com.ironsource.sdk.controller.OpenUrlActivity"
                    android:configChanges="orientation|screenSize"
                    android:hardwareAccelerated="true"
                    android:theme="@android:style/Theme.Translucent" />
                ]]
            }
        }
    },

    coronaManifest = {
        dependencies = {
            ["shared.google.play.services.ads.identifier"] = "com.coronalabs"
        }
    }
}

return metadata
