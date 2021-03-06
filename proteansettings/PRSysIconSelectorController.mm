#import "PRSysIconSelectorController.h"
#import <AppList/AppList.h>
#import <libactivator/libactivator.h>
#import <SettingsKit/SKSpecifierParser.h>
#import <objc/runtime.h>
#import <Preferences/PSTableCell.h>
#define PLIST_NAME @"/var/mobile/Library/Preferences/com.efrederickson.protean.settings.plist"
#import <objc/runtime.h>
#import "../Protean.h"

NSString* const vectorIconPath = @"/Library/Protean/TranslatedVectors~cache/";
NSString* const iconPath = @"/Library/Protean/Images.bundle";
static UIImage* defaultIcon;
static NSMutableArray* statusIcons;
NSString* const SilverIconRegexPattern = @"PR_(.*?)(_Count_(Large)?\\d\\d?)?(?:@.*|)(?:~.*|).png";
static NSMutableArray *searchedIcons;
NSArray *canHaveImages = @[ @1, @2, @11, @12, @13, @16, @17, @19, @20, @21, @22];
NSArray *canSupportExtendedOptions = @[ @0, // Custom time, show on LS, lowercase am/pm, spell out  - 4 options              - Done
                                        @3, // Signal RSSI, replace with number (TODO) (e.g. 3 for 3 bars) - 2 option        - Signal RSSI done
                                        @5, // Wifi/Data RSSI           - 1 option                                           - Done
                                        //@8, // Battery Percent, colors  - 3 options                                          - NOPE
                                        @4, // Custom Carrier/carrier timestr - 2 options                                    - Done
                                        ];

NSDictionary *extendedOptionsCounts = @{
    @0: @4,
    @3: @1,
    @5: @1,
    @8: @0, // <- battery percentage, TODO
    @4: @2,  
};

@interface PSTableCell (Protean)
+(PSTableCell *)switchCellWithFrame:(CGRect)frame specifier:(PSSpecifier *)specifier;
@end

@interface PSViewController (Protean)
-(void) viewDidLoad;
-(void) viewWillDisappear:(BOOL)animated;
-(void) setView:(id)view;
-(void) setTitle:(NSString*)title;
@end

@interface PRSysIconSelectorController () {
    NSString *checkedIcon;
    int tapAction;
    int _raw_id;
    BOOL supportsExtendedOptions;
}
@end

extern UIImage *imageFromName(NSString *name);
extern NSString *nameForDescription(NSString *desc);
extern UIImage *iconForDescription(NSString *desc);
UIImage *resizeImage(UIImage *icon)
{
	float maxWidth = 20.0f;
	float maxHeight = 20.0f;
    
	CGSize size = CGSizeMake(maxWidth, maxHeight);
	CGFloat scale = 1.0f;
    
	// the scale logic below was taken from
	// http://developer.appcelerator.com/question/133826/detecting-new-ipad-3-dpi-and-retina
	if ([[UIScreen mainScreen] respondsToSelector:@selector(displayLinkWithTarget:selector:)])
	{
		if ([UIScreen mainScreen].scale > 1.0f) scale = [[UIScreen mainScreen] scale];
		UIGraphicsBeginImageContextWithOptions(size, false, scale);
	}
	else UIGraphicsBeginImageContext(size);
    
	// Resize image to status bar size and center it
	// make sure the icon fits within the bounds
	CGFloat width = MIN(icon.size.width, maxWidth);
	CGFloat height = MIN(icon.size.height, maxHeight);
    
	CGFloat left = MAX((maxWidth-width)/2, 0);
	left = left > (maxWidth/2) ? maxWidth-(maxWidth/2) : left;
    
	CGFloat top = MAX((maxHeight-height)/2, 0);
	top = top > (maxHeight/2) ? maxHeight-(maxHeight/2) : top;
    
	[icon drawInRect:CGRectMake(left, top, width, height)];
	icon = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
    
	return icon;
}

@implementation PRSysIconSelectorController

-(id)initWithAppName:(NSString*)appName identifier:(NSString*)identifier id:(int)id_
{
	_appName = appName;
	_identifier = identifier;
    _id = [NSString stringWithFormat:@"%d",id_]; // amazing names, right?
    _raw_id = id_;
    supportsExtendedOptions = [canSupportExtendedOptions containsObject:[NSNumber numberWithInt:_raw_id]];
	return [self init];
}

-(void) updateSavedData
{
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_NAME];
    prefs = prefs ?: [NSMutableDictionary dictionary];
    
    prefs[@"images"] = prefs[@"images"] ? [prefs[@"images"] mutableCopy]: [NSMutableDictionary dictionary];
    prefs[@"images"][_id] = [checkedIcon isEqual:@"Default"] ? @"" : checkedIcon;
    
    prefs[@"tapActions"] = prefs[@"tapActions"] ? [prefs[@"tapActions"] mutableCopy]: [NSMutableDictionary dictionary];
    prefs[@"tapActions"][_id] = [NSNumber numberWithInt:tapAction == 1?2:0] ?: @0;
    
    [prefs writeToFile:PLIST_NAME atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
}

-(id)init
{
    checkedIcon = @"";
    tapAction = 0;
    
	if ((self = [super init]) == nil) return nil;
	
	if (!defaultIcon)
        defaultIcon = [[ALApplicationList sharedApplicationList] iconOfSize:ALApplicationIconSizeSmall forDisplayIdentifier:@"com.apple.WebSheet"];
	if (!statusIcons)
	{
		statusIcons = [[NSMutableArray alloc] init];
		NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:SilverIconRegexPattern
                                                                               options:NSRegularExpressionCaseInsensitive error:nil];
        
		for (NSString* path in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:iconPath error:nil])
		{
			NSTextCheckingResult* match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
			if (!match) continue;
			NSString* name = [path substringWithRange:[match rangeAtIndex:1]];
			if (![statusIcons containsObject:name]) [statusIcons addObject:name];
		}

        for (NSString* path in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:vectorIconPath error:nil])
        {
            NSTextCheckingResult* match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
            if (!match) continue;
            NSString* name = [path substringWithRange:[match rangeAtIndex:1]];
            if (![statusIcons containsObject:name]) [statusIcons addObject:name];
        }
		        
        regex = [NSRegularExpression regularExpressionWithPattern:@"Black_ON_(.*?)(?:@.*|)(?:~.*|).png"
                                                          options:NSRegularExpressionCaseInsensitive error:nil];
        
        for (NSString* path in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/System/Library/Frameworks/UIKit.framework" error:nil])
        {
            NSTextCheckingResult* match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
            if (!match) continue;
            NSString* name = [path substringWithRange:[match rangeAtIndex:1]];
            
            if ([name hasPrefix:@"Count"])
                continue;
            
            if (![statusIcons containsObject:name]) [statusIcons addObject:name];
        }
	}
    
    
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_NAME];
    prefs = prefs ?: [NSMutableDictionary dictionary];
    
    checkedIcon = ([prefs[@"images"] mutableCopy] ?: [NSMutableDictionary dictionary])[_id] ?: @"";
    tapAction = [([prefs[@"tapActions"] mutableCopy] ?: [NSMutableDictionary dictionary])[_id] intValue] == 2 ? 1 : 0;
    
    CGRect bounds = [[UIScreen mainScreen] bounds];
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height) style:UITableViewStyleGrouped];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.delegate = self;
	_tableView.dataSource = self;
    [_tableView setEditing:NO];
    [_tableView setAllowsSelection:YES];
    [_tableView setAllowsMultipleSelection:NO];
    [_tableView setAllowsSelectionDuringEditing:YES];
    [_tableView setAllowsMultipleSelectionDuringEditing:NO];
    
    [self setView:_tableView];
    
    [self setTitle:_appName];

    if ([canHaveImages containsObject:[NSNumber numberWithInt:_raw_id]])
    {
        [statusIcons sortUsingComparator: ^(NSString* a, NSString* b) {
            bool e1 = [checkedIcon isEqual:a];
            bool e2 = [checkedIcon isEqual:b];
            if (e1 && e2) {
                return [a caseInsensitiveCompare:b];
            } else if (e1) {
                return (NSComparisonResult)NSOrderedAscending;
            } else if (e2) {
                return (NSComparisonResult)NSOrderedDescending;
            }
            return [a caseInsensitiveCompare:b];
        }];

        _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        _searchBar.delegate = self;
        _searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
        searchDisplayController = [[UISearchDisplayController alloc] initWithSearchBar:_searchBar contentsController:(UIViewController*)self];
        searchDisplayController.delegate = self;
        searchDisplayController.searchResultsDataSource = self;
        searchDisplayController.searchResultsDelegate = self;
    
        UIView *tableHeaderView = [[UIView alloc] initWithFrame:searchDisplayController.searchBar.frame];
        [tableHeaderView addSubview:searchDisplayController.searchBar];
        [_tableView setTableHeaderView:tableHeaderView];

    }
    searchedIcons = [NSMutableArray array];    
    isSearching = NO;

	return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([canHaveImages containsObject:[NSNumber numberWithInt:_raw_id]])
        return isSearching ? 1 : (supportsExtendedOptions ? 3 : 2);
    return supportsExtendedOptions ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (isSearching)
        return searchedIcons.count;

    if (section == 0)
        return 2;
    else if (section == 1 && supportsExtendedOptions)
        return [((NSNumber*)extendedOptionsCounts[[NSNumber numberWithInt:_raw_id]]) intValue];
    else
        return statusIcons.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (isSearching)
        return @"Icons";

    if (section == 0)
        return @"Tap Action";
    else if (section == 1 && supportsExtendedOptions)
        return @"Other Options";
    else
        return @"Icons";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    if (indexPath.section == 0 && isSearching == NO)
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
        if (cell == nil)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];

        NSString *alignmentText = @"";
        if (indexPath.row == 0)
            alignmentText = @"Nothing";
        else if (indexPath.row == 1)
            alignmentText = @"Activator Action";
        
        cell.textLabel.text = alignmentText;
        cell.accessoryType = indexPath.row == tapAction ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    else if (indexPath.section == 1 && supportsExtendedOptions)
    {
        // Extended Options for this cell
        cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
        if (cell == nil)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
        cell.textLabel.text = @"TODO";

        if (_raw_id == 3) // Signal Strength :: RSSI, show number
        {
            cell.textLabel.text = @"Show RSSI";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
            cell.accessoryView = switchView;
            BOOL enabled = [[NSDictionary dictionaryWithContentsOfFile:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"][@"showSignalRSSI"] boolValue];
            [switchView setOn:enabled animated:NO];
            [switchView addTarget:self action:@selector(toggleSignalRSSI:) forControlEvents:UIControlEventValueChanged];
            return cell;
        }
        if (_raw_id == 5) // Wifi/Data RSSI
        {
            cell.textLabel.text = @"Show RSSI";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
            cell.accessoryView = switchView;
            BOOL enabled = [[NSDictionary dictionaryWithContentsOfFile:@"/User/Library/Preferences/com.apple.springboard.plist"][@"SBShowRSSI"] boolValue];
            [switchView setOn:enabled animated:NO];
            [switchView addTarget:self action:@selector(toggleWifiDataRSSI:) forControlEvents:UIControlEventValueChanged];
            return cell;
        }
        if (_raw_id == 4)
        {
            if (indexPath.row == 0)
            {
                UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 21)];
                cell.textLabel.text = @"Custom Carrier:";
                textField.placeholder = @"Default carrier";
                textField.text = [objc_getClass("Protean") getOrLoadSettings][@"serviceString"];
                cell.accessoryView = textField;
                textField.delegate = self;
                textField.tag = 0;
                textField.keyboardType = UIKeyboardTypeDefault;
                textField.returnKeyType = UIReturnKeyDone;

                return cell;
            }
            else
            {
                cell.textLabel.text = @"Use carrier as time format";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
                cell.accessoryView = switchView;
                BOOL enabled = [[objc_getClass("Protean") getOrLoadSettings][@"serviceIsTimeString"] boolValue];
                [switchView setOn:enabled animated:NO];
                [switchView addTarget:self action:@selector(toggleServiceIsTimeStr:) forControlEvents:UIControlEventValueChanged];
                return cell;
            }
        }
        if (_raw_id == 0) // Time
        {
            if (indexPath.row == 0)
            {
                // show on LS
                cell.textLabel.text = @"Show LS Time";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
                cell.accessoryView = switchView;
                BOOL enabled = [[objc_getClass("Protean") getOrLoadSettings][@"showLSTime"] boolValue];
                [switchView setOn:enabled animated:NO];
                [switchView addTarget:self action:@selector(toggleShowLSTime:) forControlEvents:UIControlEventValueChanged];
                return cell;
            }
            else if (indexPath.row == 1)
            {
                // Time format
                UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 21)];
                cell.textLabel.text = @"Time format:";
                textField.placeholder = @"h:mm a";
                textField.text = [objc_getClass("Protean") getOrLoadSettings][@"timeFormat"];
                cell.accessoryView = textField;
                textField.delegate = self;
                textField.tag = 1;
                textField.keyboardType = UIKeyboardTypeDefault;
                textField.returnKeyType = UIReturnKeyDone;

                return cell;
            }
            else if (indexPath.row == 2)
            {
                // lowercase AM/PM
                cell.textLabel.text = @"Lowercase AM/PM";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
                cell.accessoryView = switchView;
                BOOL enabled = [[objc_getClass("Protean") getOrLoadSettings][@"lowercaseAMPM"] boolValue];
                [switchView setOn:enabled animated:NO];
                [switchView addTarget:self action:@selector(toggleLowercaseAMPM:) forControlEvents:UIControlEventValueChanged];
                return cell;
            }
            else if (indexPath.row == 3)
            {
                // spell out time
                cell.textLabel.text = @"Spell out time (12h)";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
                cell.accessoryView = switchView;
                BOOL enabled = [[objc_getClass("Protean") getOrLoadSettings][@"spellOut"] boolValue];
                [switchView setOn:enabled animated:NO];
                [switchView addTarget:self action:@selector(toggleSpellOutTime:) forControlEvents:UIControlEventValueChanged];
                return cell;
            }
        }
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"IconCell"];
        if (cell == nil)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IconCell"];

        if (isSearching)
        {
            NSString *name = searchedIcons.count < indexPath.row ? @"" : searchedIcons[indexPath.row];
            cell.textLabel.text = name;
            cell.imageView.image = imageFromName(name);
            cell.accessoryType = [name isEqual:checkedIcon] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
        else if (indexPath.row == 0)
        {
            cell.textLabel.text = @"Default";
            cell.imageView.image = resizeImage(iconForDescription(_identifier));
            cell.accessoryType = [checkedIcon isEqual:@""] || [checkedIcon isEqual:@"Default"] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
        else
        {
            cell.textLabel.text = statusIcons[indexPath.row - 1];
            cell.imageView.image = imageFromName(statusIcons[indexPath.row - 1]);
            cell.accessoryType = [cell.textLabel.text isEqual:checkedIcon] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    }
    return cell;
}

-(void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
    //[self tableView:tableView didDeselectRowAtIndexPath:indexPath];

    if (indexPath.section == 0 && !isSearching)
    {
        tapAction = indexPath.row;
        
        if (tapAction == 1) // Activator
        {
            id activator = objc_getClass("LAEventSettingsController");
            if (!activator)
            {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Protean" message:@"Activator must be installed to use this feature." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                [alert show];
            }
            LAEventSettingsController *vc = [[objc_getClass("LAEventSettingsController") alloc] initWithModes:@[LAEventModeSpringBoard,LAEventModeApplication, LAEventModeLockScreen] eventName:[NSString stringWithFormat:@"%@%@", @"com.efrederickson.protean-",_id]];
            [self.rootController pushViewController:vc animated:YES];
        }
    }
    else if (indexPath.section == 1 && supportsExtendedOptions && isSearching == NO)
        return;
    else
    {
        checkedIcon = cell.textLabel.text;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);
    }
    
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
    [self updateSavedData];
    [_tableView reloadData];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if ([canHaveImages containsObject:[NSNumber numberWithInt:_raw_id]])
    {
        if (section == 0 || (supportsExtendedOptions && section == 1))
            return nil;
    }
    else
    {
        if (section == 0 && supportsExtendedOptions)
            return nil;
    }

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 5, [UIScreen mainScreen].bounds.size.width, 80)];
    footer.backgroundColor = [UIColor clearColor];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:footer.frame];
    lbl.backgroundColor = [UIColor clearColor];
    lbl.text = [canHaveImages containsObject:[NSNumber numberWithInt:_raw_id]] ? @"\nRespring to apply changes\nto System Icons." : @"Sorry, this icon cannot be\nthemed with Protean.";
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 3;
    lbl.font = [UIFont fontWithName:@"HelveticaNueue-UltraLight" size:5];
    lbl.textColor = [UIColor darkGrayColor];
    lbl.lineBreakMode = NSLineBreakByWordWrapping;
    [footer addSubview:lbl];
    
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if ([canHaveImages containsObject:[NSNumber numberWithInt:_raw_id]])
    {
        if (supportsExtendedOptions)
        {
            if (section == 0)
            {
                return 0;
            }
            else if (section == 1)
                return 0;
        }
        return section == 2 ? 80 : 0;
    }
    else
    {
        if (supportsExtendedOptions && section == 0)
            return 0;
    }
    return 80.0;
}

-(void)searchBar:(UISearchBar*)searchBar textDidChange:(NSString*)searchText
{
    searchedIcons = [NSMutableArray array];

    for (NSString* name in statusIcons)
    {
        if ([name rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound)
            [searchedIcons addObject:name];
    }

    [_tableView reloadData];
}

-(void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    UISearchBar *searchBar = searchDisplayController.searchBar;
    CGRect searchBarFrame = searchBar.frame;
    
    searchBarFrame.origin.y = 0;
    searchDisplayController.searchBar.frame = searchBarFrame;
}

- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller {
    isSearching = YES;
}

-(void)searchDisplayControllerWillEndSearch:(UISearchDisplayController *)controller {
    isSearching = NO;
    [_tableView reloadData];
}

-(UIColor*) tintColor { return [UIColor colorWithRed:79/255.0f green:176/255.0f blue:136/255.0f alpha:1.0f]; }

- (void)viewWillAppear:(BOOL)animated {
    ((UIView*)self.view).tintColor = self.tintColor;
    self.navigationController.navigationBar.tintColor = self.tintColor;

    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    ((UIView*)self.view).tintColor = nil;
    self.navigationController.navigationBar.tintColor = nil;
}

-(void) toggleWifiDataRSSI:(id)sender
{
    UISwitch* switchControl = sender;
    BOOL showRssi = switchControl.on;
    [super setPreferenceValue:@(showRssi) specifier:[SKSpecifierParser specifiersFromArray:@[
             @{
                 @"cell": @"PSSwitchCell",
                 @"default": @NO,
                 @"defaults": @"com.apple.springboard",
                 @"key": @"SBShowRSSI",
                 @"label": @"Show Wifi/Data RSSI",
                 @"PostNotification": @"com.apple.springboard/Prefs",
                 }] forTarget:(PSListController*)self][0]]; // lol, needs a specifier so lets give it what it "would" be
}

-(void) toggleSignalRSSI:(id)sender
{
    UISwitch* switchControl = sender;
    BOOL showRssi = switchControl.on;
    NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
    [dict setObject:@(showRssi) forKey:@"showSignalRSSI"];
    [dict writeToFile:plistName atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);
}

-(void) toggleServiceIsTimeStr:(id) sender
{
    UISwitch* switchControl = sender;
    BOOL value = switchControl.on;
    NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
    [dict setObject:@(value) forKey:@"serviceIsTimeString"];
    [dict writeToFile:plistName atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);
}

-(void) toggleShowLSTime:(id)sender
{
    UISwitch* switchControl = sender;
    BOOL value = switchControl.on;
    NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
    [dict setObject:@(value) forKey:@"showLSTime"];
    [dict writeToFile:plistName atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);

}
-(void) toggleSpellOutTime:(id)sender
{
    UISwitch* switchControl = sender;
    BOOL value = switchControl.on;
    NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
    [dict setObject:@(value) forKey:@"spellOut"];
    [dict writeToFile:plistName atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);

}
-(void) toggleLowercaseAMPM:(id)sender
{
    UISwitch* switchControl = sender;
    BOOL value = switchControl.on;
    NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
    [dict setObject:@(value) forKey:@"lowercaseAMPM"];
    [dict writeToFile:plistName atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);

}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if(textField.tag == 0)
    {
        NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
        [dict setObject:textField.text forKey:@"serviceString"];
        [dict writeToFile:plistName atomically:YES];

        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);
    }
    else if (textField.tag == 1)
    {
        NSString *plistName = [NSString stringWithFormat:@"/User/Library/Preferences/com.efrederickson.protean.settings.plist"];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistName];
        [dict setObject:textField.text forKey:@"timeFormat"];
        [dict writeToFile:plistName atomically:YES];

        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/reloadSettings"), nil, nil, YES);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.efrederickson.protean/refreshStatusBar"), nil, nil, YES);
    }
    [textField resignFirstResponder];
    return YES;
}
@end
