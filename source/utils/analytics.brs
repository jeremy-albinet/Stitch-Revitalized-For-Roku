' Analytics helpers — thin wrappers over the AnalyticsTask global node.
'
' Usage (from any component that includes this script):
'
'   trackEvent("tab_visited", { tab: "Discover" })
'   analyticsIdentify({ app_version: "2.3.0", device_model: "4640X", ... })
'
' Both functions are safe to call before the task is initialized — events are
' silently dropped if m.global.analyticsTask is invalid.

' Sends a named event with optional properties.
' Global props (app_version, is_dev, is_logged_in) are injected automatically
' by AnalyticsTask — no need to include them here.
sub trackEvent(event as string, props = {} as object)
    if m.global.analyticsTask = invalid then return
    m.global.analyticsTask.capture = {
        event: event,
        props: props
    }
end sub

' Sends a PostHog $identify event to update person properties.
' Use on app open to set durable device/app attributes.
sub analyticsIdentify(setProps as object)
    if m.global.analyticsTask = invalid then return
    m.global.analyticsTask.identify = {
        set: setProps
    }
end sub
