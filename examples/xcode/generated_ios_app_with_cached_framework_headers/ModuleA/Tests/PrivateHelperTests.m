#import <XCTest/XCTest.h>
#import <ModuleA/PrivateHelper.h>

@interface PrivateHelperTests : XCTestCase
@end

@implementation PrivateHelperTests

- (void)testPrivateValue
{
    PrivateHelper *helper = [[PrivateHelper alloc] init];
    XCTAssertEqualObjects(@"PrivateHelper.privateValue", [helper privateValue]);
}

@end
