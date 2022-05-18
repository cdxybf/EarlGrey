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

#import "GREYWaitFunctions.h"
#import "EarlGrey.h"
#import "GREYHostApplicationDistantObject+TwistViewTest.h"
#import "BaseIntegrationTest.h"

// Adjust if this test is flaky.
static const CGFloat kRotationAccuracyThreshold = 0.1;

@interface TwistViewTest : BaseIntegrationTest
@end

@implementation TwistViewTest

- (void)setUp {
  [super setUp];
  [self openTestViewNamed:@"Gesture Tests"];
}

- (void)testFastClockwiseRotation {
  CGFloat angleDelta = -kGREYTwistAngleDefault;
  CGFloat rotationBeforeTwist = [self ftr_gestureViewRotation];
  [[EarlGrey selectElementWithMatcher:grey_accessibilityLabel(@"Grey Box")]
      performAction:grey_twistFastWithAngle(angleDelta)];
  CGFloat rotationAfterTwist = [self ftr_gestureViewRotation];
  BOOL success = [self rotationFromAngle:rotationBeforeTwist
                                 toAngle:rotationAfterTwist
                            movedByAngle:angleDelta];
  GREYAssert(success, @"Rotation before twist - %@ and after twist - %@ must differ by < %@.",
             @(rotationBeforeTwist), @(rotationAfterTwist), @(angleDelta));
}

- (void)testFastCounterClockwiseRotation {
  CGFloat angleDelta = kGREYTwistAngleDefault;
  CGFloat rotationBeforeTwist = [self ftr_gestureViewRotation];
  [[EarlGrey selectElementWithMatcher:grey_accessibilityLabel(@"Grey Box")]
      performAction:grey_twistFastWithAngle(angleDelta)];
  CGFloat rotationAfterTwist = [self ftr_gestureViewRotation];
  BOOL success = [self rotationFromAngle:rotationBeforeTwist
                                 toAngle:rotationAfterTwist
                            movedByAngle:angleDelta];
  GREYAssert(success, @"Rotation before twist - %@ and after twist - %@ must differ by < %@.",
             @(rotationBeforeTwist), @(rotationAfterTwist), @(angleDelta));
}

- (void)testSlowClockwiseRotation {
  CGFloat angleDelta = -kGREYTwistAngleDefault;
  CGFloat rotationBeforeTwist = [self ftr_gestureViewRotation];
  [[EarlGrey selectElementWithMatcher:grey_accessibilityLabel(@"Grey Box")]
      performAction:grey_twistSlowWithAngle(angleDelta)];
  CGFloat rotationAfterTwist = [self ftr_gestureViewRotation];
  BOOL success = [self rotationFromAngle:rotationBeforeTwist
                                 toAngle:rotationAfterTwist
                            movedByAngle:angleDelta];
  GREYAssert(success, @"Rotation before twist - %@ and after twist - %@ must differ by < %@.",
             @(rotationBeforeTwist), @(rotationAfterTwist), @(angleDelta));
}

- (void)testSlowCounterClockwiseRotation {
  CGFloat angleDelta = kGREYTwistAngleDefault;
  CGFloat rotationBeforeTwist = [self ftr_gestureViewRotation];
  [[EarlGrey selectElementWithMatcher:grey_accessibilityLabel(@"Grey Box")]
      performAction:grey_twistSlowWithAngle(angleDelta)];
  CGFloat rotationAfterTwist = [self ftr_gestureViewRotation];
  BOOL success = [self rotationFromAngle:rotationBeforeTwist
                                 toAngle:rotationAfterTwist
                            movedByAngle:angleDelta];
  GREYAssert(success, @"Rotation before twist - %@ and after twist - %@ must differ by < %@.",
             @(rotationBeforeTwist), @(rotationAfterTwist), @(angleDelta));
}

#pragma mark - Helper methods

/**
 * Returns the image view controller frame.
 */
- (CGFloat)ftr_gestureViewRotation {
  GREYHostApplicationDistantObject *host = GREYHostApplicationDistantObject.sharedInstance;
  return [host rotationForTwistView];
}

- (BOOL)rotationFromAngle:(CGFloat)rotationBeforeTwist
                  toAngle:(CGFloat)rotationAfterTwist
             movedByAngle:(CGFloat)expectedAngleDelta {
  CGFloat computedRotation = rotationAfterTwist - rotationBeforeTwist;
  CGFloat error = fabs(computedRotation - expectedAngleDelta);
  return error < kRotationAccuracyThreshold;
}

@end
