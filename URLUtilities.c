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
				
    Change History (most recent first):

	   <8>	 	08/08/02	qte		removed escape character '\' from '\`' to keep gcc happy
	   <7>	 	02/09/00	qte		removed "static" keyword from URLUtils_EncodeString and _Decode;
									added URLUtils_IsUnsafeChar; tweaked definitions of other character
									functions per RFC 1738
	   <6>	 	02/22/99	qte		added URLUtils_HaveBrowserOpenURL
	   <5>	 	12/26/98	qte		added URLUtils_LocationFromFullPath
	   <4>	 	12/23/98	qte		added URLUtils_FSSpecToFullNativePath, URLUtils_FSSpecToURL, and
									URLUtils_URLToFSSpec; fixed bug in URLUtils_DecodeString
	   <3>	 	12/07/98	qte		modified URLUtils_NewMovieFromURL to take flags and ID parameters;
									added URLUtils_URLToFullNativePath
	   <2>	 	12/06/98	qte		more work; finished URLUtils_FullNativePathToURL
	   <1>	 	12/04/98	qte		first file

	The structure of URLs assumed in these functions is based on that specified in
	the Network Working Group RFC 2396 (August 1998) by Tim Berners-Lee (who else?)
	et al. In addition, I have adopted the terminology used in that document.

	The basic structure of an absolute URL is this:

						<scheme>://<authority><path>?<query>
*/

// header files

#ifndef __URLUtilities__
#include "URLUtilities.h"

///////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Syntax utilities.
//
// Use these functions to retrieve the distinguishable parts of a URL.
//
///////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////
//
// URLUtils_GetScheme
// Return the scheme portion of the specified (absolute) URL. If that URL is not absolute, return NULL.
//
// The scheme of a URL is the leading portion of a URL. It specifies the protocol to be used to access
// the named resource. RFC 2396 specifies that a scheme begin with an alphabetic character and contain
// only alphanumerics and '+', '-', '.'; we don't check for this yet.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_GetScheme (char *theURL)
{
	char	*myScheme = NULL;
	short	myLength = 0;
	short	myIndex;
	
	// make sure we were passed an absolute URL
	if (!URLUtils_IsAbsoluteURL(theURL))
		return(myScheme);

	// find the length of the scheme
	while (theURL[myLength] != kURLSchemeSeparator)
		myLength++;
	
	myScheme = malloc(myLength + 1);
	if (myScheme != NULL) {
		for (myIndex = 0; myIndex < myLength; myIndex++)
			myScheme[myIndex] = URLUtils_ToLowercase(theURL[myIndex]);
			
		myScheme[myLength] = '\0';
	}
	
	return(myScheme);
}


//////////
//
// URLUtils_GetAuthority
// Return the naming authority portion of the specified (absolute) URL. If that URL is not absolute,
// return NULL.
//
// The authority is preceded by a double slash and is terminated by the following slash, question mark,
// or null character. In some cases, the authority portion of a URL is empty; in those cases, we return
// a non-NULL pointer to an empty string.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_GetAuthority (char *theURL)
{
	char	*myAuthority = NULL;
	char	*myString = NULL;
	short	myLength = 0;
	
	// make sure we were passed an absolute URL
	if (!URLUtils_IsAbsoluteURL(theURL))
		return(myAuthority);

	// find the place in theURL where the authority prefix begins
	myString = URLUtils_GetAuthBegin(theURL);
	if (myString != NULL) {
		// get the length of the authority portion
		myLength = strcspn(myString + strlen(kURLAuthPrefix), kURLAuthSuffix);
		
		myAuthority = malloc(myLength + 1);
		if (myAuthority != NULL) {
			strncpy(myAuthority, myString + strlen(kURLAuthPrefix), myLength);
			myAuthority[myLength] = '\0';
		}
	}

	return(myAuthority);
}


//////////
//
// URLUtils_GetPath
// Return the path portion of the specified (absolute) URL. If that URL is not absolute, return NULL.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_GetPath (char *theURL)
{
	char	*myPath = NULL;
	char	*myString = NULL;
	short	myLength = 0;
	
	// make sure we were passed an absolute URL
	if (!URLUtils_IsAbsoluteURL(theURL))
		return(myPath);

	// find the place in theURL where the path prefix begins
	myString = URLUtils_GetPathBegin(theURL);
	if (myString != NULL) {
		// get the length of the path portion
		myLength = strcspn(myString, kURLPathSuffix);
		
		myPath = malloc(myLength + 1);
		if (myPath != NULL) {
			strncpy(myPath, myString, myLength);
			myPath[myLength] = '\0';
		}
	}

	return(myPath);
}


//////////
//
// URLUtils_GetQuery
// Return the query portion of the specified (absolute) URL. If that URL is not absolute, return NULL.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_GetQuery (char *theURL)
{
	char	*myQuery = NULL;
	char	*myString = NULL;
	
	// make sure we were passed an absolute URL
	if (!URLUtils_IsAbsoluteURL(theURL))
		return(myQuery);

	// find the place in theURL where the query begins
	myString = URLUtils_GetQueryBegin(theURL);
	if (myString != NULL) {
		myQuery = malloc(strlen(myString) + 1);
		if (myQuery != NULL) {
			strcpy(myQuery, myString);
			myQuery[strlen(myString)] = '\0';
		}
	}

	return(myQuery);
}


//////////
//
// URLUtils_GetAuthBegin
// Return a pointer to the beginning of the authority portion of the specified URL.
//
//////////

char *URLUtils_GetAuthBegin (char *theURL)
{
	return(strstr(theURL, kURLAuthPrefix));
}


//////////
//
// URLUtils_GetPathBegin
// Return a pointer to the beginning of the path portion of the specified URL.
//
//////////

char *URLUtils_GetPathBegin (char *theURL)
{
	char	*myString = NULL;
	short	myLength = 0;
	
	myString = URLUtils_GetAuthBegin(theURL);
	if (myString != NULL) {
		// get the length of the authority portion
		myLength = strcspn(myString + strlen(kURLAuthPrefix), kURLAuthSuffix);
		
		// determine the beginning of the path portion
		myString += (myLength + strlen(kURLAuthPrefix));
	}
	
	return(myString);
}


//////////
//
// URLUtils_GetQueryBegin
// Return a pointer to the beginning of the query portion of the specified URL.
//
//////////

char *URLUtils_GetQueryBegin (char *theURL)
{
	char	*myString = NULL;
	
	myString = strchr(theURL, kURLQuerySeparator);
	if (myString != NULL)
		myString++;			// to skip over the query separator
	
	return(myString);
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// FSSpec/URL/Pathname conversion utilities.
//
// Use these functions to convert among FSSpecs, URLs, and pathnames.
//
///////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////
//
// URLUtils_FullNativePathToURL 
// Convert a full native pathname into a local file URL.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_FullNativePathToURL (char *thePath)
{
	char		*myURL = NULL;	
	char		*myScratchStr = NULL;	
	char		*myEncodedStr = NULL;	
	short		myIndex;
	
	if (thePath == NULL)
		goto bail;

	//////////
	//
	// transform thePath as required by the target operating system
	//
	// on MacOS, a full pathname is of the form <vol>:<dir>:...:<dir>:<name>
	// to convert this into a form appropriate to URLs, we need only convert
	// the colon (:) into the URL separator (/)
	//
	// on Windows, a full pathname has the form <vol>:\<dir>\<dir>\...\<name>
	// to convert this into a form appropriate to URLs, we need to convert
	// the colon (:) into '|' and the backslash (\) into the URL separator (/)
	//
	//////////
	
	myScratchStr = malloc(strlen(thePath) + 1);
	if (myScratchStr == NULL)
		goto bail;
	
	for (myIndex = 0; myIndex <= strlen(thePath); myIndex++)
		if (thePath[myIndex] == kFilePathSeparator)
			myScratchStr[myIndex] = kURLPathSeparator;
#if TARGET_OS_WIN32
		else if (thePath[myIndex] == kWinVolumeNameChar)
			myScratchStr[myIndex] = kURLVolumeNameChar;
#endif
		else
			myScratchStr[myIndex] = thePath[myIndex];

	//////////
	//
	// encode the transformed string
	//
	//////////
	
	myEncodedStr = URLUtils_EncodeString(myScratchStr);
	if (myEncodedStr == NULL)
		goto bail;

	myURL = malloc(strlen(myEncodedStr) + strlen(kFilePrefix) + strlen(kLocalhostAuth) + strlen("/") + 1);
	if (myURL == NULL)
		goto bail;
		
	//////////
	//
	// prepend the appropriate URL head
	//
	//////////
	
	myURL[0] = '\0';
	strcat(myURL, kFilePrefix);
	strcat(myURL, kLocalhostAuth);
	strcat(myURL, "/");

	//////////
	//
	// append the converted and encoded path name to the URL head
	//
	//////////
	
	strcat(myURL, myEncodedStr);
	
bail:
	free(myScratchStr);
	free(myEncodedStr);
		
	return(myURL);
}


//////////
//
// URLUtils_URLToFullNativePath 
// Convert a local file URL into a full native pathname.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_URLToFullNativePath (char *theURL)
{
	char		*myScratchStr = NULL;	
	char		*myDecodedStr = NULL;	
	short		myIndex;

	if (theURL == NULL)
		goto bail;

	// make sure we were passed a file URL; the URL must begin with the file prefix
	myScratchStr = strstr(theURL, kFilePrefix);
	if ((myScratchStr == NULL) || (myScratchStr != theURL))
		goto bail;
	
	// strip off the URL head
	myScratchStr += strlen(kFilePrefix);
	
	// strip off the authority portion, if it's non-empty
	if (strstr(theURL, kLocalhostStr) == myScratchStr)
		myScratchStr += strlen(kLocalhostStr);
		
	// strip off the authority portion, if it's just '/'
	if (myScratchStr[0] == kURLPathSeparator)
		myScratchStr++;
	
	// decode the path string
	myDecodedStr = URLUtils_DecodeString(myScratchStr);
	if (myDecodedStr == NULL)
		goto bail;

	// transform the decoded path as required by the target operating system
	for (myIndex = 0; myIndex <= strlen(myDecodedStr); myIndex++)
		if (myDecodedStr[myIndex] == kURLPathSeparator)
			myDecodedStr[myIndex] = kFilePathSeparator;
#if TARGET_OS_WIN32
		else if (myDecodedStr[myIndex] == kURLVolumeNameChar)
			myDecodedStr[myIndex] = kWinVolumeNameChar;
#endif

bail:
	return(myDecodedStr);
}


//////////
//
// URLUtils_FullNativePathToFSSpec
// Convert a full native pathname into an FSSpec.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

FSSpecPtr URLUtils_FullNativePathToFSSpec (char *thePath)
{
	FSSpecPtr		myFSSpecPtr = malloc(sizeof(FSSpec));
	StringPtr 		myStringPtr = NULL;
	
	if (myFSSpecPtr == NULL)
		return(myFSSpecPtr);
		
	myStringPtr = URLUtils_ConvertCToPascalString(thePath);

	if (strlen(thePath) < 255)
		FSMakeFSSpec(0, 0L, myStringPtr, myFSSpecPtr);
	else
		URLUtils_LocationFromFullPath(strlen(thePath), thePath, myFSSpecPtr);
		
	free(myStringPtr);
	
	return(myFSSpecPtr);
}


//////////
//
// URLUtils_FSSpecToFullNativePath
// Convert an FSSpec into a full native pathname.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_FSSpecToFullNativePath (const FSSpecPtr theFSSpecPtr)
{
	char			*myPathName = NULL;
#if TARGET_OS_MAC	
	Handle			myHandle = NULL;
	short			myLength = 0;
#endif

	if (theFSSpecPtr == NULL)
		goto bail;

	myPathName = malloc(MAX_PATH);
	if (myPathName == NULL)
		goto bail;

#if TARGET_OS_WIN32
	// on Windows, this is easy (thanks to those hardworking QuickTime engineers)
	FSSpecToNativePathName(theFSSpecPtr, myPathName, MAX_PATH, kFullNativePath);	
#elif TARGET_OS_MAC	
	// on Macintosh, this is easy (thanks to that hardworking Jim Luther)
	URLUtils_FSpecGetFullPath(theFSSpecPtr, &myLength, &myHandle);
	BlockMove(*myHandle, myPathName, myLength);
	myPathName[myLength] = '\0';
	
	DisposeHandle(myHandle);
#endif

bail:
	return(myPathName);
}


//////////
//
// URLUtils_FSSpecToURL
// Convert an FSSpec into a local file URL.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_FSSpecToURL (const FSSpecPtr theFSSpecPtr)
{
	char		*myPathName = NULL;
	char		*myURL = NULL;
	
	myPathName = URLUtils_FSSpecToFullNativePath(theFSSpecPtr);
	myURL = URLUtils_FullNativePathToURL(myPathName);
	
	free(myPathName);
	return(myURL);
}


//////////
//
// URLUtils_URLToFSSpec
// Convert a local file URL into an FSSpec.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

FSSpecPtr URLUtils_URLToFSSpec (char *theURL)
{
	char		*myPathName = NULL;
	FSSpecPtr	myFSSpecPtr = malloc(sizeof(FSSpec));
	
	if (myFSSpecPtr == NULL)
		return(myFSSpecPtr);

	myPathName = URLUtils_URLToFullNativePath(theURL);
	myFSSpecPtr = URLUtils_FullNativePathToFSSpec(myPathName);
	
	free(myPathName);
	return(myFSSpecPtr);
}


//////////
//
// URLUtils_FSpecGetFullPath 
// Get a full path name from an FSSpec.
//
// This is straight out of MoreFiles 1.4 by Jim Luther; the only thing I did was to change the name
// and make the coding style consistent with the rest of this file.
//
// NOTE: This function is MACINTOSH ONLY.
//
//////////

OSErr URLUtils_FSpecGetFullPath (const FSSpecPtr theFSSpecPtr, short *theFullPathLength, Handle *theFullPath)
{
	FSSpec			myTempSpec;
	CInfoPBRec		myPBRec;
	OSErr			myErr = noErr;
	
	*theFullPathLength = 0;
	*theFullPath = NULL;
	
	// make a copy of the input FSSpec that can be modified
	BlockMoveData(theFSSpecPtr, &myTempSpec, sizeof(FSSpec));
	
	if (myTempSpec.parID == fsRtParID) {
		// the object is a volume; add a colon to make it a full pathname
		++myTempSpec.name[0];
		myTempSpec.name[myTempSpec.name[0]] = kFilePathSeparator;
		
		// we're done
		myErr = PtrToHand(&myTempSpec.name[1], theFullPath, myTempSpec.name[0]);
	} else {
		// the object isn't a volume; is the object a file or a directory?
		myPBRec.dirInfo.ioNamePtr = myTempSpec.name;
		myPBRec.dirInfo.ioVRefNum = myTempSpec.vRefNum;
		myPBRec.dirInfo.ioDrDirID = myTempSpec.parID;
		myPBRec.dirInfo.ioFDirIndex = 0;
		myErr = PBGetCatInfoSync(&myPBRec);
		if (myErr == noErr) {
			// if the object is a directory, append a colon so full pathname ends with colon
			if ((myPBRec.hFileInfo.ioFlAttrib & ioDirMask) != 0) {
				++myTempSpec.name[0];
				myTempSpec.name[myTempSpec.name[0]] = kFilePathSeparator;
			}
			
			// put the object name in first
			myErr = PtrToHand(&myTempSpec.name[1], theFullPath, myTempSpec.name[0]);
			if (myErr == noErr) {
				// get the ancestor directory names
				myPBRec.dirInfo.ioNamePtr = myTempSpec.name;
				myPBRec.dirInfo.ioVRefNum = myTempSpec.vRefNum;
				myPBRec.dirInfo.ioDrParID = myTempSpec.parID;
				
				// loop until we have an error or find the root directory
				do {
					myPBRec.dirInfo.ioFDirIndex = -1;
					myPBRec.dirInfo.ioDrDirID = myPBRec.dirInfo.ioDrParID;
					myErr = PBGetCatInfoSync(&myPBRec);
					if (myErr == noErr) {
						// append colon to directory name
						++myTempSpec.name[0];
						myTempSpec.name[myTempSpec.name[0]] = kFilePathSeparator;
						
						// add directory name to beginning of theFullPath
						(void)Munger(*theFullPath, 0, NULL, 0, &myTempSpec.name[1], myTempSpec.name[0]);
						myErr = MemError();
					}
				} while ((myErr == noErr) && (myPBRec.dirInfo.ioDrDirID != fsRtDirID));
			}
		}
	}
	if (myErr == noErr) {
		// return the length
		*theFullPathLength = GetHandleSize(*theFullPath);
	} else {
		// dispose of the handle and return NULL and zero length
		if (*theFullPath != NULL)
			DisposeHandle(*theFullPath);
		*theFullPath = NULL;
		*theFullPathLength = 0;
	}
	
	return(myErr);
}


//////////
//
// URLUtils_LocationFromFullPath 
// Get a full path name from an FSSpec.
//
// This is straight out of MoreFiles 1.4 by Jim Luther; the only thing I did was to change the name
// and make the coding style consistent with the rest of this file.
//
//////////

OSErr URLUtils_LocationFromFullPath (short theFullPathLength, const void *theFullPath, FSSpecPtr theFSSpecPtr)
{
	AliasHandle		myAliasHandle;
	Boolean			myWasChanged;
	Str32			myString;
	OSErr			myErr;
	
	// create a minimal alias from the full pathname
	myString[0] = 0;	// null string to indicate no zone or server name
	myErr = NewAliasMinimalFromFullPath(theFullPathLength, theFullPath, myString, myString, &myAliasHandle);
	if (myErr == noErr) {
		// let the Alias Manager resolve the alias
		myErr = ResolveAlias(NULL, myAliasHandle, theFSSpecPtr, &myWasChanged);
		DisposeHandle((Handle)myAliasHandle);
	}
	
	return(myErr);
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Relative URL utilities.
//
// Use these functions to manage relative URLs.
//
///////////////////////////////////////////////////////////////////////////////////////////////////////////

// TO BE PROVIDED



///////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Movie utilities.
//
// Use these functions to open movies or web pages addressed by URLs.
//
///////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////
//
// URLUtils_NewMovieFromURL
// Open the movie file referenced by the specified uniform resource locator (URL).
//
//////////

Movie URLUtils_NewMovieFromURL (char *theURL, short theFlags, short *theID)
{
	Movie		myMovie = NULL;
	Handle		myHandle = NULL;
	Size		mySize = 0;
	
	//////////
	//
	// copy the specified URL into a handle
	//
	//////////
	
	// get the size of the URL, plus the terminating null byte
	mySize = (Size)strlen(theURL) + 1;
	if (mySize == 0)
		goto bail;
	
	// allocate a new handle
	myHandle = NewHandleClear(mySize);
    if (myHandle == NULL)
    	goto bail;

	// copy the URL into the handle
	BlockMove(theURL, *myHandle, mySize);

	//////////
	//
	// instantiate a movie from the specified URL
	//
	// the data reference that is passed to NewMovieFromDataRef is a handle
	// containing the text of the URL, *with* a terminating null byte
	//
	//////////
	
	NewMovieFromDataRef(&myMovie, theFlags, theID, myHandle, URLDataHandlerSubType);

bail:
	if (myHandle != NULL)
		DisposeHandle(myHandle);
		
	return(myMovie);
}


//////////
//
// URLUtils_HaveBrowserOpenURL
// Tell the user's default web browser to open the specified uniform resource locator (URL).
//
//////////

OSErr URLUtils_HaveBrowserOpenURL (char *theURL)
{
	MovieController		myMC = NULL;
	Handle				myHandle = NULL;
	Size				mySize = 0;
	OSErr				myErr = noErr;
	
	//////////
	//
	// copy the specified URL into a handle
	//
	//////////
	
	// get the size of the URL, plus the terminating null byte
	mySize = (Size)strlen(theURL) + 1;
	if (mySize == 0)
		goto bail;
	
	// allocate a new handle
	myHandle = NewHandleClear(mySize);
    if (myHandle == NULL)
    	goto bail;

	// copy the URL into the handle
	BlockMove(theURL, *myHandle, mySize);

	//////////
	//
	// instantiate a movie controller and send it an mcActionLinkToURL message
	//
	//////////
	
	myErr = OpenADefaultComponent(MovieControllerComponentType, 0, &myMC);
	if (myErr != noErr)
		goto bail;
		
	myErr = MCDoAction(myMC, mcActionLinkToURL, (void *)myHandle);

bail:
	if (myHandle != NULL)
		DisposeHandle(myHandle);
		
	if (myMC != NULL)
		CloseComponent(myMC);
		
	return(myErr);
}


//////////
//
// URLUtils_GetURLBasename
// Return the basename of the specified URL.
//
// The basename of a URL is the portion of the URL following the rightmost URL separator. This function
// is useful for setting window titles of movies opened using the URL data handler to the basename of a
// URL (just like MoviePlayer does).
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_GetURLBasename (char *theURL)
{
	char	*myBasename = NULL;
	short	myLength = 0;
	short	myIndex;

	// make sure we got a URL passed in
	if (theURL == NULL)
		goto bail;
		
	// get the length of the URL
	myLength = strlen(theURL);
	
	// find the position of the rightmost URL path separator in theURL
	if (strchr(theURL, kURLPathSeparator) != NULL) {

		myIndex = myLength - 1;
		while (theURL[myIndex] != kURLPathSeparator)
			myIndex--;
			
		// calculate the length of the basename
		myLength = myLength - myIndex - 1;

	} else {
		// there is no rightmost URL path separator in theURL;
		// set myIndex so that myIndex + 1 == 0, for the call to BlockMove below
		myIndex = -1;
	}
	
	// allocate space to hold the string that we return to the caller
	myBasename = malloc(myLength + 1);
	if (myBasename == NULL)
		goto bail;
		
	// copy into myBasename the substring of theURL from myIndex + 1 to the end
	BlockMove(&theURL[myIndex + 1], myBasename, myLength);
	myBasename[myLength] = '\0';
	
bail:	
	return(myBasename);
}


//////////
//
// URLUtils_IsAbsoluteURL
// Is the specified string an absolute URL?
//
// An absolute URL must begin with an alphabetic character, and it must contain
// the URL scheme separator.
//
//////////

Boolean URLUtils_IsAbsoluteURL (char *theURL)
{
	if (theURL == NULL)
		return(false);
		
	if (URLUtils_IsAlphabetic(theURL[0]))
		if (strchr(theURL, kURLSchemeSeparator) != NULL)
			return(true);

	return(false);
}


//////////
//
// URLUtils_IsRelativeURL
// Is the specified string a relative URL?
//
//////////

Boolean URLUtils_IsRelativeURL (char *theURL)
{
	return(!URLUtils_IsAbsoluteURL(theURL));
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Character encoding utilities.
//
// Use these functions to encode or decode "escaped" characters within URLs. See RFC 1738 (found at the URL
// http://www.faqs.org/rfcs/rfc1738.html) for details on this character encoding. Here's the crucial nugget:
// "Octets must be encoded if they have no corresponding graphic character within the US-ASCII coded character
// set, if the use of the corresponding character is unsafe, or if the corresponding character is reserved for
// some other interpretation within the particular URL scheme."
//
///////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////
//
// URLUtils_IsReservedChar
// Is the specified character a reserved character?
//
//////////

Boolean URLUtils_IsReservedChar (char theChar)
{
	if ((theChar == ';') || (theChar == '/') || (theChar == '?') || (theChar == ':') || (theChar == '@') ||
		(theChar == '&') || (theChar == '='))
		return(true);

	return(false);
}


//////////
//
// URLUtils_IsDelimiterChar
// Is the specified character a delimiter?
//
//////////

Boolean URLUtils_IsDelimiterChar (char theChar)
{
	if ((theChar == '<') || (theChar == '>') || (theChar == '#'))
		return(true);

	return(false);
}


//////////
//
// URLUtils_IsUnsafeChar
// Is the specified character an unsafe character (which might get modified during transmission)?
//
//////////

Boolean URLUtils_IsUnsafeChar (char theChar)
{
	if ((theChar == '{') || (theChar == '}') || (theChar == '|') || (theChar == '\\') || (theChar == '^') ||
		(theChar == '~') || (theChar == '[') || (theChar == ']') || (theChar == '`')  || (theChar == '%'))
		return(true);

	return(false);
}


//////////
//
// URLUtils_IsPunctMarkChar
// Is the specified character a punctuation mark or similar symbol?
//
//////////

Boolean URLUtils_IsPunctMarkChar (char theChar)
{
	if ((theChar == '-') || (theChar == '_') || (theChar == '.') || (theChar == '!') || (theChar == '~') ||
		(theChar == '*') || (theChar == '(') || (theChar == ')') || (theChar == '"') || (theChar == '\''))
		return(true);

	return(false);
}


//////////
//
// URLUtils_IsEncodableChar
// Is the specified character a character that should be encoded?
//
//////////

Boolean URLUtils_IsEncodableChar (char theChar)
{
	// all control characters and high-ASCII characters are encodable
	if ((theChar <= 0x1f) || (theChar >= 0x7f))
		return(true);
	
	// the space character is encodable
	if (theChar == 0x20)
		return(true);
	
	// all delimiters are encodable
	if (URLUtils_IsDelimiterChar(theChar))
		return(true);
	
	// all unsafe characters are encodable
	if (URLUtils_IsUnsafeChar(theChar))
		return(true);
	
	return(false);
}


//////////
//
// URLUtils_EncodeString 
// Convert any special characters in the specified string into their encoded versions.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_EncodeString (char *theString)
{
	char		*myEncodedStr = NULL;	
	char		myChar;
	short		myCount = 0;
	short		myIndex;

	if (theString == NULL)
		goto bail;

	// count the number of special characters that need converting
	for (myIndex = 0; myIndex < strlen(theString); myIndex++)
		if (URLUtils_IsEncodableChar(theString[myIndex]))
			myCount++;

	// allocate a character string of the proper size;
	// each encoded character increases the length of the original string by 2 bytes
	myEncodedStr = malloc(strlen(theString) + (myCount * 2) + 1);
	if (myEncodedStr == NULL)
		goto bail;

	// traverse the URL, encoding encodable characters as we go
	for (myCount = 0, myIndex = 0; myIndex < strlen(theString); myIndex++) {
		if (URLUtils_IsEncodableChar(theString[myIndex])) {
			myEncodedStr[myCount + 0] = kURLEscapeCharacter;
	        myChar = (theString[myIndex] >> 4) & 0x0f;
	        myEncodedStr[myCount + 1] = myChar + ((myChar <= 9) ? '0' : ('A' - 10));
	        myChar = theString[myIndex] & 0x0f;
	        myEncodedStr[myCount + 2] = myChar + ((myChar <= 9) ? '0' : ('A' - 10));
			myCount += 3;		
		} else {
			myEncodedStr[myCount] = theString[myIndex];
			myCount++;		
		}
	}
	
	myEncodedStr[myCount] = '\0';
	
bail:
	return(myEncodedStr);
}


//////////
//
// URLUtils_DecodeString 
// Convert any encoded characters in the specified string into their unencoded versions.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

char *URLUtils_DecodeString (char *theString)
{
	char		*myDecodedStr = NULL;	
	char		myChar, myTemp1, myTemp2;
	short		myCount = 0;
	short		myIndex;
	short		myLength;

	if (theString == NULL)
		goto bail;

	// count the number of escape characters in the string
	for (myIndex = 0; myIndex < strlen(theString); myIndex++)
		if (theString[myIndex] == kURLEscapeCharacter)
			myCount++;

	// allocate a character string of the proper size;
	// each encoded character decreases the length of the original string by 2 bytes
	myLength = strlen(theString) + 1 - (myCount * 2);
	myDecodedStr = malloc(myLength);
	if (myDecodedStr == NULL)
		goto bail;

	// traverse the URL, decoding encoded characters as we go
	for (myCount = 0, myIndex = 0; myIndex < myLength; myIndex++) {
		if (theString[myCount] == kURLEscapeCharacter) {
		
			// make sure that any hex digits are uppercase
			myTemp1 = URLUtils_ToUppercase(theString[myCount + 1]);
			myTemp2 = URLUtils_ToUppercase(theString[myCount + 2]);
		
			myChar = ((myTemp1 - ((myTemp1 <= '9' ? '0' : 'A' - 10))) << 4) & 0xf0;
			myChar += (myTemp2 - ((myTemp2 <= '9' ? '0' : 'A' - 10))) & 0x0f;
			myDecodedStr[myIndex] = myChar;
			myCount += 3;
		} else {
			myDecodedStr[myIndex] = theString[myCount];
			myCount++;
		}
	}
	
	myDecodedStr[myLength] = '\0';
	
bail:
	return(myDecodedStr);
}


//////////
//
// URLUtils_ConvertCToPascalString
// Convert a C string into a Pascal string.
//
// The caller is responsible for disposing of the pointer returned by this function (by calling free).
//
//////////

StringPtr URLUtils_ConvertCToPascalString (char *theString)
{
	StringPtr	myString = malloc(strlen(theString) + 1);
	short		myIndex = 0;

	while (theString[myIndex] != '\0') {
		myString[myIndex + 1] = theString[myIndex];
		myIndex++;
	}
	
	myString[0] = (unsigned char)myIndex;
	
	return(myString);
}



#endif	// ifndef __URLUtilities__