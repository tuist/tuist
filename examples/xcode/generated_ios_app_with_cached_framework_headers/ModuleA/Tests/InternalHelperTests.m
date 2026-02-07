#import <XCTest/XCTest.h>
#import "InternalHelper.h"

@interface InternalHelperTests : XCTestCase
@end

@implementation InternalHelperTests

- (void)testInternalValue
{
    InternalHelper *helper = [[InternalHelper alloc] init];
    XCTAssertEqualObjects(@"InternalHelper.internalValue", [helper internalValue]);
}

@end
