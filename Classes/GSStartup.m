//
//  GSStartup.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 6/12/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "GSStartup.h"

#import <ServiceManagement/ServiceManagement.h>

@implementation GSStartup

#pragma mark - GSStartup API

+ (BOOL)existsInStartupItems
{
    SMAppServiceStatus status = [SMAppService mainAppService].status;
    return status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval;
}

+ (void)loadAtStartup:(BOOL)value
{
    SMAppService *service = [SMAppService mainAppService];
    SMAppServiceStatus status = service.status;
    NSError *error = nil;

    if (value) {
        if (status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval)
            return;

        if (![service registerAndReturnError:&error]) {
            GSLogError(@"Failed to register login item: %@", error);
            return;
        }

        if (service.status == SMAppServiceStatusRequiresApproval)
            GSLogInfo(@"Login item is registered and waiting for approval in System Settings.");
        else
            GSLogDebug(@"Registered login item.");
    } else {
        if (status == SMAppServiceStatusNotRegistered || status == SMAppServiceStatusNotFound)
            return;

        if (![service unregisterAndReturnError:&error])
            GSLogError(@"Failed to unregister login item: %@", error);
        else
            GSLogDebug(@"Unregistered login item.");
    }
}

@end
