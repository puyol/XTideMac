//
//  XTStation.h
//  XTide
//
//  Created by Lee Ann Rucker on 4/13/16.
//  Copyright © 2016 Lee Ann Rucker. All rights reserved.
//

#ifndef XTStation_h
#define XTStation_h

@class XTTideEventsOrganizer;
@class XTStationRef;

@interface XTStation : NSObject

+ (NSArray *)unitsPrefMap;

- (NSString *)name;
- (NSTimeZone *)timeZone;
- (NSString *)stationInfoAsHTML;
- (NSArray *)stationMetadata;
- (XTStationRef *)stationRef;

- (NSString *)timeStringFromDate: (NSDate *)date;
- (NSString *)dayStringFromDate:(NSDate *)date;
- (NSString *)dateStringFromDate:(NSDate *)date;

- (void)predictTideEventsStart:(NSDate*)startTime
                           end:(NSDate*)endTime
                     organizer:(XTTideEventsOrganizer*)organizer;


- (void)predictTideEventsStart:(NSDate*)startTime
                           end:(NSDate*)endTime
                     organizer:(XTTideEventsOrganizer*)organizer
                        filter:(int)filter;

// Return the tide events as an IPC compliant dictionary for a watch.
- (NSArray *)generateWatchEventsStart:(NSDate*)startTime
                                  end:(NSDate*)endTime;

@end

#endif /* XTStation_h */
