//
//  Exercises GSRulesDecide and GSRulesMinuteInRange.
//  Build from the repo root:
//    cc -Wall -Wextra -Wstrict-prototypes -Wmissing-prototypes -Werror -std=c11 \
//       -I Classes -o /tmp/test-rules Classes/GSRules.c script/test-rules.c
//

#include "GSRules.h"

#include <stdio.h>
#include <string.h>

static int g_failures = 0;

static void expect_action(const char *name, GSPowerAction got, GSPowerAction want)
{
    if (got == want)
        return;
    fprintf(stderr, "FAIL %s: action got %d want %d\n", name, (int)got, (int)want);
    g_failures++;
}

static void expect_reason(const char *name, GSRuleReason got, GSRuleReason want)
{
    if (got == want)
        return;
    fprintf(stderr, "FAIL %s: reason got %d want %d\n", name, (int)got, (int)want);
    g_failures++;
}

static void expect_int(const char *name, int got, int want)
{
    if (got == want)
        return;
    fprintf(stderr, "FAIL %s: got %d want %d\n", name, got, want);
    g_failures++;
}

static GSRulesContext base_context(void)
{
    GSRulesContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.currentlyDynamic = 1;
    ctx.powerMode = GSPowerSourceBasedSwitchingModeDontChange;
    ctx.scheduleMode = GSPowerSourceBasedSwitchingModeDontChange;
    ctx.oneShotMode = GSPowerSourceBasedSwitchingModeDontChange;
    ctx.batteryThresholdPercent = 20;
    return ctx;
}

static void test_priority(void)
{
    GSRulesContext ctx = base_context();
    GSRulesDecision decision = GSRulesDecide(0);
    expect_action("null", decision.action, GSPowerActionNone);

    ctx.manualOverride = 1;
    ctx.perAppEnabled = 1;
    ctx.perAppWantsDiscrete = 1;
    decision = GSRulesDecide(&ctx);
    expect_action("manual holds", decision.action, GSPowerActionNone);
    expect_reason("manual reason", decision.reason, GSRuleReasonManual);

    ctx.manualOverride = 0;
    ctx.paused = 1;
    ctx.displayRuleEnabled = 1;
    ctx.externalDisplayConnected = 1;
    decision = GSRulesDecide(&ctx);
    expect_action("pause holds", decision.action, GSPowerActionNone);
    expect_reason("pause has no rule reason", decision.reason, GSRuleReasonNone);

    ctx.paused = 0;
    ctx.manualOverride = 1;
    decision = GSRulesDecide(&ctx);
    expect_reason("manual beats pause", decision.reason, GSRuleReasonManual);
    ctx.manualOverride = 0;

    ctx.perAppWantsIntegrated = 1;
    decision = GSRulesDecide(&ctx);
    expect_action("per-app discrete wins", decision.action, GSPowerActionSwitchDiscrete);
    expect_reason("per-app reason", decision.reason, GSRuleReasonPerApp);

    ctx.perAppWantsDiscrete = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("per-app integrated", decision.action, GSPowerActionSwitchIntegrated);

    ctx.perAppWantsIntegrated = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("display after unmatched apps", decision.action, GSPowerActionSwitchDiscrete);
    expect_reason("display reason", decision.reason, GSRuleReasonDisplay);

    ctx.externalDisplayConnected = 0;
    ctx.batteryThresholdEnabled = 1;
    ctx.batteryPercentKnown = 1;
    ctx.batteryPercent = 19;
    ctx.batteryThresholdPercent = 20;
    decision = GSRulesDecide(&ctx);
    expect_action("below threshold", decision.action, GSPowerActionSwitchIntegrated);
    expect_reason("threshold reason", decision.reason, GSRuleReasonBatteryThreshold);

    ctx.batteryPercent = 20;
    ctx.scheduleEnabled = 1;
    ctx.scheduleHasMatch = 1;
    ctx.scheduleMode = GSPowerSourceBasedSwitchingModeDynamic;
    decision = GSRulesDecide(&ctx);
    expect_action("threshold is strict less-than", decision.action, GSPowerActionNone);
    expect_reason("schedule already dynamic", decision.reason, GSRuleReasonSchedule);

    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 1;
    decision = GSRulesDecide(&ctx);
    expect_action("schedule switches", decision.action, GSPowerActionSwitchDynamic);

    ctx.scheduleHasMatch = 0;
    ctx.powerEnabled = 1;
    ctx.powerMode = GSPowerSourceBasedSwitchingModeDontChange;
    ctx.oneShotEnabled = 1;
    ctx.oneShotMode = GSPowerSourceBasedSwitchingModeDiscrete;
    ctx.oneShotReason = GSRuleReasonLaunch;
    decision = GSRulesDecide(&ctx);
    expect_action("dont-change does not fall through", decision.action, GSPowerActionNone);
    expect_reason("power consumed the decision", decision.reason, GSRuleReasonPowerSource);

    ctx.powerEnabled = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("launch one-shot", decision.action, GSPowerActionSwitchDiscrete);
    expect_reason("launch reason", decision.reason, GSRuleReasonLaunch);

    ctx.oneShotReason = GSRuleReasonWake;
    decision = GSRulesDecide(&ctx);
    expect_reason("wake reason", decision.reason, GSRuleReasonWake);

    ctx.oneShotEnabled = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("nothing enabled", decision.action, GSPowerActionNone);
    expect_reason("nothing reason", decision.reason, GSRuleReasonNone);
}

static void test_dependencies_and_current_mode(void)
{
    GSRulesContext ctx = base_context();
    ctx.powerEnabled = 1;
    ctx.powerMode = GSPowerSourceBasedSwitchingModeIntegrated;
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 1;
    ctx.hasDiscreteDependencies = 1;
    GSRulesDecision decision = GSRulesDecide(&ctx);
    expect_action("already integrated ignores deps", decision.action, GSPowerActionNone);
    expect_reason("already integrated still names the rule", decision.reason, GSRuleReasonPowerSource);

    ctx.currentlyDynamic = 1;
    ctx.currentlyIntegrated = 1;
    decision = GSRulesDecide(&ctx);
    expect_action("dynamic plus integrated is blocked", decision.action, GSPowerActionBlockedByDependencies);

    ctx.hasDiscreteDependencies = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("dynamic plus integrated switches", decision.action, GSPowerActionSwitchIntegrated);

    ctx.powerMode = GSPowerSourceBasedSwitchingModeDiscrete;
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("already discrete", decision.action, GSPowerActionNone);

    ctx.powerMode = 99;
    decision = GSRulesDecide(&ctx);
    expect_action("garbage mode", decision.action, GSPowerActionNone);

    ctx.batteryThresholdEnabled = 1;
    ctx.batteryPercentKnown = 0;
    ctx.batteryPercent = 1;
    ctx.batteryThresholdPercent = 50;
    ctx.powerEnabled = 0;
    decision = GSRulesDecide(&ctx);
    expect_action("unknown percent skips threshold", decision.action, GSPowerActionNone);
}

static void test_ranges(void)
{
    expect_int("inside", GSRulesMinuteInRange(9 * 60, 9 * 60, 17 * 60), 1);
    expect_int("end is exclusive", GSRulesMinuteInRange(17 * 60, 9 * 60, 17 * 60), 0);
    expect_int("before", GSRulesMinuteInRange(8 * 60 + 59, 9 * 60, 17 * 60), 0);
    expect_int("empty", GSRulesMinuteInRange(12 * 60, 10 * 60, 10 * 60), 0);
    expect_int("wrap late", GSRulesMinuteInRange(23 * 60, 22 * 60, 6 * 60), 1);
    expect_int("wrap early", GSRulesMinuteInRange(5 * 60 + 59, 22 * 60, 6 * 60), 1);
    expect_int("wrap end exclusive", GSRulesMinuteInRange(6 * 60, 22 * 60, 6 * 60), 0);
    expect_int("wrap gap", GSRulesMinuteInRange(12 * 60, 22 * 60, 6 * 60), 0);
    expect_int("bad minute", GSRulesMinuteInRange(24 * 60, 0, 10), 0);
    expect_int("bad range", GSRulesMinuteInRange(10, -1, 20), 0);
}

int main(void)
{
    test_priority();
    test_dependencies_and_current_mode();
    test_ranges();
    if (g_failures) {
        fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    printf("ok\n");
    return 0;
}
