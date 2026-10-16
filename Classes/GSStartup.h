//
//  GSStartup.h
//  gfxCardStatus
//
//  Created by Cody Krieger on 6/12/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

@interface GSStartup : NSObject

// Whether or not the app is registered as a login item via SMAppService.
// Requires Approval still counts: the user asked for it, and macOS is waiting
// on System Settings → General → Login Items.
+ (BOOL)existsInStartupItems;

// Register or unregister this app as a login item.
+ (void)loadAtStartup:(BOOL)value;

@end
