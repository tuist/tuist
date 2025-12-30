#import "Framework.h"

NSString *BarGreeting(void)
{
    return @"Bar header ready";
}

NSString *BazGreeting(void)
{
    return @"Baz header ready";
}

NSString *FrameworkGreeting(void)
{
    return [NSString stringWithFormat:@"%@ + %@", BarGreeting(), BazGreeting()];
}
