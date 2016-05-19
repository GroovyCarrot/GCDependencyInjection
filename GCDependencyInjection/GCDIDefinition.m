//
// GCDependencyInjection
//
// Created by Jake Wise on 30/03/2016.
// Copyright (c) 2016 GroovyCarrot Ltd. All rights reserved.
//
// You are permitted to use, modify, and distribute this file in accordance with
// the terms of the license agreement accompanying it.
//

#import "GCDIDefinition.h"
#import "GCDIMethodCall.h"

@implementation GCDIDefinition

@synthesize isPublic = _public;

# pragma mark - Init methods

- (id)init {
  self = [super init];
  if (!self) {
    return nil;
  }

  _arguments = @[].mutableCopy;
  _setters = @{}.mutableCopy;
  _methodCalls = @[].mutableCopy;
  _tags = @{}.mutableCopy;

  _shared = TRUE;
  _public = TRUE;
  _synthetic = FALSE;
  _lazy = FALSE;

  return self;
}

+ (GCDIDefinition *)definitionForClass:(Class)klass {
  return [[GCDIDefinition alloc] initForClassNamed:NSStringFromClass(klass)
                                      withSelector:@"init"
                                      andArguments:@[]];
}

+ (GCDIDefinition *)definitionForClass:(Class)klass withMethodCall:(GCDIMethodCall *)methodCall {
  return [[GCDIDefinition alloc] initForClassNamed:NSStringFromClass(klass)
                                      withSelector:methodCall.pSelector
                                      andArguments:methodCall.arguments];
}

+ (GCDIDefinition *)definitionForClass:(Class)klass withSelector:(SEL)pSelector {
  return [[GCDIDefinition alloc] initForClassNamed:NSStringFromClass(klass)
                                      withSelector:NSStringFromSelector(pSelector)
                                      andArguments:@[]];
}

+ (GCDIDefinition *)definitionForClass:(Class)klass withSelector:(SEL)pSelector andArguments:(NSArray *)arguments {
  return [[GCDIDefinition alloc] initForClassNamed:NSStringFromClass(klass)
                                      withSelector:NSStringFromSelector(pSelector)
                                      andArguments:arguments];
}

+ (GCDIDefinition *)definitionForClassNamed:(NSString *)klass withSelector:(SEL)pSelector {
  return [[GCDIDefinition alloc] initForClassNamed:klass
                                      withSelector:NSStringFromSelector(pSelector)
                                      andArguments:@[]];
}

+ (GCDIDefinition *)definitionForClassNamed:(NSString *)klass withSelector:(SEL)pSelector andArguments:(NSArray *)arguments {
  return [[GCDIDefinition alloc] initForClassNamed:klass
                                      withSelector:NSStringFromSelector(pSelector)
                                      andArguments:arguments];
}

- (GCDIDefinition *)initForClassNamed:(NSString *)klass withSelector:(NSString *)pSelector andArguments:(NSArray *)arguments {
  if (![self init]) {
    return nil;
  }

  _klass = klass.copy;
  _pSelector = pSelector.copy;
  _arguments = arguments.mutableCopy;

  return self;
}

# pragma mark - Setters

- (void)setArguments:(NSArray *)arguments {
  _arguments = arguments.mutableCopy;
}

- (void)setSetters:(NSDictionary *)setters {
  _setters = setters.mutableCopy;
}

- (void)setMethodCalls:(NSArray *)methodCalls {
  _methodCalls = methodCalls.mutableCopy;
}

- (void)setTags:(NSDictionary *)tags {
  _tags = tags.mutableCopy;
}

# pragma mark - Argument methods

- (void)addArgument:(id)argument {
  _arguments[_arguments.count] = argument;
}

- (void)replaceArgument:(id)argument atIndex:(NSUInteger)index {
  _arguments[index] = argument;
}

# pragma mark - Method invocations

- (void)addMethodCall:(GCDIMethodCall *)methodCall {
  _methodCalls[_methodCalls.count] = methodCall;
}

- (void)removeMethodCall:(GCDIMethodCall *)methodCall {
  for (GCDIMethodCall *method in _methodCalls) {
    if ([methodCall isEqualToMethodCall:method]) {
      [_methodCalls removeObject:method];
    }
  }
}

- (BOOL)hasMethodCall:(GCDIMethodCall *)methodCall {
  for (NSInvocation *method in _methodCalls) {
    if ([methodCall isEqualToMethodCall:method]) {
      return TRUE;
    }
  }
  return FALSE;
}

# pragma mark - Tagging methods

- (NSString *)getTag:(NSString *)tag {
  return _tags[tag];
}

- (void)clearTag:(NSString *)tag {
  [_tags removeObjectForKey:tag];
}

- (void)clearTags {
  [_tags removeAllObjects];
}

# pragma mark - Depreciation methods

- (void)setDepreciated:(BOOL)status forReason:(NSString *)reason {
  _depreciated = status;
  _depreciationMessage = reason.copy;
}

@end
