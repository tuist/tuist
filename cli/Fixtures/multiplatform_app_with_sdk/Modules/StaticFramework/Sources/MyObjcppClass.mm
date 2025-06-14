#import "MyObjcppClass.h"

#include <iostream>

@implementation MyObjcppClass

- (void)hello
{
    std::cout << "Hello from cpp" << std::endl;
}

@end
