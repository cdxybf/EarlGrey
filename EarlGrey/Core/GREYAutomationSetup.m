//
// Copyright 2016 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "Core/GREYAutomationSetup.h"

#import <XCTest/XCTest.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <objc/runtime.h>
#include <signal.h>

#import "Common/GREYDefines.h"
#import "Common/GREYExposed.h"
#import "Common/GREYSwizzler.h"

// Exception handler that was previously installed before we replaced it with our own.
static NSUncaughtExceptionHandler *gPreviousUncaughtExceptionHandler;

// Normal signal handler.
typedef void (*SignalHandler)(int signum);

// When SA_SIGINFO is set, it is an extended signal handler.
typedef void (*SignalHandlerEX)(int signum, struct __siginfo *siginfo, void *context);

// All signals that we want to handle.
static const int gSignals[] = {
  SIGQUIT,
  SIGILL,
  SIGTRAP,
  SIGABRT,
  SIGFPE,
  SIGBUS,
  SIGSEGV,
  SIGSYS,
};

// Total number of signals we handle.
static const int kNumSignals = sizeof(gSignals) / sizeof(gSignals[0]);

// A union of normal and extended signal handler.
typedef union GREYSignalHandlerUnion {
  SignalHandler signalHandler;
  SignalHandlerEX signalHandlerExtended;
} GREYSignalHandlerUnion;

// Saved signal handler with a bit indicating extended or normal handler signature.
typedef struct GREYSignalHandler {
  GREYSignalHandlerUnion handler;
  bool extended;
} GREYSignalHandler;

// All previous signal handlers we replaced with our own.
static GREYSignalHandler gPreviousSignalHandlers[kNumSignals];

#pragma mark - Accessibility On Device

#if !(TARGET_OS_SIMULATOR)

@implementation NSNotificationCenter (GREYAdditions)
/**
 *  Fakes app going into background mode by calling the @c block immediately when
 *  registered to be notified for UIApplicationDidEnterBackgroundNotification
 */
- (id<NSObject>)grey_addObserverForName:(NSString *)name
                                 object:(id)obj
                                  queue:(NSOperationQueue *)queue
                             usingBlock:(void (^)(NSNotification *note))block {
  if ([name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
    block(nil);
    return nil;
  } else {
    return INVOKE_ORIGINAL_IMP4(id<NSObject>,
                                @selector(grey_addObserverForName:object:queue:usingBlock:),
                                name,
                                obj,
                                queue,
                                block);
  }
}
@end

@interface XCUIDevice (GREYExposed)
/**
 *  Exposing method to overwrite it with our own implementation.
 */
- (void)_silentPressButton:(XCUIDeviceButton)buttonType;
@end

@implementation XCUIDevice (GREYAdditions)
/**
 *  No-op method to prevent XCUITest from backgrounding the app when we use private API to enable
 *  accessibility.
 */
- (void)grey_silentPressButton:(XCUIDeviceButton)buttonType {
  // No-op because we don't want the test to background itself.
}
@end

#endif

#pragma mark - Automation Setup

@implementation GREYAutomationSetup

+ (instancetype)sharedInstance {
  static GREYAutomationSetup *sharedInstance = nil;
  static dispatch_once_t token = 0;
  dispatch_once(&token, ^{
    sharedInstance = [[GREYAutomationSetup alloc] initOnce];
  });
  return sharedInstance;
}

- (instancetype)initOnce {
  self = [super init];
  return self;
}

- (void)prepare {
  [self grey_setupCrashHandlers];
  [self grey_enableAccessibility];
  // Force software keyboard.
  [[UIKeyboardImpl sharedInstance] setAutomaticMinimizationEnabled:NO];
  // Turn off auto correction as it interferes with typing on iOS8.2+.
  if (iOS8_2_OR_ABOVE()) {
    [self grey_modifyKeyboardSettings];
  }
}

#pragma mark - Accessibility

// Enables accessibility as it is required for using any property of the accessibility tree.
- (void)grey_enableAccessibility {
#if TARGET_OS_SIMULATOR
  NSLog(@"Enabling accessibility for automation on Simulator.");
  static NSString *path =
      @"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities";
  char const *const localPath = [path fileSystemRepresentation];
  NSAssert(localPath, @"localPath should not be nil");

  void *handle = dlopen(localPath, RTLD_LOCAL);
  NSAssert(handle, @"dlopen couldn't open AccessibilityUtilities at path %s", localPath);

  Class AXBackBoardServerClass = NSClassFromString(@"AXBackBoardServer");
  NSAssert(AXBackBoardServerClass, @"AXBackBoardServer class not found");
  id server = [AXBackBoardServerClass server];
  NSAssert(server, @"server should not be nil");

  [server setAccessibilityPreferenceAsMobile:(CFStringRef)@"ApplicationAccessibilityEnabled"
                                       value:kCFBooleanTrue
                                notification:(CFStringRef)@"com.apple.accessibility.cache.app.ax"];
  [server setAccessibilityPreferenceAsMobile:(CFStringRef)@"AccessibilityEnabled"
                                       value:kCFBooleanTrue
                                notification:(CFStringRef)@"com.apple.accessibility.cache.ax"];
#else // On device
  NSLog(@"Enabling accessibility for automation on Device.");
  char const *const libAccessibilityPath =
      [@"/usr/lib/libAccessibility.dylib" fileSystemRepresentation];
  void *handle = dlopen(libAccessibilityPath, RTLD_LOCAL);
  NSAssert(handle, @"dlopen couldn't open libAccessibility.dylib at path %s", libAccessibilityPath);
  void (*_AXSSetAutomationEnabled)(BOOL) = dlsym(handle, "_AXSSetAutomationEnabled");
  NSAssert(_AXSSetAutomationEnabled, @"Pointer to _AXSSetAutomationEnabled must not be NULL");

  _AXSSetAutomationEnabled(YES);

  Class XCAXClientClass = NSClassFromString(@"XCAXClient_iOS");
  NSAssert(XCAXClientClass, @"XCAXClient_iOS class not found");
  // As part of turning on accessibility, XCUITest tries to background this process.
  // Swizzle to prevent app from being backgrounded.
  GREYSwizzler *swizzler = [[GREYSwizzler alloc] init];
  BOOL swizzleSuccess = [swizzler swizzleClass:[XCUIDevice class]
                         replaceInstanceMethod:@selector(_silentPressButton:)
                                    withMethod:@selector(grey_silentPressButton:)];
  NSAssert(swizzleSuccess, @"Cannot swizzle XCUIDevice _silentPressButton:");
  swizzleSuccess =
      [swizzler swizzleClass:[NSNotificationCenter class]
       replaceInstanceMethod:@selector(addObserverForName:object:queue:usingBlock:)
                  withMethod:@selector(grey_addObserverForName:object:queue:usingBlock:)];
  NSAssert(swizzleSuccess,
           @"Cannot swizzle NSNotificationCenter addObserverForName:object:queue:usingBlock:");
  // Call which backgrounds the app and enables accessibility on iOS 9 and below. For iOS 10
  // another call is made below to load accessibility.
  id XCAXClient = [XCAXClientClass sharedClient];
  NSAssert(XCAXClient, @"XCAXClient_iOS sharedClient doesn't exist.");
  // Accessibility should be enabled...Reset swizzled implementations to original.
  BOOL reset = [swizzler resetInstanceMethod:@selector(_silentPressButton:)
                                       class:[XCUIDevice class]];
  NSAssert(reset, @"Failed to reset swizzled method _silentPressButton:");
  reset = [swizzler resetInstanceMethod:@selector(addObserverForName:object:queue:usingBlock:)
                                  class:[NSNotificationCenter class]];
  NSAssert(reset, @"Failed to reset swizzled method addObserverForName:object:queue:usingBlock:");
  if (iOS10_OR_ABOVE()) {
    void *unused = 0;
    [XCAXClient loadAccessibility:&unused];
  }
#endif
}

// Modifies the autocorrect and predictive typing settings to turn them off through the
// keyboard settings bundle.
- (void)grey_modifyKeyboardSettings {
  static NSString *const keyboardSettingsPrefBundlePath =
      @"/System/Library/PreferenceBundles/KeyboardSettings.bundle/KeyboardSettings";
  static NSString *const keyboardControllerClassName = @"KeyboardController";
  id keyboardControllerInstance =
      [self grey_classInstanceFromBundleAtPath:keyboardSettingsPrefBundlePath
                                 withClassName:keyboardControllerClassName];
  [keyboardControllerInstance setAutocorrectionPreferenceValue:@(NO) forSpecifier:nil];
  [keyboardControllerInstance setPredictionPreferenceValue:@(NO) forSpecifier:nil];
}

// For the provided bundle @c path, we use the actual @c className of the class to extract and
// return a class instance that can be modified.
- (id)grey_classInstanceFromBundleAtPath:(NSString *)path withClassName:(NSString *)className {
  NSParameterAssert(path);
  NSParameterAssert(className);
  char const *const preferenceBundlePath = [path fileSystemRepresentation];
  void *handle = dlopen(preferenceBundlePath, RTLD_LAZY);
  if (!handle) {
    NSAssert(NO, @"dlopen couldn't open settings bundle at path bundle %@", path);
  }

  Class klass = NSClassFromString(className);
  if (!klass) {
    NSAssert(NO, @"Couldn't find %@ class", klass);
  }

  id klassInstance = [[klass alloc] init];
  if (!klassInstance) {
    NSAssert(NO, @"Couldn't initialize controller for class: %@", klass);
  }

  return klassInstance;
}

#pragma mark - Crash Handlers

// Installs the default handler and raises the specified @c signum.
static void grey_installDefaultHandlerAndRaise(int signum) {
  // Install default and re-raise the signal.
  struct sigaction defaultSignalAction;
  memset(&defaultSignalAction, 0, sizeof(defaultSignalAction));
  int result = sigemptyset(&defaultSignalAction.sa_mask);
  if (result != 0) {
    char *sigEmptyError = "Unable to empty sa_mask";
    write(STDERR_FILENO, sigEmptyError, strlen(sigEmptyError));
    kill(getpid(), SIGKILL);
  }

  defaultSignalAction.sa_handler = SIG_DFL;
  if (sigaction(signum, &defaultSignalAction, NULL) == 0) {
    // re-raise with default in place.
    raise(signum);
  }
}

// Call only asynchronous-safe functions within signal handlers
// Learn more: https://www.securecoding.cert.org/confluence/display/c/SIG00-C.+Mask+signals+handled+by+noninterruptible+signal+handlers
static void grey_signalHandler(int signum) {
  char *signalCaught = "Signal caught: ";
  char *signalString = strsignal(signum);
  write(STDERR_FILENO, signalCaught, strlen(signalCaught));
  write(STDERR_FILENO, signalString, strlen(signalString));

  write(STDERR_FILENO, "\n", 1);
  static const int kMaxStackSize = 128;
  void *callStack[kMaxStackSize];
  const int numFrames = backtrace(callStack, kMaxStackSize);
  backtrace_symbols_fd(callStack, numFrames, STDERR_FILENO);

  int signalIndex = -1;
  for (size_t i = 0; i < kNumSignals; i++) {
    if (signum == gSignals[i]) {
      signalIndex = (int)i;
    }
  }

  if (signalIndex == -1) {  // Not found.
    char *signalNotFound = "Caught signal not in handled signal array: ";
    write(STDERR_FILENO, signalNotFound, strlen(signalNotFound));
    write(STDERR_FILENO, signalString, strlen(signalString));
    kill(getpid(), SIGKILL);
  }

  GREYSignalHandler previousSignalHandler = gPreviousSignalHandlers[signalIndex];
  if (previousSignalHandler.extended) {
    // We don't handle these yet, simply re-raise with default handler.
    grey_installDefaultHandlerAndRaise(signum);
  } else {
    SignalHandler signalHandler = previousSignalHandler.handler.signalHandler;
    if (signalHandler == SIG_DFL) {
      grey_installDefaultHandlerAndRaise(signum);
    } else if (signalHandler == SIG_IGN) {
      // Ignore.
    } else {
      signalHandler(signum);
    }
  }
}

static void grey_uncaughtExceptionHandler(NSException *exception) {
  NSLog(@"Uncaught exception: %@; Stack trace:\n%@",
        exception,
        [exception.callStackSymbols componentsJoinedByString:@"\n"]);
  if (gPreviousUncaughtExceptionHandler) {
    gPreviousUncaughtExceptionHandler(exception);
  } else {
    exit(EXIT_FAILURE);
  }
}

- (void)grey_setupCrashHandlers {
  NSLog(@"Crash handler setup started.");

  struct sigaction signalAction;
  memset(&signalAction, 0, sizeof(signalAction));
  int result = sigemptyset(&signalAction.sa_mask);
  if (result != 0) {
    NSLog(@"Unable to empty sa_mask. Return value:%d", result);
    exit(EXIT_FAILURE);
  }
  signalAction.sa_handler = &grey_signalHandler;

  for (size_t i = 0; i < kNumSignals; i++) {
    int signum = gSignals[i];
    struct sigaction previousSigAction;
    memset(&previousSigAction, 0, sizeof(previousSigAction));

    GREYSignalHandler *previousSignalHandler = &gPreviousSignalHandlers[i];
    memset(previousSignalHandler, 0, sizeof(gPreviousSignalHandlers[0]));

    int returnValue = sigaction(signum, &signalAction, &previousSigAction);
    if (returnValue != 0) {
      NSLog(@"Error installing %s handler. errorno:'%s'.", strsignal(signum), strerror(errno));
      previousSignalHandler->extended = false;
      previousSignalHandler->handler.signalHandler = SIG_IGN;
    } else if (previousSigAction.sa_flags & SA_SIGINFO) {
      previousSignalHandler->extended = true;
      previousSignalHandler->handler.signalHandlerExtended =
          previousSigAction.__sigaction_u.__sa_sigaction;
    } else {
      previousSignalHandler->extended = false;
      previousSignalHandler->handler.signalHandler = previousSigAction.__sigaction_u.__sa_handler;
    }
  }
  // Register the handler for uncaught exceptions.
  gPreviousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
  NSSetUncaughtExceptionHandler(&grey_uncaughtExceptionHandler);

  NSLog(@"Crash handler setup completed.");
}

@end
