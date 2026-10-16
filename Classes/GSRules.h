//
//  GSRules.h
//  gfxCardStatus
//
//  Pure decision logic for automatic GPU rules. No Cocoa, so it can be
//  tested on its own (see script/test-rules.c).
//
//  Priority, first match wins:
//    1. Manual override. A status-menu, shortcut, launch-argument, or URL
//       choice is already in effect. Do not switch. The hold itself is
//       cleared by the caller on the next settled power-source change,
//       on Resume, or when a profile is selected.
//    2. Pause. Suppress every automatic rule. Do not switch.
//    3. Per-app. Discrete wins if any running chosen app requests it,
//       otherwise integrated if any running chosen app requests that.
//    4. External display. Discrete while a display is connected.
//    5. Battery threshold. Integrated when the charge is known and below
//       the configured percent.
//    6. Schedule. The first matching time range.
//    7. Power source, including Don't Change. Don't Change does not fall
//       through to the launch or wake one-shot.
//    8. One-shot. Launch default, or the wake mode, only when the caller
//       sets oneShotEnabled for that event.
//
//  Integrated Only is blocked while a discrete-GPU dependency exists,
//  unless the machine is already locked to the integrated GPU (that must
//  not nag). Already being in the requested mode does not call the mux.
//

#ifndef GSRules_h
#define GSRules_h

#include "GSPowerPolicy.h"

typedef enum {
    GSRuleReasonNone = 0,
    GSRuleReasonManual = 1,
    GSRuleReasonPerApp = 2,
    GSRuleReasonDisplay = 3,
    GSRuleReasonBatteryThreshold = 4,
    GSRuleReasonSchedule = 5,
    GSRuleReasonPowerSource = 6,
    GSRuleReasonWake = 7,
    GSRuleReasonLaunch = 8,
    // Recorded for a GPU change this process did not request.
    GSRuleReasonExternal = 100
} GSRuleReason;

typedef struct {
    int paused;
    int manualOverride;

    int perAppEnabled;
    int perAppWantsDiscrete;
    int perAppWantsIntegrated;

    int displayRuleEnabled;
    int externalDisplayConnected;

    int batteryThresholdEnabled;
    int batteryPercentKnown;
    int batteryPercent;
    int batteryThresholdPercent;

    int scheduleEnabled;
    int scheduleHasMatch;
    int scheduleMode;

    // powerMode is already resolved for the current source. Don't Change
    // and an unknown source are both passed as Don't Change. When
    // powerEnabled is 0 the power rule is skipped entirely.
    int powerEnabled;
    int powerMode;

    int oneShotEnabled;
    int oneShotMode;
    int oneShotReason;

    int currentlyDynamic;
    int currentlyIntegrated;
    int hasDiscreteDependencies;
} GSRulesContext;

typedef struct {
    GSPowerAction action;
    GSRuleReason reason;
} GSRulesDecision;

// Returns the action for one evaluation. Does not switch by itself.
GSRulesDecision GSRulesDecide(const GSRulesContext *context);

// Minute of the day, [0, 1440). A range is [start, end). start == end is
// empty and never matches. start > end wraps past midnight.
int GSRulesMinuteInRange(int minute, int start, int end);

#endif
