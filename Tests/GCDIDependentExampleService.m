//
// GCDependencyInjection
//
// Created by Jake Wise on 17/04/2016.
// Copyright (c) 2016 GroovyCarrot Ltd. All rights reserved.
//
// You are permitted to use, modify, and distribute this file in accordance with
// the terms of the license agreement accompanying it.
//

#import "GCDIDependentExampleService.h"
#import "GCDIExampleService.h"

@implementation GCDIDependentExampleService

- (GCDIDependentExampleService *)initWithDependentService:(GCDIExampleService *)dependency {
  self = [super init];
  if (!self) {
    return nil;
  }

  self.dependency = dependency;

  return self;
}

- (BOOL)isDependentServiceInitialised {
  return [self.dependency exampleServiceInitialised];
}

@end