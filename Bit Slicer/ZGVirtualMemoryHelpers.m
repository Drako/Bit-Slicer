/*
 * Created by Mayur Pawashe on 8/9/13.
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

#import "ZGVirtualMemoryHelpers.h"
#import "ZGVirtualMemory.h"
#import "ZGRegion.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "NSArrayAdditions.h"

#import <mach/mach_error.h>
#import <mach/mach_vm.h>

static NSDictionary *gTasksDictionary = nil;

BOOL ZGTaskExistsForProcess(pid_t process, ZGMemoryMap *task)
{
	*task = MACH_PORT_NULL;
	if (gTasksDictionary)
	{
		*task = [[gTasksDictionary objectForKey:@(process)] unsignedIntValue];
	}
	return *task != MACH_PORT_NULL;
}

BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task)
{
	if (!gTasksDictionary)
	{
		gTasksDictionary = [[NSDictionary alloc] init];
	}
	
	BOOL success = YES;
	
	if (!ZGTaskExistsForProcess(process, task))
	{
		if (!ZGTaskForPID(process, task))
		{
			if (*task != MACH_PORT_NULL)
			{
				ZGDeallocatePort(*task);
			}
			*task = MACH_PORT_NULL;
			success = NO;
		}
		else if (!MACH_PORT_VALID(*task))
		{
			if (*task != MACH_PORT_NULL)
			{
				ZGDeallocatePort(*task);
			}
			*task = MACH_PORT_NULL;
			NSLog(@"Mach port is not valid for process %d", process);
			success = NO;
		}
		else
		{
			NSMutableDictionary *newTasksDictionary = [[NSMutableDictionary alloc] initWithDictionary:gTasksDictionary];
			[newTasksDictionary setObject:@(*task) forKey:@(process)];
			gTasksDictionary = [NSDictionary dictionaryWithDictionary:newTasksDictionary];
		}
	}
	
	return success;
}

void ZGFreeTask(ZGMemoryMap task)
{
	for (id process in gTasksDictionary.allKeys)
	{
		if ([@(task) isEqualToNumber:[gTasksDictionary objectForKey:process]])
		{
			NSMutableDictionary *newTasksDictionary = [[NSMutableDictionary alloc] initWithDictionary:gTasksDictionary];
			[newTasksDictionary removeObjectForKey:process];
			gTasksDictionary = [NSDictionary dictionaryWithDictionary:newTasksDictionary];
			
			ZGDeallocatePort(task);
			
			break;
		}
	}
}

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask)
{
	NSMutableArray *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (1)
	{
		infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		if (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS)
		{
			break;
		}
		
		ZGRegion *region = [[ZGRegion alloc] initWithAddress:address size:size];
		region.protection = info.protection;
		
		[regions addObject:region];
		
		address += size;
	}
	
	return [NSArray arrayWithArray:regions];
}

NSArray *ZGRegionsForProcessTaskRecursively(ZGMemoryMap processTask)
{
	NSMutableArray *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_submap_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	natural_t depth = 0;
	
	while (1)
	{
		infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
		if (mach_vm_region_recurse(processTask, &address, &size, &depth, (vm_region_recurse_info_t)&info, &infoCount) != KERN_SUCCESS)
		{
			break;
		}
		
		if (info.is_submap)
		{
			depth++;
		}
		else
		{
			ZGRegion *region = [[ZGRegion alloc] initWithAddress:address size:size];
			region.protection = info.protection;
			
			address += size;
		}
	}
	
	return [NSArray arrayWithArray:regions];
}

NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask)
{
	return [ZGRegionsForProcessTask(processTask) count];
}

#define ZGUserTagPretty(x) [[[(x) stringByReplacingOccurrencesOfString:@"VM_MEMORY_" withString:@""] stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString]

#define ZGHandleUserTagCase(result, value) \
case value: \
	result = ZGUserTagPretty(@(#value)); \
	break;

#define ZGHandleUserTagCaseWithDescription(result, value, description) \
	case value: \
		result = description; \
		break;

NSString *ZGUserTagDescription(unsigned int userTag)
{
	NSString *userTagDescription = nil;
	
	switch (userTag)
	{
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_SMALL)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_LARGE)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_HUGE)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_SBRK)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_REALLOC)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_TINY)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_LARGE_REUSABLE)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_LARGE_REUSED)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_ANALYSIS_TOOL)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_MALLOC_NANO)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_MACH_MSG, @"Mach Message")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_IOKIT, @"IOKit")
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_STACK)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_GUARD)
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_SHARED_PMAP)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_DYLIB, @"dylib")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_OBJC_DISPATCHERS, @"Obj-C Dispatchers")
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_UNSHARED_PMAP)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_APPKIT, @"AppKit")
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_FOUNDATION)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREGRAPHICS, @"Core Graphics")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_CORESERVICES, @"Core Services")
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_JAVA)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREDATA, @"Core Data")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREDATA_OBJECTIDS, @"Core Data Object IDs")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_ATS, @"Apple Type Services")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_LAYERKIT, @"LayerKit")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_CGIMAGE, @"CGImage")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_TCMALLOC, @"TCMalloc")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREGRAPHICS_DATA, @"Core Graphics Data")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREGRAPHICS_SHARED, @"Core Graphics Shared")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREGRAPHICS_FRAMEBUFFERS, @"Core Graphics Framebuffers")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREGRAPHICS_BACKINGSTORES, @"Core Graphics Backing Stores")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_DYLD, @"dyld")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_DYLD_MALLOC, @"dyld Malloc")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_SQLITE, @"SQLite")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_JAVASCRIPT_CORE, @"JavaScript Core")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_JAVASCRIPT_JIT_EXECUTABLE_ALLOCATOR, @"JavaScript JIT Executable Allocator")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_JAVASCRIPT_JIT_REGISTER_FILE, @"JavaScript JIT Register File")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_GLSL, @"GLSL")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_OPENCL, @"OpenCL")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREIMAGE, @"Core Image")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_WEBCORE_PURGEABLE_BUFFERS, @"WebCore Purgeable Buffers")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_IMAGEIO, @"ImageIO")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREPROFILE, @"Core Profile")
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_ASSETSD)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_OS_ALLOC_ONCE, @"OS Alloc Once")
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_LIBDISPATCH, @"libdispatch")
			ZGHandleUserTagCase(userTagDescription, VM_MEMORY_ACCELERATE)
			ZGHandleUserTagCaseWithDescription(userTagDescription, VM_MEMORY_COREUI, @"CoreUI")
	}
	
	return userTagDescription;
}

NSString *ZGUserTagDescriptionFromAddress(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size)
{
	NSString *userTagDescription = nil;
	ZGMemoryAddress regionAddress = address;
	ZGMemorySize regionSize = size;
	ZGMemorySubmapInfo submapInfo;
	if (ZGRegionSubmapInfo(processTask, &regionAddress, &regionSize, &submapInfo) && regionAddress <= address && address + size <= regionAddress + regionSize)
	{
		userTagDescription = ZGUserTagDescription(submapInfo.user_tag);
	}
	return userTagDescription;
}

CSSymbolRef ZGFindSymbol(CSSymbolicatorRef symbolicator, NSString *symbolName, NSString *partialSymbolOwnerName, BOOL requiresExactMatch)
{
	__block CSSymbolRef resultSymbol = kCSNull;
	__block CSSymbolRef partialResultSymbol = kCSNull;
	const char *symbolCString = [symbolName UTF8String];
	
	CSSymbolicatorForeachSymbolOwnerAtTime(symbolicator, kCSNow, ^(CSSymbolOwnerRef owner) {
		const char *symbolOwnerName = CSSymbolOwnerGetName(owner); // this really returns a suffix
		if (partialSymbolOwnerName == nil || (symbolOwnerName != NULL && [partialSymbolOwnerName hasSuffix:@(symbolOwnerName)]))
		{
			CSSymbolOwnerForeachSymbol(owner, ^(CSSymbolRef symbol) {
				if (CSIsNull(resultSymbol))
				{
					const char *symbolFound = CSSymbolGetName(symbol);
					if (symbolFound != NULL)
					{
						if (strcmp(symbolCString, symbolFound) == 0)
						{
							resultSymbol = symbol;
						}
						else if (!requiresExactMatch && CSIsNull(partialResultSymbol) && [@(symbolFound) rangeOfString:symbolName].location != NSNotFound)
						{
							partialResultSymbol = symbol;
						}
					}
				}
			});
		}
	});
	
	if (!requiresExactMatch && CSIsNull(resultSymbol))
	{
		resultSymbol = partialResultSymbol;
	}
	
	return resultSymbol;
}

NSArray *ZGGetAllData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress)
{
	NSMutableArray *dataArray = [[NSMutableArray alloc] init];
	ZGProtectionMode protectionMode = searchData.protectionMode;
	
	NSArray *regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
		return region.protection & VM_PROT_READ &&
			(protectionMode == ZGProtectionAll || (protectionMode == ZGProtectionWrite && region.protection & VM_PROT_WRITE) || (protectionMode == ZGProtectionExecute && region.protection & VM_PROT_EXECUTE));
	}];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		searchProgress.initiatedSearch = YES;
		searchProgress.progressType = ZGSearchProgressMemoryStoring;
		searchProgress.maxProgress = regions.count;
	});
	
	for (ZGRegion *region in regions)
	{
		void *bytes = NULL;
		ZGMemorySize size = region.size;
		
		if (ZGReadBytes(processTask, region.address, &bytes, &size))
		{
			region.bytes = bytes;
			region.size = size;
			
			[dataArray addObject:region];
		}
		
		if (searchProgress.shouldCancelSearch)
		{
			ZGFreeData(dataArray);
			dataArray = nil;
			break;
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			searchProgress.progress++;
		});
	}
	
	return dataArray;
}

void ZGFreeData(NSArray *dataArray)
{
	for (ZGRegion *memoryRegion in dataArray)
	{
		ZGFreeBytes(memoryRegion.processTask, memoryRegion.bytes, memoryRegion.size);
	}
}

// helper function for ZGSaveAllDataToDirectory
static void ZGSavePieceOfData(NSMutableData *currentData, ZGMemoryAddress currentStartingAddress, NSString *directory, int *fileNumber, FILE *mergedFile)
{
	if (currentData)
	{
		ZGMemoryAddress endAddress = currentStartingAddress + [currentData length];
		(*fileNumber)++;
		[currentData
		 writeToFile:[directory stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"(%d) 0x%llX - 0x%llX", *fileNumber, currentStartingAddress, endAddress]]
		 atomically:NO];
		
		if (mergedFile)
		{
			fwrite(currentData.bytes, currentData.length, 1, mergedFile);
		}
	}
}

BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGMemoryMap processTask, ZGSearchProgress *searchProgress)
{
	BOOL success = NO;
	
	NSMutableData *currentData = nil;
	ZGMemoryAddress currentStartingAddress = 0;
	ZGMemoryAddress lastAddress = currentStartingAddress;
	int fileNumber = 0;
	
	FILE *mergedFile = fopen([directory stringByAppendingPathComponent:@"(All) Merged"].UTF8String, "w");
	
	NSArray *regions = ZGRegionsForProcessTask(processTask);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		searchProgress.initiatedSearch = YES;
		searchProgress.progressType = ZGSearchProgressMemoryDumping;
		searchProgress.maxProgress = regions.count;
	});
	
	for (ZGRegion *region in regions)
	{
		if (lastAddress != region.address || !(region.protection & VM_PROT_READ))
		{
			// We're done with this piece of data
			ZGSavePieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
			currentData = nil;
		}
		
		if (region.protection & VM_PROT_READ)
		{
			if (!currentData)
			{
				currentData = [[NSMutableData alloc] init];
				currentStartingAddress = region.address;
			}
			
			// outputSize should not differ from size
			ZGMemorySize outputSize = region.size;
			void *bytes = NULL;
			if (ZGReadBytes(processTask, region.address, &bytes, &outputSize))
			{
				[currentData appendBytes:bytes length:(NSUInteger)outputSize];
				ZGFreeBytes(processTask, bytes, outputSize);
			}
		}
		
		lastAddress = region.address;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			searchProgress.progress++;
		});
  	    
		if (searchProgress.shouldCancelSearch)
		{
			goto EXIT_ON_CANCEL;
		}
	}
	
	ZGSavePieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
    
EXIT_ON_CANCEL:
	
	if (mergedFile)
	{
		fclose(mergedFile);
	}
	
	success = YES;
	
	return success;
}

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize, ZGMemorySize maxStringSizeLimit)
{
	ZGMemorySize totalSize = 0;
	
	ZGMemorySize characterSize = (dataType == ZGString8) ? sizeof(char) : sizeof(unichar);
	void *buffer = NULL;
	
	if (dataType == ZGString16 && oldSize % 2 != 0)
	{
		oldSize--;
	}
	
	BOOL shouldUseOldSize = (oldSize >= characterSize);
	
	while (YES)
	{
		BOOL shouldBreak = NO;
		ZGMemorySize outputtedSize = shouldUseOldSize ? oldSize : characterSize;
		
		BOOL couldReadBytes = ZGReadBytes(processTask, address, &buffer, &outputtedSize);
		if (!couldReadBytes && shouldUseOldSize)
		{
			shouldUseOldSize = NO;
			continue;
		}
		
		if (couldReadBytes)
		{
			ZGMemorySize numberOfCharacters = outputtedSize / characterSize;
			if (dataType == ZGString16 && outputtedSize % 2 != 0 && numberOfCharacters > 0)
			{
				numberOfCharacters--;
				shouldBreak = YES;
			}
			
			for (ZGMemorySize characterCounter = 0; characterCounter < numberOfCharacters; characterCounter++)
			{
				if ((dataType == ZGString8 && ((char *)buffer)[characterCounter] == 0) || (dataType == ZGString16 && ((unichar *)buffer)[characterCounter] == 0))
				{
					shouldBreak = YES;
					break;
				}
				
				totalSize += characterSize;
			}
			
			ZGFreeBytes(processTask, buffer, outputtedSize);
			
			if (maxStringSizeLimit > 0 && totalSize >= maxStringSizeLimit)
			{
				totalSize = maxStringSizeLimit;
				shouldBreak = YES;
			}
			
			if (dataType == ZGString16)
			{
				outputtedSize = numberOfCharacters * characterSize;
			}
		}
		else
		{
			shouldBreak = YES;
		}
		
		if (shouldBreak)
		{
			break;
		}
		
		address += outputtedSize;
	}
	
	return totalSize;
}
