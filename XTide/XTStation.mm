//
//  XTStation.mm
//  XTideCocoa
//
//  Created by Lee Ann Rucker on 4/12/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XTStationInt.h"
#import "XTCalendar.h"
#import "XTSettings.h"
#import "XTTideEvent.h"
#import "XTTideEventsOrganizer.h"
#import "XTUtils.h"
#import "PredictionValue.hh"

static NSArray *unitsPrefMap = nil;

@implementation XTStation

+ (NSArray *)unitsPrefMap
{
	if (unitsPrefMap == nil) {
		unitsPrefMap = [NSArray arrayWithObjects:@"x", @"ft", @"m", nil];
	}
	return unitsPrefMap;
}

- (id)initUsingStationRef: (libxtide::StationRef *)aStationRef
{
    if ((self = [super init])) {
        mStation = aStationRef->load();
        if (!mStation) {
            return nil;
        }
        [self updateUnits];
    }
    return self;
}

- (void)dealloc
{
   // Created and owned by self.
   delete mStation;
}

- (NSString *)name
{
    return DstrToNSString(mStation->name);
}

- (void)updateUnits
{
	NSString *unitType = [[NSUserDefaults standardUserDefaults] objectForKey:XTide_units];
    if (!unitType) {
        unitType = @"ft";
    }
	if (![unitType isEqualToString:@"x"]) {
		libxtide::Units::PredictionUnits units = libxtide::Units::parse([unitType UTF8String]);
		[self setUnits:units];
	}
}

- (libxtide::Station *)adaptedStation
{
   return mStation;
}

- (NSDateFormatter *)timeFormatter
{
	if (!timeFormatter) {
		timeFormatter = [[NSDateFormatter alloc] init];
		[timeFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
		[timeFormatter setDateStyle:NSDateFormatterNoStyle];
		[timeFormatter setTimeStyle:NSDateFormatterMediumStyle];
		[timeFormatter setTimeZone:[self timeZone]];
	}
	return timeFormatter;
}

- (NSDateFormatter *)dayFormatter
{
	if (!dayFormatter) {
		dayFormatter = [[NSDateFormatter alloc] init];
		[dayFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
		[dayFormatter setDateStyle:NSDateFormatterMediumStyle];
		[dayFormatter setTimeStyle:NSDateFormatterNoStyle];
	}
	return dayFormatter;
}

- (NSString *)timeStringFromDate:(NSDate *)date
{
   return [[self timeFormatter] stringFromDate:date];
}

- (NSString *)dayStringFromDate:(NSDate *)date
{
   return [[self dayFormatter] stringFromDate:date];
}


// Generate an organizer with min/max events extending beyond the start/end dates.
- (XTTideEventsOrganizer *)populateOrganizerForWatchEventsStart:(NSDate *)startTime
                                                            end:(NSDate *)endTime
{
    static NSTimeInterval DAY = 60 * 60 * 24;
    libxtide::Station::TideEventsFilter filter = libxtide::Station::maxMin;

    XTTideEventsOrganizer *organizer = [[XTTideEventsOrganizer alloc] init];
    // Generate min/max events, with at least one before and after the range for interpolation.
    [self predictTideEventsStart:[startTime dateByAddingTimeInterval:-DAY]
                             end:[endTime dateByAddingTimeInterval:DAY]
                       organizer:organizer
                          filter:filter];
    NSInteger paranoiaCount = 0;
    while ([[(XTTideEvent *)[[organizer standardEvents] firstObject] date] compare:startTime] != NSOrderedAscending) {
        [self extendRange:organizer
                direction:libxtide::Station::backward
                 interval:libxtide::Global::day
                   filter:filter];
        paranoiaCount++;
        if (paranoiaCount > 5) {
            break;
        }
    }
    paranoiaCount = 0;
    while ([[(XTTideEvent *)[[organizer standardEvents] lastObject] date] compare:startTime] != NSOrderedDescending) {
        [self extendRange:organizer
                direction:libxtide::Station::forward
                 interval:libxtide::Global::day
                   filter:filter];
        paranoiaCount++;
        if (paranoiaCount > 5) {
            break;
        }
    }
    return organizer;
}

/*
 * Return the tide events as dictionary objects for a watch:
 * min/max, plus level and angle at every hour.
 * Angle is in radians for UIKit. AppKit may need degrees.
 */
- (NSArray *)generateWatchEventsStart:(NSDate *)startTime
                                  end:(NSDate *)endTime
{
    XTTideEventsOrganizer *organizer = [self populateOrganizerForWatchEventsStart:startTime end:endTime];
    libxtide::Timestamp currentTime = libxtide::Timestamp((time_t)[startTime timeIntervalSince1970]);
    libxtide::Timestamp endTimestamp = libxtide::Timestamp((time_t)[endTime timeIntervalSince1970]);
    NSArray *events = [organizer standardEvents];

    NSMutableArray *array = [NSMutableArray array];
    NSEnumerator *enumerator = [events objectEnumerator];
    XTTideEvent *prev = [enumerator nextObject];
    XTTideEvent *next = [enumerator nextObject];
    if (!next) {
        return nil;
    }
    // Find first pair.
    while (next && [next adaptedTideEvent]->eventTime <= currentTime) {
        prev = next;
        next = [enumerator nextObject];
    }
    if (!next) {
        return nil;
    }
    // Go through all min/max events, compute intermediate rising/falling events with angle and level.
    while (next) {
        libxtide::TideEvent *previousMaxOrMin = [prev adaptedTideEvent];
        libxtide::TideEvent *nextMaxOrMin = [next adaptedTideEvent];
        if (previousMaxOrMin->eventTime > endTimestamp) {
            break;
        }
        BOOL isRising = previousMaxOrMin->eventType == libxtide::TideEvent::min;
        // TODO: Is this right for current? Also localize this and TideEvent description.
        NSString *desc = nil;
        if (mStation->isCurrent) {
            desc = isRising ? @"Flood" : @"Ebb";
        } else {
            desc = isRising ? @"Rising" : @"Falling";
        }
        [array addObject:[prev eventDictionary]];
        while (currentTime <= nextMaxOrMin->eventTime) {
            double temp ((currentTime - previousMaxOrMin->eventTime) /
                         (nextMaxOrMin->eventTime - previousMaxOrMin->eventTime));
            temp *= M_PI;
            if (previousMaxOrMin->eventType == libxtide::TideEvent::min)
                temp += M_PI;
            Dstr levelPrint;
            mStation->predictTideLevel(currentTime).print(levelPrint);
            NSString *level = DstrToNSString(levelPrint);
            mStation->predictTideLevel(currentTime).printnp(levelPrint);
            NSString *levelShort = DstrToNSString(levelPrint);
           
            NSDictionary *event = @{@"date"  : TimestampToNSDate(currentTime),
                                    @"angle" : @(temp),
                                    @"level" : level,
                                    @"levelShort" : levelShort,
                                    @"desc"     : desc,
                                    @"isRising" : @(isRising)};
            [array addObject:event];
            currentTime += libxtide::Global::hour;
        }
        prev = next;
        next = [enumerator nextObject];
    }
    return array;
}


- (void)predictTideEventsStart:(NSDate *)startTime
                           end:(NSDate *)endTime
                     organizer:(XTTideEventsOrganizer *)organizer
                        filter:(int)filter
{
   libxtide::Timestamp start = libxtide::Timestamp((time_t)[startTime timeIntervalSince1970]);
   libxtide::Timestamp end = libxtide::Timestamp((time_t)[endTime timeIntervalSince1970]);

   mStation->predictTideEvents(start,
                               end,
                               [organizer adaptedOrganizer],
                               (libxtide::Station::TideEventsFilter)filter);
    [organizer reloadData];
}

- (void)predictTideEventsStart:(NSDate*)startTime
                           end:(NSDate*)endTime
                     organizer:(XTTideEventsOrganizer*)organizer
{
   libxtide::Timestamp start = libxtide::Timestamp((time_t)[startTime timeIntervalSince1970]);
   libxtide::Timestamp end = libxtide::Timestamp((time_t)[endTime timeIntervalSince1970]);
   mStation->predictTideEvents(start,
                               end,
                               [organizer adaptedOrganizer]);
    [organizer reloadData];
}

- (libxtide::PredictionValue)predictTideLevel:(NSDate *)predictTime
{
   libxtide::Timestamp predict = libxtide::Timestamp((time_t)[predictTime timeIntervalSince1970]);
   return mStation->predictTideLevel(predict);
}

- (void)extendRange:(XTTideEventsOrganizer *)organizer
          direction:(libxtide::Station::Direction)direction
		   interval:(libxtide::Interval)howMuch
             filter:(libxtide::Station::TideEventsFilter)filter
{
    mStation->extendRange([organizer adaptedOrganizer], direction, howMuch, filter);
    [organizer reloadData];
}

- (void)markLevel: (libxtide::PredictionValue)aPredictionValue
{
   mStation->markLevel = aPredictionValue;
}

- (void)clearMarkLevel
{
   mStation->markLevel.makeNull();
}

- (void)aspect: (double)anAspect
{
   mStation->aspect = anAspect;
}

- (NSTimeZone *)timeZone
{
   char *tzName = mStation->timezone.aschar();
	//  Apparently these are the strings NSTimeZone groks, except they start with a ':'
   return [NSTimeZone timeZoneWithName:
				[NSString stringWithCString:&tzName[1] 
                                   encoding:NSISOLatin1StringEncoding]];
}

- (libxtide::PredictionValue)minLevel {return mStation->minLevelHeuristic();}
- (libxtide::PredictionValue)maxLevel {return mStation->maxLevelHeuristic();}

- (BOOL)hasMarkLevel
{
   return !mStation->markLevel.isNull();
}
- (double)aspect {return mStation->aspect;}
- (libxtide::PredictionValue)markLevel {return mStation->markLevel;}
- (BOOL)isCurrent {return mStation->isCurrent;}
- (libxtide::Units::PredictionUnits)predictUnits {return mStation->predictUnits();}

- (void)setUnits: (libxtide::Units::PredictionUnits)units
{
   mStation->setUnits(units);
}

- (NSString *)stationInfoAsHTML
{
	Dstr text_out;
	mStation->aboutMode(text_out, libxtide::Format::HTML, libxtide::Global::codeset);
	return DstrToNSString(text_out);
}


- (NSString *)stationCalendarInfoFromDate: (NSDate *)startTime
											  toDate: (NSDate *)endTime
{
	return [[self loadCalendarFromStart:startTime toEnd:endTime] generateHTML];
}

- (NSDictionary *)stationCalendarDataFromDate: (NSDate *)startTime
											      toDate: (NSDate *)endTime
{
	return [[self loadCalendarFromStart:startTime toEnd:endTime] generateDataSource];
}

- (XTCalendar *)loadCalendarFromStart: (NSDate *)startTime
										  toEnd: (NSDate *)endTime
{
    return [[XTCalendar alloc] initWithStation:self
                                     startTime:startTime
                                       endTime:endTime];
}

- (NSArray *)stationMetadata
{
	NSMutableArray *array = [NSMutableArray array];
	const libxtide::MetaFieldVector metadata = mStation->metadata();
	libxtide::MetaFieldVector::const_iterator it = metadata.begin();
    while (it != metadata.end()) {
        Dstr name (it->name), value (it->value);
        [array addObject:@{@"name" : DstrToNSString(name), @"value" : DstrToNSString(value)}];
		++it;
	}
	return array;
}

- (NSDictionary *)stationInfoDictionarys
{
	NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
	const libxtide::MetaFieldVector metadata = mStation->metadata();
	libxtide::MetaFieldVector::const_iterator it = metadata.begin();
    while (it != metadata.end()) {
      Dstr name (it->name), value (it->value);
		[infoDict setObject:DstrToNSString(value) forKey:DstrToNSString(name)];
		++it;
	}
	return infoDict;
}

@end
