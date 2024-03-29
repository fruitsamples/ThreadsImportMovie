/*
	File:		URLUtilities.c
	
	Description: Some utilities for working with URLs.
                 All utilities start with the prefix "URLUtils_".

	Author:		QuickTime Engineering

	Copyright: 	� Copyright 2003-2004 Apple Computer, Inc. All rights reserved.
	
	Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
				("Apple") in consideration of your agreement to the following terms, and your
				use, installation, modification or redistribution of this Apple software
				constitutes acceptance of these terms.  If you do not agree with these terms,
				please do not use, install, modify or redistribute this Apple software.

				In consideration of your agreement to abide by the following terms, and subject
				to these terms, Apple grants you a personal, non-exclusive license, under Apple�s
				copyrights in this original Apple software (the "Apple Software"), to use,
				reproduce, modify and redistribute the Apple Software, with or without
				modifications, in source and/or binary forms; provided that if you redistribute
				the Apple Software in its entirety and without modifications, you must retain
				this notice and the following text and disclaimers in all such redistributions of
				the Apple Software.  Neither the name, trademarks, service marks or logos of
				Apple Computer, Inc. may be used to endorse or promote products derived from the
				Apple Software without specific prior written permission from Apple.  Except as
				expressly stated in this notice, no other rights or licenses, express or implied,
				are granted by Apple herein, including but not limited to any patent rights that
				may be infringed by your derivative works or by other works in which the Apple
				Software may be incorporated.

				The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
				WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
				WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
				PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
				COMBINATION WITH YOUR PRODUCTS.

				IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
				CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
				GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
				ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
				OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
				(INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
				ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
				
    Change History (most recent first): <1> 12/04/98 initial release
*/

#pragma once

//////////
//
// header files
//
//////////

#ifndef __URLUtilities__
#define __URLUtilities__

#import <Carbon/Carbon.h>
#import <QuickTime/QuickTime.h>


//////////
//
// compiler flags
//
//////////

#define USE_EMPTY_LOCALHOST			1				// use "" instead of "localhost" for the local hostname in file URLs


//////////
//
// constants
//
//////////

#define kURLSchemeSeparator			(char)':'		// URL scheme separator
#define kURLPathSeparator			(char)'/'		// URL path separator
#define kURLQuerySeparator			(char)'?'		// URL query separator
#define kURLEscapeCharacter			(char)'%'		// the escape character
#define kURLAuthPrefix				"://"			// the prefix for the authority portion of a URL
#define kURLAuthSuffix				"?/"			// the characters that can terminate the authority portion of a URL
#define kURLPathSuffix				"?"				// the characters that can terminate the path portion of a URL

#define kHTTPScheme					"http"			// the scheme for http URLs
#define kFTPScheme					"ftp"			// the scheme for ftp URLs
#define kFileScheme					"file"			// the scheme for file URLs
#define kTelnetScheme				"telnet"		// the scheme for telnet URLs
#define kGopherScheme				"gopher"		// the scheme for gopher URLs

#define kLocalhostStr				"localhost"		// the authority portion for local files

#define kFilePrefix					"file://"		// the prefix for file URLs


#if USE_EMPTY_LOCALHOST
#define kLocalhostAuth				""				// the authority portion for local files
#else
#define kLocalhostAuth				kLocalhostStr	// the authority portion for local files
#endif

#if TARGET_OS_MAC
#define kFilePathSeparator			(char)':'		// on Macintosh, the file path separator is ':'
#elif TARGET_OS_WIN32
#define kFilePathSeparator			(char)'\\'		// on Windows, the file path separator is '\\'
#else
#define kFilePathSeparator			(char)'/'		// on other systems, assume the file path separator is '/'
#endif

#if TARGET_OS_MAC
#define kFilePathSepString			":"				// on Macintosh, the file path separator string is ":"
#elif TARGET_OS_WIN32
#define kFilePathSepString			"\\"			// on Windows, the file path separator string is "\\"
#else
#define kFilePathSepString			"/"				// on other systems, assume the file path separator string is "/"
#endif

#define kWinVolumeNameChar			(char)':'		// on Windows, the character that follows volume names in full pathnames
#define kURLVolumeNameChar			(char)'|'		// on Windows, the character that follows volume names in URLs

#ifndef MAX_PATH
#define MAX_PATH					512				// maximum size of a path name
#endif


//////////
//
// macros
//
//////////

#define URLUtils_IsDigit(x)			(((x >= '0') && (x <= '9')) ? 1 : 0)
#define URLUtils_IsUppercase(x)		(((x >= 'A') && (x <= 'Z')) ? 1 : 0)
#define URLUtils_IsLowercase(x)		(((x >= 'a') && (x <= 'z')) ? 1 : 0)
#define URLUtils_ToUppercase(x)		((URLUtils_IsLowercase(x)) ? x - 'a' + 'A' : x)
#define URLUtils_ToLowercase(x)		((URLUtils_IsUppercase(x)) ? x + 'a' - 'A' : x)
#define URLUtils_IsAlphabetic(x)	((URLUtils_IsUppercase(x) || URLUtils_IsLowercase(x)) ? 1 : 0)
#define URLUtils_IsAlphanumeric(x)	((URLUtils_IsAlphabetic(x) || URLUtils_IsDigit(x)) ? 1 : 0)


//////////
//
// function prototypes
//
//////////

char *							URLUtils_GetScheme (char *theURL);
char *							URLUtils_GetAuthority (char *theURL);
char *							URLUtils_GetPath (char *theURL);
char *							URLUtils_GetQuery (char *theURL);
char *					URLUtils_GetAuthBegin (char *theURL);
char *					URLUtils_GetPathBegin (char *theURL);
char *					URLUtils_GetQueryBegin (char *theURL);

char *							URLUtils_FullNativePathToURL (char *thePath);
char *							URLUtils_URLToFullNativePath (char *theURL);
FSSpecPtr						URLUtils_FullNativePathToFSSpec (char *thePath);
char *							URLUtils_FSSpecToFullNativePath (const FSSpecPtr theFSSpecPtr);
char *							URLUtils_FSSpecToURL (const FSSpecPtr theFSSpecPtr);
FSSpecPtr						URLUtils_URLToFSSpec (char *theURL);
OSErr					URLUtils_FSpecGetFullPath (const FSSpecPtr theFSSpecPtr, short *theFullPathLength, Handle *theFullPath);
OSErr					URLUtils_LocationFromFullPath (short theFullPathLength, const void *theFullPath, FSSpecPtr theFSSpecPtr);

Movie							URLUtils_NewMovieFromURL (char *theURL, short theFlags, short *theID);
OSErr							URLUtils_HaveBrowserOpenURL (char *theURL);

char *							URLUtils_GetURLBasename (char *theURL);

Boolean							URLUtils_IsAbsoluteURL (char *theURL);
Boolean							URLUtils_IsRelativeURL (char *theURL);

Boolean					URLUtils_IsReservedChar (char theChar);
Boolean					URLUtils_IsDelimiterChar (char theChar);
Boolean					URLUtils_IsUnsafeChar (char theChar);
Boolean					URLUtils_IsPunctMarkChar (char theChar);
Boolean					URLUtils_IsEncodableChar (char theChar);

char *							URLUtils_EncodeString (char *theString);
char *							URLUtils_DecodeString (char *theString);

StringPtr						URLUtils_ConvertCToPascalString (char *theString);


#endif	// __URLUtilities__
