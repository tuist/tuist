#import <XCTest/XCTest.h>
#import "ClassA.h"

@interface ClassAObjCTests : XCTestCase
@end

@implementation ClassAObjCTests

- (void)testHello
{
    ClassA *sut = [[ClassA alloc] init];
    XCTAssertEqualObjects(@"ClassA.hello", [sut hello]);
}

@end
