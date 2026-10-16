//
//  GSPowerPolicy.c
//  gfxCardStatus
//

#include "GSPowerPolicy.h"

static int _modeIsKnown(GSPowerSourceBasedSwitchingMode mode)
{
    return mode == GSPowerSourceBasedSwitchingModeIntegrated
        || mode == GSPowerSourceBasedSwitchingModeDiscrete
        || mode == GSPowerSourceBasedSwitchingModeDynamic
        || mode == GSPowerSourceBasedSwitchingModeDontChange;
}

GSPowerAction GSPowerDecide(const GSPowerContext *context)
{
    GSPowerSourceBasedSwitchingMode desired;

    if (context == 0)
        return GSPowerActionNone;
    if (!context->featureEnabled || context->manualOverride)
        return GSPowerActionNone;
    if (context->source != GSPowerSourceBattery && context->source != GSPowerSourceACAdapter)
        return GSPowerActionNone;

    desired = (context->source == GSPowerSourceBattery) ? context->batteryMode : context->acMode;
    if (!_modeIsKnown(desired) || desired == GSPowerSourceBasedSwitchingModeDontChange)
        return GSPowerActionNone;

    if (desired == GSPowerSourceBasedSwitchingModeDynamic) {
        if (context->currentlyDynamic)
            return GSPowerActionNone;
        return GSPowerActionSwitchDynamic;
    }

    if (desired == GSPowerSourceBasedSwitchingModeIntegrated) {
        // Already locked to the integrated GPU. Dependencies do not matter
        // and must not produce a repeated warning.
        if (!context->currentlyDynamic && context->currentlyIntegrated)
            return GSPowerActionNone;
        if (context->hasDiscreteDependencies)
            return GSPowerActionBlockedByDependencies;
        return GSPowerActionSwitchIntegrated;
    }

    // Discrete only.
    if (!context->currentlyDynamic && !context->currentlyIntegrated)
        return GSPowerActionNone;
    return GSPowerActionSwitchDiscrete;
}

void GSPowerNoteSource(GSPowerTracker *tracker, GSPowerSource source, int *shouldApply)
{
    if (shouldApply)
        *shouldApply = 0;
    if (tracker == 0)
        return;
    if (source != GSPowerSourceBattery && source != GSPowerSourceACAdapter)
        return;

    if (!tracker->hasSettled) {
        tracker->hasSettled = 1;
        tracker->lastSettledSource = source;
        if (shouldApply)
            *shouldApply = tracker->manualOverride ? 0 : 1;
        return;
    }

    if (source == tracker->lastSettledSource)
        return;

    tracker->lastSettledSource = source;
    tracker->manualOverride = 0;
    if (shouldApply)
        *shouldApply = 1;
}
