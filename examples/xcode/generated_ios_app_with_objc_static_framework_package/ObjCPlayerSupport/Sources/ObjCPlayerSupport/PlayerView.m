#import "PlayerView.h"

@implementation PlayerView

+ (NSString *)playerName
{
    return [SWIFTPM_MODULE_BUNDLE bundlePath];
}

@end
