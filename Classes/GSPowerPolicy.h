//
//  GSPowerPolicy.h
//  gfxCardStatus
//
//  Pure decision logic for power-source GPU rules. No Cocoa, so it can be
//  tested on its own (see script/test-power-policy.c).
//
//  Stored preference values are integers and must stay stable:
//    0 integrated only, 1 discrete only, 2 dynamic switching, 3 don't change.
//

#ifndef GSPowerPolicy_h
#define GSPowerPolicy_h

typedef enum {
    GSPowerSourceUnknown = 0,
    GSPowerSourceBattery = 1,
    GSPowerSourceACAdapter = 2
} GSPowerSource;

typedef enum {
    GSPowerSourceBasedSwitchingModeIntegrated = 0,
    GSPowerSourceBasedSwitchingModeDiscrete = 1,
    GSPowerSourceBasedSwitchingModeDynamic = 2,
    GSPowerSourceBasedSwitchingModeDontChange = 3
} GSPowerSourceBasedSwitchingMode;

// What one evaluation of the rules should do. "None" means do not call the
// mux at all, which is what keeps an already-correct mode from switching
// again (and from looping on the display reconfiguration that follows).
typedef enum {
    GSPowerActionNone = 0,
    GSPowerActionSwitchIntegrated,
    GSPowerActionSwitchDiscrete,
    GSPowerActionSwitchDynamic,
    GSPowerActionBlockedByDependencies
} GSPowerAction;

typedef struct {
    // Master toggle. When this is 0 the rules never switch.
    int featureEnabled;
    // A manual status-menu (or launch-argument) choice is in effect.
    int manualOverride;
    GSPowerSource source;
    GSPowerSourceBasedSwitchingMode batteryMode;
    GSPowerSourceBasedSwitchingMode acMode;
    // Current mux state, using the same meaning as the status menu:
    // dynamic switching is its own mode even when the integrated GPU is the
    // one currently driving the display.
    int currentlyDynamic;
    int currentlyIntegrated;
    // External display or a process holding the discrete GPU on.
    int hasDiscreteDependencies;
} GSPowerContext;

// Remembers the last power source we acted on, and whether a manual choice
// is holding. A reading that is not battery or AC does not settle and does
// not clear a manual choice.
typedef struct {
    int hasSettled;
    GSPowerSource lastSettledSource;
    int manualOverride;
} GSPowerTracker;

// Returns the action for the current context. Does not switch by itself.
GSPowerAction GSPowerDecide(const GSPowerContext *context);

// Updates the tracker for a newly read power source.
// *shouldApply is set to 1 only when the rules should be evaluated:
// the first settled reading (unless a manual override is already holding),
// or a later change between battery and AC. A change clears the override
// before *shouldApply is set, so the new source's rule runs.
void GSPowerNoteSource(GSPowerTracker *tracker, GSPowerSource source, int *shouldApply);

#endif
