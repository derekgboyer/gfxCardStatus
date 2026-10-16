//
//  GSRules.c
//  gfxCardStatus
//

#include "GSRules.h"

static GSRulesDecision _decision(GSPowerAction action, GSRuleReason reason)
{
    GSRulesDecision decision;
    decision.action = action;
    decision.reason = reason;
    return decision;
}

// Same already-in-mode and dependency checks as GSPowerDecide, so a machine
// with only the power-source rule behaves the way that rule did on its own.
static GSRulesDecision _switchOrNone(const GSRulesContext *context, int mode, GSRuleReason reason)
{
    if (mode == GSPowerSourceBasedSwitchingModeDontChange)
        return _decision(GSPowerActionNone, reason);

    if (mode == GSPowerSourceBasedSwitchingModeDynamic) {
        if (context->currentlyDynamic)
            return _decision(GSPowerActionNone, reason);
        return _decision(GSPowerActionSwitchDynamic, reason);
    }

    if (mode == GSPowerSourceBasedSwitchingModeIntegrated) {
        if (!context->currentlyDynamic && context->currentlyIntegrated)
            return _decision(GSPowerActionNone, reason);
        if (context->hasDiscreteDependencies)
            return _decision(GSPowerActionBlockedByDependencies, reason);
        return _decision(GSPowerActionSwitchIntegrated, reason);
    }

    if (mode == GSPowerSourceBasedSwitchingModeDiscrete) {
        if (!context->currentlyDynamic && !context->currentlyIntegrated)
            return _decision(GSPowerActionNone, reason);
        return _decision(GSPowerActionSwitchDiscrete, reason);
    }

    return _decision(GSPowerActionNone, reason);
}

GSRulesDecision GSRulesDecide(const GSRulesContext *context)
{
    if (context == 0)
        return _decision(GSPowerActionNone, GSRuleReasonNone);
    if (context->manualOverride)
        return _decision(GSPowerActionNone, GSRuleReasonManual);
    if (context->paused)
        return _decision(GSPowerActionNone, GSRuleReasonNone);

    if (context->perAppEnabled) {
        if (context->perAppWantsDiscrete)
            return _switchOrNone(context, GSPowerSourceBasedSwitchingModeDiscrete, GSRuleReasonPerApp);
        if (context->perAppWantsIntegrated)
            return _switchOrNone(context, GSPowerSourceBasedSwitchingModeIntegrated, GSRuleReasonPerApp);
    }

    if (context->displayRuleEnabled && context->externalDisplayConnected)
        return _switchOrNone(context, GSPowerSourceBasedSwitchingModeDiscrete, GSRuleReasonDisplay);

    if (context->batteryThresholdEnabled && context->batteryPercentKnown
        && context->batteryPercent < context->batteryThresholdPercent)
        return _switchOrNone(context, GSPowerSourceBasedSwitchingModeIntegrated, GSRuleReasonBatteryThreshold);

    if (context->scheduleEnabled && context->scheduleHasMatch)
        return _switchOrNone(context, context->scheduleMode, GSRuleReasonSchedule);

    // Don't Change is a real result. It must not fall through to launch/wake.
    if (context->powerEnabled)
        return _switchOrNone(context, context->powerMode, GSRuleReasonPowerSource);

    if (context->oneShotEnabled)
        return _switchOrNone(context, context->oneShotMode, (GSRuleReason)context->oneShotReason);

    return _decision(GSPowerActionNone, GSRuleReasonNone);
}

int GSRulesMinuteInRange(int minute, int start, int end)
{
    if (minute < 0 || minute >= (24 * 60))
        return 0;
    if (start < 0 || end < 0 || start >= (24 * 60) || end >= (24 * 60))
        return 0;
    if (start == end)
        return 0;
    if (start < end)
        return minute >= start && minute < end;
    return minute >= start || minute < end;
}
