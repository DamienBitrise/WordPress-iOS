#import "Coordinate.h"
#import <WordPressUIKit/WPTableViewCell.h>

@interface PostGeolocationCell : WPTableViewCell

- (void)setCoordinate:(Coordinate *)coordinate andAddress:(NSString *)address;

@end
