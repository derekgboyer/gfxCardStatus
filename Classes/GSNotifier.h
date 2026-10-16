//
//  GSNotifier.h
//  gfxCardStatus
//
//  Created by Cody Krieger on 6/12/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "GSGPU.h"

@interface GSNotifier : NSObject

+ (GSNotifier *)sharedInstance;

- (void)showGPUChangeNotification:(GSGPUType)type;
- (void)showOneTimeNotification;
- (void)showGPUSwitchingUnavailableMessage;
- (void)showCantSwitchToIntegratedOnlyMessage:(NSArray *)taskList;

// Non-modal. Used when a power-source rule cannot move to Integrated Only.
// taskNames are display names, not the process dictionaries.
- (void)showPowerRuleBlockedNotification:(NSArray *)taskNames;

@end
