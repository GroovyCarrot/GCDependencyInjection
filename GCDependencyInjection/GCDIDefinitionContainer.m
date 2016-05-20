//
// GCDependencyInjection
//
// Created by Jake Wise on 17/04/2016.
// Copyright (c) 2016 GroovyCarrot Ltd. All rights reserved.
//
// You are permitted to use, modify, and distribute this file in accordance with
// the terms of the license agreement accompanying it.
//

#import "GCDIDefinitionContainer.h"
#import "GCDIDefinition.h"
#import "GCDIParameterBagProtocol.h"
#import "GCDIReference.h"
#import "GCDIExceptions.h"
#import "GCDIMethodCall.h"
#import "GCDIDefinitionContainer+Yaml.h"
#import "GCDIAlias.h"
#import "GCDINSStringReferenceConverter.h"
#import <objc/runtime.h>

static NSMutableDictionary *registeredStoryboardContainers;

@interface NSIBUserDefinedRuntimeAttributesConnector : NSObject
- (void)establishConnection;
- (void)setValues:(id)arg1;
- (id)values;
@end

@implementation GCDIDefinitionContainer {
 @protected
  NSMutableDictionary *_obsoleteDefinitions;
}

+ (void)load {
  // Setup runtime to allow injection into storyboards.
  registeredStoryboardContainers = @{}.mutableCopy;

  Class klass = objc_getClass("NSIBUserDefinedRuntimeAttributesConnector");
  SEL sel = @selector(establishConnection);
  Method method = class_getInstanceMethod(klass, sel);

  void (*NSIBUserDefinedRuntimeAttributesConnector$establishConnection)(id, SEL) = (void (*)(id, SEL)) method_getImplementation(method);
  IMP adjustedImp = imp_implementationWithBlock(^void (NSIBUserDefinedRuntimeAttributesConnector *_self) {
    // Resolve values before allowing attributes connector to connect them to
    // the object.
    GCDINSStringReferenceConverter *referenceConverter = [[GCDINSStringReferenceConverter alloc] init];
    id values = [referenceConverter resolveReferencesToServices:[_self values]];
    [_self setValues:[GCDIDefinitionContainer exposeValuesToRegisteredStoryboardContainers:values]];
    NSIBUserDefinedRuntimeAttributesConnector$establishConnection(_self, sel);
  });

  class_replaceMethod(klass, sel, adjustedImp, method_getTypeEncoding(method));
}

+ (id)exposeValuesToRegisteredStoryboardContainers:(id)values {
  // @todo support unescaping parameter placeholders with multiple containers.
  // @todo support multiple containers in general without needing to use @? to
  // prevent the first container throwing exceptions for services that do not
  // exist within that container.
  for (NSString *key in registeredStoryboardContainers) {
    GCDIDefinitionContainer *container = registeredStoryboardContainers[key];
    values = [container.parameterBag resolveParameterPlaceholders:values];
    values = [container resolveServices:values];
  }
  return values;
}

- (id)init {
  self = [super init];
  if (!self) {
    return nil;
  }

  _identifier = [NSUUID UUID].UUIDString;

  _definitions = @{}.mutableCopy;
  _aliasDefinitions = @{}.mutableCopy;
  _obsoleteDefinitions = @{}.mutableCopy;

  // Add the Yaml provision method to the default init method for overriding.
  [self yamlProvisionContainer];

  return self;
}

# pragma mark - Service methods

- (id)getServiceNamed:(NSString *)serviceId withInvalidBehaviour:(GCDIInvalidBehaviourType)invalidBehaviourType {
  serviceId = [serviceId lowercaseString];

  id service = [super getServiceNamed:serviceId
                 withInvalidBehaviour:kNilOnInvalidReference];
  if (service) {
    return service;
  }

  if (!_definitions[serviceId] && _aliasDefinitions[serviceId]) {
    GCDIAlias *alias = _aliasDefinitions[serviceId];
    return [self getServiceNamed:alias.aliasId withInvalidBehaviour:invalidBehaviourType];
  }

  // Attempt to load the service.
  GCDIDefinition *definition;

  @try {
    definition = [self getDefinitionForService:serviceId];
  }
  @catch (NSException *e) {
    if (invalidBehaviourType != kExceptionOnInvalidReference) {
      return nil;
    }
    @throw e;
  }

  if ([definition isLazy]) {
    // @todo Serve a proxy object
  }

  _loading[serviceId] = @TRUE;

  @try {
    service = [self createServiceNamed:serviceId fromDefinition:definition];
  }
  @catch (NSException *e) {
    if (invalidBehaviourType != kExceptionOnInvalidReference) {
      return nil;
    }
    @throw e;
  }
  @finally {
    [_loading removeObjectForKey:serviceId];
  }

  return service;
}

- (id)createServiceNamed:(NSString *)serviceId fromDefinition:(GCDIDefinition *)definition {
  if ([definition isSynthetic]) {
    [NSException raise:GCDIRequestedSyntheticService
                format:@"Cannot construct synthetic service \"%@\"", serviceId];
  }

  if ([definition isDepreciated]) {
    NSLog(@"[GCDIContainer %p] %@", self, [definition getDepreciationMessage]);
  }

  id service;

  // Get the service either from the factory, or by initialising a new instance
  // of the service class.
  NSInvocation *invocation;
  if (definition.factory) {
    id factory = [self resolveServices:definition.factory];
    invocation = [self buildInvocationForClass:[factory class]
                                  withSelector:definition.pSelector
                                  andArguments:definition.arguments];

    // Invoke the required method on the factory object.
    [invocation setTarget:factory];
    [invocation invoke];

    void *tempService;
    [invocation getReturnValue:&tempService];
    service = (__bridge id)tempService;
  }
  else {
    // Invoke the required initialisation on the service.
    Class klass = NSClassFromString([_parameterBag resolveParameterPlaceholders:definition.klass]);
    if (!klass) {
      [NSException raise:GCDIServiceNotFoundException
                  format:@"Service with Class \"%@\" not found. %@", klass, definition];
    }

    invocation = [self buildInvocationForClass:klass
                                  withSelector:definition.pSelector ?: @"init"
                                  andArguments:definition.arguments];

    service = [klass alloc];
    [invocation setTarget:service];
    // Invoke the method to get the service object.
    [invocation invoke];
  }

  for (GCDIMethodCall *methodCall in definition.methodCalls) {
    NSInvocation *setupInvocation = [self buildInvocationForClass:[service class]
                                                     withSelector:methodCall.pSelector
                                                     andArguments:methodCall.arguments];
    if (!invocation) {
      [NSException raise:NSInvalidArgumentException
                  format:@"Could not invoke method call \"%@\" on service \"%@\"", methodCall.pSelector, serviceId];
    }

    [setupInvocation invokeWithTarget:service];
  }

  // Configure properties on the service using setters and values.
  for (NSString *setter in definition.setters.allKeys) {
    invocation = [self buildInvocationForClass:[service class]
                                  withSelector:setter
                                  andArguments:@[definition.setters[setter]]];
    if (!invocation) {
      [NSException raise:NSInvalidArgumentException
                  format:@"Could not apply setter \"%@\" to service \"%@\"", setter, serviceId];
    }

    [invocation invokeWithTarget:service];
  }

  // Invoke the configurator and pass the service as the argument.
  // @todo support configurator arguments.
  if (definition.configurator) {
    id configurator = [self resolveServices:definition.configurator];
    invocation = [self buildInvocationForClass:[configurator class]
                                  withSelector:definition.configuratorSelector
                                  andArguments:@[service]];
    if (!invocation) {
      [NSException raise:NSInvalidArgumentException
                  format:@"Could not invoke configurator \"%@\" to service \"%@\"", definition.configurator, serviceId];
    }

    [invocation invokeWithTarget:service];
  }

  if ([definition isShared]) {
    _services[serviceId] = service;
  }

  return service;
}

- (NSInvocation *)buildInvocationForClass:(Class)klass withSelector:(NSString *)pSelector andArguments:(NSArray *)arguments {
  // Resolve selector name, if necessary.
  pSelector = [self.parameterBag resolveParameterPlaceholders:pSelector];
  pSelector = [self.parameterBag escapeParameterPlaceholders:pSelector];
  SEL sel = NSSelectorFromString(pSelector);

  NSMethodSignature *methodSignature = [klass instanceMethodSignatureForSelector:sel];
  if (!methodSignature) {
    return nil;
  }

  if (arguments.count != methodSignature.numberOfArguments - 2) {
    [NSException raise:NSInvalidArgumentException
                format:@"Invalid amount of arguments (%d/%d) provided for method signature for selector \"%@\"", arguments.count, methodSignature.numberOfArguments - 2, pSelector];
  }

  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
  [invocation setSelector:sel];
  [self addArguments:arguments toInvocation:invocation];
  return invocation;
}

- (void)addArguments:(NSArray *)arguments toInvocation:(NSInvocation *)invocation {
  arguments = [_parameterBag resolveParameterPlaceholders:arguments];
  arguments = [_parameterBag unescapeParameterPlaceholders:arguments];
  arguments = [self resolveServices:arguments];

  NSInteger i = 2;
  for (id argument in arguments) {
    [invocation setArgument:&argument atIndex:i];
  }
}

- (id)resolveServices:(id)_resolveServices {
  if ([_resolveServices isKindOfClass:[NSArray class]]) {
    NSArray *resolveServices = _resolveServices;
    NSMutableArray *resolvedServices = @[].mutableCopy;

    for (NSUInteger i = 0; i < resolveServices.count; i++) {
      resolvedServices[i] = [self resolveServices:resolveServices[i]];
    }

    return resolvedServices.copy;
  }
  else if ([_resolveServices isKindOfClass:[GCDIReference class]]) {
    GCDIReference *reference = _resolveServices;
    return [self getServiceNamed:reference.serviceId
            withInvalidBehaviour:reference.invalidBehaviourType];
  }
  else if ([_resolveServices isKindOfClass:[GCDIDefinition class]]) {
    GCDIDefinition *definition = _resolveServices;
    return [self createServiceNamed:nil fromDefinition:definition];
  }

  return _resolveServices;
}

- (void)setService:(NSString *)serviceId instance:(id)service {
  if (_definitions[serviceId]) {
    _obsoleteDefinitions[serviceId] = _definitions[serviceId];
    [_definitions removeObjectForKey:serviceId];
  }

  [super setService:serviceId instance:service];
}

- (BOOL)hasService:(NSString *)serviceId {
  return [super hasService:serviceId] || (bool) _definitions[serviceId];
}

- (NSArray *)getServiceIds {
  NSMutableOrderedSet *serviceIds = [NSMutableOrderedSet orderedSetWithArray:[super getServiceIds]];
  [serviceIds addObjectsFromArray:_definitions.allKeys.copy];
  return [serviceIds array];
}

- (void)registerService:(NSString *)serviceId forClass:(Class)klass andSelector:(SEL)pSelector {
  [self setService:serviceId definition:^(GCDIDefinition *definition) {
    [definition setClass:klass];
    [definition setSEL:pSelector];
  }];
}

# pragma mark - Definition methods

- (void)addDefinitions:(NSDictionary *)definitions {
  for (NSString *serviceId in definitions) {
    [self setService:serviceId definition:definitions[serviceId]];
  }
}

- (void)setDefinitions:(NSDictionary *)definitions {
  _definitions = @{}.mutableCopy;
  [self addDefinitions:definitions];
}

- (NSDictionary *)getDefinitions {
  return _definitions.copy;
}

- (void)setService:(NSString *)serviceId definition:(id)definition {
  // @todo retire ability to pass in pre-configured definition object.
  if (![definition isKindOfClass:objc_getClass("NSBlock")] && ![definition isKindOfClass:[GCDIDefinition class]]) {
    [NSException raise:NSInvalidArgumentException
                format:@"Definition object must be an instance of GCDIDefinition, or block of signature GCDIDefinitionBlock."];
  }

  serviceId = [serviceId lowercaseString];
  [_aliases removeObjectForKey:serviceId];
  _definitions[serviceId] = definition;
}

- (id)getDefinitionForService:(NSString *)serviceId {
  serviceId = [serviceId lowercaseString];
  if (!_definitions[serviceId]) {
    [NSException raise:GCDIServiceNotFoundException
                format:@"Service \"%@\" not found", serviceId];
  }
  else if ([_definitions[serviceId] isKindOfClass:objc_getClass("NSBlock")]) {
    // Support Obj-C blocks that build definitions JIT.
    GCDIDefinitionBlock setupDefinition = _definitions[serviceId];
    GCDIDefinition *definition = [[GCDIDefinition alloc] init];
    setupDefinition(definition);
    return definition;
  }

  return _definitions[serviceId];
}

- (BOOL)hasDefinitionForService:(NSString *)serviceId {
  return (BOOL) _definitions[serviceId];
}

# pragma mark Aliases

- (void)setAlias:(NSString *)alias to:(id)_serviceId {
  alias = [alias lowercaseString];

  if ([_serviceId isKindOfClass:[NSString class]]) {
    _serviceId = [GCDIAlias aliasForId:_serviceId];
  }
  else if (![_serviceId isKindOfClass:[GCDIAlias class]]) {
    [NSException raise:NSInvalidArgumentException
                format:@"Alias must be of type NSString or GCDIAlias."];
  }

  GCDIAlias *serviceId = _serviceId;

  if ([alias isEqualToString:serviceId.aliasId]) {
    [NSException raise:GCDICircularReferenceException
                format:@"Circular reference found on alias \"%@\"", alias];
  }

  [_definitions removeObjectForKey:alias];
  _aliasDefinitions[alias] = serviceId;
}

- (void)addAliases:(NSDictionary *)aliases {
  for (NSString *alias in aliases.allKeys) {
    [self setAlias:alias to:aliases[alias]];
  }
}

- (void)setAliases:(NSDictionary *)aliases {
  _aliasDefinitions = @{}.mutableCopy;
  [self addAliases:_aliases];
}

- (void)removeAlias:(NSString *)alias {
  [_aliasDefinitions removeObjectForKey:[alias lowercaseString]];
}

- (BOOL)hasAlias:(NSString *)alias {
  return (BOOL) _aliasDefinitions[[alias lowercaseString]];
}

- (GCDIAlias *)getAlias:(NSString *)alias {
  return _aliasDefinitions[[alias lowercaseString]];
}

# pragma mark Tagging

- (NSDictionary *)findServiceIdsForTag:(NSString *)name {
  NSMutableDictionary *services = @{}.mutableCopy;

  id tag;
  for (NSString *id in _definitions.allKeys) {
    // @todo improve efficiency of tag searching, this operation becomes more
    // expensive without storing all definitions all of the time.
    GCDIDefinition *definition = [self getDefinitionForService:id];
    if ((tag = [definition getTag:name])) {
      services[id] = tag;
    }
  }

  return services.copy;
}

# pragma mark Storyboard injection

- (void)setContainerInjectsIntoStoryboards:(BOOL)injects {
  if (injects) {
    registeredStoryboardContainers[_identifier] = self;
  }
  else {
    [registeredStoryboardContainers removeObjectForKey:_identifier];
  }
}

@end