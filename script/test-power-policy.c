//
//  Exercises GSPowerDecide and GSPowerNoteSource.
//  Build from the repo root:
//    cc -Wall -Wextra -Wstrict-prototypes -Werror -I Classes \
//       -o /tmp/test-power-policy Classes/GSPowerPolicy.c script/test-power-policy.c
//

#include "GSPowerPolicy.h"

#include <stdio.h>
#include <string.h>

static int g_failures = 0;

static void expect_action(const char *name, GSPowerAction got, GSPowerAction want)
{
    if (got == want)
        return;
    fprintf(stderr, "FAIL %s: got %d want %d\n", name, (int)got, (int)want);
    g_failures++;
}

static void expect_int(const char *name, int got, int want)
{
    if (got == want)
        return;
    fprintf(stderr, "FAIL %s: got %d want %d\n", name, got, want);
    g_failures++;
}

static GSPowerContext base_context(void)
{
    GSPowerContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.featureEnabled = 1;
    ctx.source = GSPowerSourceBattery;
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeIntegrated;
    ctx.acMode = GSPowerSourceBasedSwitchingModeDynamic;
    ctx.currentlyDynamic = 1;
    ctx.currentlyIntegrated = 0;
    return ctx;
}

static void test_decide(void)
{
    GSPowerContext ctx = base_context();

    expect_action("off", GSPowerDecide(&(GSPowerContext){
        .featureEnabled = 0,
        .source = GSPowerSourceBattery,
        .batteryMode = GSPowerSourceBasedSwitchingModeIntegrated,
        .currentlyDynamic = 1
    }), GSPowerActionNone);

    ctx = base_context();
    ctx.manualOverride = 1;
    expect_action("manual hold", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDontChange;
    expect_action("dont change", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.source = GSPowerSourceUnknown;
    expect_action("unknown source", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.batteryMode = (GSPowerSourceBasedSwitchingMode)99;
    expect_action("garbage mode", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.currentlyDynamic = 1;
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDynamic;
    expect_action("already dynamic", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 1;
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDynamic;
    expect_action("integrated only to dynamic", GSPowerDecide(&ctx), GSPowerActionSwitchDynamic);

    ctx = base_context();
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 1;
    ctx.hasDiscreteDependencies = 1;
    expect_action("already integrated ignores deps", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.currentlyDynamic = 1;
    ctx.currentlyIntegrated = 1;
    expect_action("dynamic-but-integrated still locks", GSPowerDecide(&ctx), GSPowerActionSwitchIntegrated);

    ctx = base_context();
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 0;
    ctx.hasDiscreteDependencies = 1;
    expect_action("blocked by deps", GSPowerDecide(&ctx), GSPowerActionBlockedByDependencies);

    ctx = base_context();
    ctx.currentlyDynamic = 1;
    ctx.hasDiscreteDependencies = 0;
    expect_action("switch integrated", GSPowerDecide(&ctx), GSPowerActionSwitchIntegrated);

    ctx = base_context();
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDiscrete;
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 0;
    expect_action("already discrete", GSPowerDecide(&ctx), GSPowerActionNone);

    ctx = base_context();
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDiscrete;
    ctx.currentlyDynamic = 1;
    ctx.currentlyIntegrated = 0;
    expect_action("dynamic to discrete", GSPowerDecide(&ctx), GSPowerActionSwitchDiscrete);

    ctx = base_context();
    ctx.source = GSPowerSourceACAdapter;
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDiscrete;
    ctx.acMode = GSPowerSourceBasedSwitchingModeDynamic;
    ctx.currentlyDynamic = 0;
    ctx.currentlyIntegrated = 1;
    expect_action("ac uses ac mode", GSPowerDecide(&ctx), GSPowerActionSwitchDynamic);

    ctx = base_context();
    ctx.source = GSPowerSourceBattery;
    ctx.batteryMode = GSPowerSourceBasedSwitchingModeDontChange;
    ctx.acMode = GSPowerSourceBasedSwitchingModeDiscrete;
    ctx.currentlyDynamic = 1;
    expect_action("battery ignores ac mode", GSPowerDecide(&ctx), GSPowerActionNone);

    expect_action("null context", GSPowerDecide(0), GSPowerActionNone);
}

static void test_note_source(void)
{
    GSPowerTracker tracker;
    int apply = 0;

    memset(&tracker, 0, sizeof(tracker));
    GSPowerNoteSource(&tracker, GSPowerSourceUnknown, &apply);
    expect_int("unknown does not settle", tracker.hasSettled, 0);
    expect_int("unknown does not apply", apply, 0);

    GSPowerNoteSource(&tracker, GSPowerSourceBattery, &apply);
    expect_int("first battery settles", tracker.hasSettled, 1);
    expect_int("first battery applies", apply, 1);
    expect_int("first battery remembers", (int)tracker.lastSettledSource, (int)GSPowerSourceBattery);

    apply = 99;
    GSPowerNoteSource(&tracker, GSPowerSourceBattery, &apply);
    expect_int("same source does not apply", apply, 0);

    GSPowerNoteSource(&tracker, GSPowerSourceUnknown, &apply);
    expect_int("glitch keeps last source", (int)tracker.lastSettledSource, (int)GSPowerSourceBattery);
    expect_int("glitch does not apply", apply, 0);

    tracker.manualOverride = 1;
    GSPowerNoteSource(&tracker, GSPowerSourceACAdapter, &apply);
    expect_int("change clears override", tracker.manualOverride, 0);
    expect_int("change applies", apply, 1);
    expect_int("change remembers ac", (int)tracker.lastSettledSource, (int)GSPowerSourceACAdapter);

    memset(&tracker, 0, sizeof(tracker));
    tracker.manualOverride = 1;
    GSPowerNoteSource(&tracker, GSPowerSourceUnknown, &apply);
    expect_int("override survives unknown", tracker.manualOverride, 1);
    expect_int("unknown still does not settle", tracker.hasSettled, 0);
    GSPowerNoteSource(&tracker, GSPowerSourceBattery, &apply);
    expect_int("first real source keeps launch override", apply, 0);
    expect_int("launch override still set", tracker.manualOverride, 1);

    memset(&tracker, 0, sizeof(tracker));
    tracker.manualOverride = 1;
    GSPowerNoteSource(&tracker, GSPowerSourceACAdapter, &apply);
    expect_int("launch override holds", apply, 0);
    expect_int("launch override stays", tracker.manualOverride, 1);
    expect_int("launch override still settles", tracker.hasSettled, 1);

    GSPowerNoteSource(&tracker, GSPowerSourceBattery, &apply);
    expect_int("later change ends launch override", tracker.manualOverride, 0);
    expect_int("later change applies", apply, 1);

    GSPowerNoteSource(0, GSPowerSourceBattery, &apply);
    expect_int("null tracker clears apply", apply, 0);
}

int main(void)
{
    test_decide();
    test_note_source();
    if (g_failures) {
        fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    printf("power policy tests passed\n");
    return 0;
}
