/*
 * Created by Mayur Pawashe on 3/7/13.
 *
 * Copyright (c) 2013 zgcoder
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ZGSearchProgress.h"

#define ZGSearchProgressProgressTypeKey @"ZGSearchProgressProgressTypeKey"
#define ZGSearchProgressMaxProgressKey @"ZGSearchProgressMaxProgressKey"
#define ZGSearchProgressNumberOfVariablesFoundKey @"ZGSearchProgressNumberOfVariablesFoundKey"
#define ZGSearchProgressProgressKey @"ZGSearchProgressProgressKey"

@implementation ZGSearchProgress

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt32:_progressType forKey:ZGSearchProgressProgressTypeKey];
	[coder encodeInt64:(int64_t)_maxProgress forKey:ZGSearchProgressMaxProgressKey];
	[coder encodeInteger:(NSInteger)_numberOfVariablesFound forKey:ZGSearchProgressNumberOfVariablesFoundKey];
	[coder encodeInt64:(int64_t)_progress forKey:ZGSearchProgressProgressKey];
}

- (id)initWithCoder:(NSCoder *)decoder
{
	self = [super init];
	if (self == nil) return nil;
	
	_progressType = (uint16_t)[decoder decodeInt32ForKey:ZGSearchProgressProgressTypeKey];
	_maxProgress = (uint64_t)[decoder decodeInt64ForKey:ZGSearchProgressMaxProgressKey];
	_numberOfVariablesFound = (uint64_t)[decoder decodeInt64ForKey:ZGSearchProgressNumberOfVariablesFoundKey];
	_progress = (uint64_t)[decoder decodeInt64ForKey:ZGSearchProgressProgressKey];
	
	return self;
}

- (id)copyWithZone:(NSZone *)__unused zone
{
	NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self];
	return [NSKeyedUnarchiver unarchiveObjectWithData:archivedData];
}

- (id)initWithProgressType:(ZGSearchProgressType)progressType maxProgress:(ZGMemorySize)maxProgress
{
	self = [super init];
	if (self != nil)
	{
		_progressType = progressType;
		_maxProgress = maxProgress;
	}
	return self;
}

@end
