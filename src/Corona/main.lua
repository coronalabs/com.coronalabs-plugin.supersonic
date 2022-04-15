-- Abstract: Supersonic Plugin
-- Version: 1.0
-- Sample code is MIT licensed; see https://www.coronalabs.com/links/code/license
---------------------------------------------------------------------------------------

local widget = require("widget")
local supersonic = require("plugin.supersonic")
local json = require("json")

display.setStatusBar(display.HiddenStatusBar)

local isAndroid = system.getInfo("platformName") == "Android"

local placementIds
local appKey
local userId = "testUser"
local placementIds = {"offerWall", "interstitial", "rewardedVideo"}

if isAndroid then
	appKey = "577e1595"
else
	appKey = "577ddc0d"
end

local currentPlacementId = 1

local background = display.newImageRect("back-whiteorange.png", display.actualContentWidth, display.actualContentHeight)
background.x = display.contentCenterX
background.y = display.contentCenterY

local statusText = display.newText({
	text = "",
	font = native.systemFontBold,
	fontSize = 16,
	align = "left",
	width = 320,
	height = 200,
})
statusText:setFillColor(0)
statusText.anchorX = 0.5
statusText.anchorY = 0
statusText.x = display.contentCenterX
statusText.y = display.screenOriginY + 10

local function supersonicListener(event)
	local eventText = json.prettify(event)
	statusText.text = eventText
	print(eventText)
end

print("Using ", appKey)
supersonic.init(supersonicListener, {
	appKey = appKey,
	userId = userId,
testMode = false
})

local changePlacementId = widget.newButton(
{
	label = "Change PID",
	width = 250,
	onRelease = function(event)
		currentPlacementId = currentPlacementId + 1
		if currentPlacementId > #placementIds then
			currentPlacementId = 1
		end
		statusText.text = string.format("Placement type: %s", placementIds[currentPlacementId])
	end,
})
changePlacementId.x = display.contentCenterX
changePlacementId.y = statusText.y + (statusText.height) + 10

local loadAd = widget.newButton(
{
	label = "Load Ad",
	width = 250,
	onRelease = function(event)
		supersonic.load(placementIds[currentPlacementId], userId)
	end,
})
loadAd.x = display.contentCenterX
loadAd.y = changePlacementId.y + changePlacementId.height + loadAd.height * .15

local showAd = widget.newButton(
{
	label = "Show Ad",
	onRelease = function(event)
		local isLoaded = supersonic.isLoaded(placementIds[currentPlacementId])
		print("Is ad loaded:", isLoaded)

		if isLoaded then
			supersonic.show(placementIds[currentPlacementId])
		end
	end,
})
showAd.x = display.contentCenterX
showAd.y = loadAd.y + loadAd.height + showAd.height * .15
