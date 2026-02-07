#import "ClassB.h"
#import <ModuleA/ClassA.h>

@implementation ClassB

- (NSString *)hello
{
    ClassA *classA = [[ClassA alloc] init];
    return [NSString stringWithFormat:@"ClassB.hello -> %@", [classA hello]];
}

@end
