/*
	File:		MyDocument.m
	
	Description: Document-specific code for thread-safety test application.

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
				
	Change History (most recent first): <1> dts 04/05/04 fixes for initial release

*/

//////////
//
// header files
//
//////////

#import "MyDocument.h"
#import "AutoRunSettings.h"
#import "DataRefUtilities.h"
#import "WorkerThread.h"

//////////
//
// non-Controller function declarations
//
//////////

static OSErr importTheMovie (ThreadData *threadData);
static OSErr movieProgressProc (Movie theMovie, short message, short whatOperation, Fixed percentDone, long refcon);

void workerActionRoutine (void *refcon, WorkerRequestRef request);
void workerCancelRoutine (void *refcon, WorkerRequestRef request);
void workerResponseMainThreadCallback (void *refcon, WorkerRequestRef request);

//////////
//
// static global variables
//
//////////

static MovieProgressUPP	gMovieProgressProcUPP = NULL;   // UPP for our progress procedure
static UInt32           gNumIteration = 0;			
static unsigned long	gOSVersion = 0;

//////////
//
// MyDocument implementation
//
//////////

@implementation MyDocument

- (id)init
{
    WorkerThreadRef outWorker = NULL; 
    
    [super init];
    if (self) {
    
	autoRunSettings = [[AutoRunSettings alloc] init];

        _threadModelTag = USE_POSIX_THREAD;     // use POSIX threads by default
        _dhTag = USE_FILE_DH;					// use file data handler by default
        _onlySafeComps = YES;					// use only thread-safe components by default
        _useFileName = YES;                     // tag Handle and Pointer data references with file name extension
        _useFileType = NO;
        _useMIMEType = NO;
        
        // allocate progress proc UPP, if necessary
        if (gMovieProgressProcUPP == NULL)
            gMovieProgressProcUPP = NewMovieProgressUPP(movieProgressProc);

        // get the current version of the OS we're running on
        Gestalt(gestaltSystemVersion, &gOSVersion);
        if (gOSVersion < 0x00001030) {
            // thread-safe components are available only in 10.3 (Panther) and beyond; for earlier systems,
            // don't allow POSIX threads
            _threadModelTag = USE_MAIN_THREAD;
        }

        // add a notification observer to monitor selections in the file table view
        [[NSNotificationCenter defaultCenter]	addObserver:self
                                                selector:@selector(tableViewSelectionDidChange:)
                                                name:NSTableViewSelectionDidChangeNotification
                                                object:tableView];
                                                
        // create a worker thread handler
        createWorkerThread(
                workerActionRoutine,
                workerCancelRoutine,
                workerResponseMainThreadCallback,
                (void *)self,
                &outWorker);
        _worker = outWorker;
    }
    
    return self;
}

- (void)dealloc
{    
    // stop auto-running
    [self setAutoRunTimer:nil];

    // remove the worker thread handler
    releaseWorkerThread(_worker);

    // remove the notification that monitors selections in the file table view
    [[NSNotificationCenter defaultCenter]	removeObserver:self
                                                name:NSTableViewSelectionDidChangeNotification
                                                object:tableView];
                                                
    // clean up the list of Movies
    [self setFileArray:nil];

    // dispose of the thread data and any memory it accesses
    if (_currThreadData != NULL)
        if (_currThreadData->threadModelTag == USE_MAIN_THREAD)
            [self setCurrThreadData:nil];
    
    [autoRunSettings release];
    
    [super dealloc];
}

- (NSString *)windowNibName
{
    return @"MyDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [quickdrawView setDocument: self];
    [super windowControllerDidLoadNib:aController];
}

- (void)showWindows
{
	[super showWindows];
	[self updateWindowTitle];
}

- (NSData *)dataRepresentationOfType:(NSString *)aType
{
    return nil;
}

- (BOOL)loadDataRepresentation:(NSData *)data ofType:(NSString *)aType
{
    return YES;
}

    //////////
    //
    // window notifications
    //
    //////////

- (void)windowWillClose:(NSNotification*)notification
{
    // note that NSTimer's scheduledTimerWithTimeInterval method increments the retain count of its target, 
    // so we cannot release a timer in our dealloc method (since that method will never get called if at least one timer is active...)
    
    // stop the timer
    [self setAutoRunTimer:nil];
}

    //////////
    //
    // window delegates
    //
    //////////

- (BOOL)windowShouldClose:(id)sender
{
    WorkerRequestRef wkrRequest = NULL;

    // the window wants to close; make sure the threads are closed down
    if (_currThreadData != NULL) {
        if (_currThreadData->threadModelTag == USE_POSIX_THREAD) {
            if (_currThreadData->busy) {
                // cancel the current worker request
                wkrRequest = _currThreadData->request;
                if (wkrRequest != NULL) {
                    // it's not safe to close the document window right now; cancel any current request
                    // and mark the document as wanting to be closed when it's safe to do so
                    cancelWorkerRequest(wkrRequest);
                    _currThreadData->closeWhenSafe = YES;
                    return NO;
                }
            }
        } else if (_currThreadData->threadModelTag == USE_MAIN_THREAD) {
            // dispose of the thread data and any memory it accesses
            [self setCurrThreadData:NULL];
        }
    }

    return YES;
}

    //////////
    //
    // the main drawing routine
    //
    // draw the Movie into the NSQuickDrawView in the document window; this method is *always* called on the main thread
    //
    //////////

- (void)updateQDMovieView:(ThreadData *)threadData updateTime:(BOOL)doUpdateTime
{
    GrafPtr port = NULL;
    CGrafPtr savedPort = NULL;
    GDHandle savedGDevice = NULL;
    Rect srcRect;
    Rect dstRect;
    Rect viewRect;
    float MovieWidth, MovieHeight;
    float viewWidth, viewHeight;
    float newWidth, newHeight;
    NSMutableString *sizeString = [NSMutableString string];
    UnsignedWide endTime;
    
    if (threadData == NULL)
        return;
        
    // update the elapsed time indicator, if so instructed
    if (doUpdateTime) {
        Microseconds(&endTime);
        [timeField setDoubleValue: endTime.lo - threadData->startTime.lo];
    }
    
    // stop the progress indicator
    [progressBar stopAnimation:nil];

    _doneDrawing = false;		// a flag for cycleMovies: method

    port = [quickdrawView qdPort];
    if (port == NULL)
        return;
  
    // display the natural size of the Movie
    [sizeString appendFormat:@"%i", threadData->naturalWidth];
    [sizeString appendString:@" x "];
    [sizeString appendFormat:@"%i", threadData->naturalHeight];
    [sizeField setStringValue:sizeString];

    // get the current port and device
    GetGWorld(&savedPort, &savedGDevice);
    
    // set the NSQuickDrawView port to be the current port
    SetGWorld(port, NULL);

    // erase the NSQuickDrawView
    GetPortBounds(port, &viewRect);
    EraseRect(&viewRect);
    
    // set the thread data passed in as the current thread data
    [self setCurrThreadData:threadData];
    
    if (threadData->gWorld != NULL) {
        GetPortBounds(threadData->gWorld, &srcRect);
        LockPixels(GetGWorldPixMap(threadData->gWorld));

        // scale the destination rectangle so that the Movie fits into the NSQuickDrawView while retaining its aspect ratio
        MovieWidth = srcRect.right - srcRect.left;
        MovieHeight = srcRect.bottom - srcRect.top;
        viewWidth = viewRect.right - viewRect.left;
        viewHeight = viewRect.bottom - viewRect.top;
        
        dstRect.top = 0;
        dstRect.left = 0;
        
        if ((threadData->naturalWidth <= viewWidth) && (threadData->naturalHeight <= viewHeight)) {
            dstRect.right = MovieWidth;
            dstRect.bottom = MovieHeight;
        } else {
            float MovieRatio = MovieWidth / MovieHeight;
            float viewRatio = viewWidth / viewHeight;
            
            if (MovieRatio > viewRatio) {
                // the Movie is wider than will fit; rescale
                newHeight = viewWidth / MovieRatio;
                newWidth = newHeight * MovieRatio;
                
                dstRect.right = newWidth;
                dstRect.bottom = newHeight;
            } else {
                // the Movie is taller than will fit; rescale
                newWidth = viewHeight * MovieRatio;
                newHeight = newWidth / MovieRatio;
                
                dstRect.right = newWidth;
                dstRect.bottom = newHeight;
            }
        }
        LockPixels(GetPortPixMap(port));
        
        CopyBits(GetPortBitMapForCopyBits(threadData->gWorld), GetPortBitMapForCopyBits(port), &srcRect, &dstRect, srcCopy, NULL);

        UnlockPixels(GetGWorldPixMap(threadData->gWorld));
        UnlockPixels(GetPortPixMap(port));
        
        // make sure our drawing appears in the window
        QDFlushPortBuffer(port, NULL);
    }

    // restore the original port and device
    SetGWorld(savedPort, savedGDevice);

    _doneDrawing = true;		// a flag for cycleMovies: method
}

- (void)cycleMovies:(NSTimer *)timer
{
    UInt32 currRow = [tableView selectedRow];

    // if the current Movie has been drawn, select the next item in the list of Movies; at the end, loop back to the beginning
    if (_doneDrawing) {
        if (_randomAutoRun) {
            // select a random row between 0 and [tableView numberOfRows] - 1
            double randNum = (rand()/(double)RAND_MAX) * [tableView numberOfRows];
            UInt32 nextRow = (UInt32)randNum;

            if (currRow == nextRow) {
                nextRow++;
                if (nextRow >= [tableView numberOfRows]) {
                    nextRow = 0;
                }
            }
                
            _doneDrawing = false;
            [tableView selectRow:nextRow byExtendingSelection:NO];
        } else {
            if ((gNumIteration < _autoRunIterations) || (_autoRunIterations == 0)) {
    
                currRow++;
                if (currRow == [tableView numberOfRows]) {
                    currRow = 0;
                    gNumIteration++;
                }
                
                _doneDrawing = false;
                [tableView selectRow:currRow byExtendingSelection:NO];
            } else {
                // stop the auto-run
                [self setAutoRunTimer:nil];
                [autorunBtn setTitle:@"Auto-Run"]; 
            }
        }
    }
}

    //////////
    //
    // button action handlers
    //
    //////////

- (IBAction)autoRun:(id)sender {
    gNumIteration = 0;						// reset iteration counter
    [tableView selectRow:0 byExtendingSelection:NO];
    
    if (_autorunTimer == nil) {
        [self setAutoRunTimer:[NSTimer
                scheduledTimerWithTimeInterval:kAutoRunInterval 
                target:self 
                selector:@selector(cycleMovies:) 
                userInfo:nil 
                repeats:YES]];
        [[NSRunLoop currentRunLoop] addTimer:[self autorunTimer] forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer:[self autorunTimer] forMode:NSEventTrackingRunLoopMode];
        [autorunBtn setTitle:@"Stop"]; 
    } else {
        [self setAutoRunTimer:nil];
        [autorunBtn setTitle:@"Auto-Run"]; 
    }   
}

- (IBAction)selectFolder:(id)sender
{
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    NSString *filename;
    NSEnumerator *enumerator = nil;
    UInt32 count = 0;
    UInt32 dirPathLength = 0;
    int result;

    // elicit a folder from the user
    [oPanel setCanChooseDirectories:YES];
    [oPanel setCanChooseFiles:NO];
    [oPanel setAllowsMultipleSelection:NO];
    
    result = [oPanel runModalForTypes:nil];
    if (result != NSOKButton)
        return;
    
    // no current thread data yet...
    _currThreadData = NULL;
    
    // enable the auto-run button but disable the select-folder button
    [autorunBtn setEnabled:YES];
    [folderBtn setEnabled:NO];
    
    // allocate and retain a file array
    [self setFileArray:[NSMutableArray array]];

    dirPathLength = [[[oPanel filenames] objectAtIndex:0] cStringLength];
    
    // put filenames and full pathnames into the file array
    enumerator = [[[NSFileManager defaultManager] directoryContentsAtPath: [[oPanel filenames] objectAtIndex:0]] objectEnumerator];
    while (filename = [enumerator nextObject]) {
        if ([filename length] > 0) {
            // don't allow any "hidden" files
            if ([filename characterAtIndex:0] == '.')
                continue;
         
            FileObject *aFileObject = [[FileObject alloc] init];           
            char *cFileName, *cPathName;
        
            cFileName = malloc([filename cStringLength] + 1);
            cPathName = malloc([filename cStringLength] + dirPathLength + 2);
            if ((cFileName != NULL) && (cPathName != NULL)) {
                [filename getCString:cFileName];
                [[[oPanel filenames] objectAtIndex:0] getCString:cPathName];
                *(cPathName + dirPathLength) = '/';
                [filename getCString:cPathName + dirPathLength + 1];
                
                [aFileObject setPathName: cPathName];
                [aFileObject setFileName: cFileName];
            }
            
            // don't put directories in the list
            NSDictionary *fattrs = [[NSFileManager defaultManager] fileAttributesAtPath:[NSString stringWithCString:cPathName] traverseLink:YES];        
            if (fattrs) {
                NSString *fileType = [fattrs objectForKey:NSFileType];
                if (fileType == NSFileTypeRegular) {
                    [_fileArray insertObject:aFileObject atIndex:count];
                    count++;
                }
                
                [aFileObject release];	// was retained by the array, so release this instance
            }
        }
    }

    // select the first item in the list, and reload the data
    [tableView selectRow:0 byExtendingSelection:NO];
    [tableView reloadData];
    [[tableView window] makeFirstResponder:tableView];
    
    [self updateWindowTitle];
}

    //////////
    //
    // table notification handler and data source methods
    //
    //////////

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    ThreadData *threadData = NULL;
    WorkerRequestRef wkrRequest = NULL;
    Rect tinyRect = {0,0,1,1};
    OSErr err = noErr;

    // make sure it's a notification for me
    if ([aNotification object] != tableView)
        return;
        
    // initialize the elapsed time indicator
    [timeField setIntValue: 0];
    
    // clear the status field
    [statusField setStringValue:@""];

    // determine whether an Movie is currently being imported; if so, try to cancel the import
    // if it's not on the main thread
    if (_currThreadData != NULL) {
        if (_currThreadData->threadModelTag == USE_POSIX_THREAD) {
            if (_currThreadData->busy) {
                // cancel the current worker request
                wkrRequest = _currThreadData->request;
                if (wkrRequest != NULL) {
                    cancelWorkerRequest(wkrRequest);
                }
            }
        } else if (_currThreadData->threadModelTag == USE_MAIN_THREAD) {
            // dispose of the thread data and any memory it accesses
            [self setCurrThreadData:NULL];
        }
    }

    // load the Movie currently selected in the list of files
    _fileObject = [_fileArray objectAtIndex:[tableView selectedRow]];
    if (_fileObject) {
    
        // start the progress indicator animation
        [progressBar startAnimation:nil];
        
        // each import operation gets its own thread data
        threadData = calloc(1, sizeof(ThreadData));
        if (threadData == NULL)
            return;

        // configure the thread data to the current settings
        threadData->dhTag = _dhTag;
        threadData->threadModelTag = _threadModelTag;
        threadData->fileObject = _fileObject;
        threadData->movieRect = [self qdViewBounds];
        threadData->onlySafeComps = _onlySafeComps;
        threadData->useFileName = _useFileName;
        threadData->useFileType = _useFileType;
        threadData->useMIMEType = _useMIMEType;

       // create a scratch GWorld
        err = NewGWorld(&threadData->tinyGW, 32, &tinyRect, NULL, NULL, 0);
        LockPixels(GetPortPixMap(threadData->tinyGW));
        
        [self setCurrThreadData:threadData];
        
        switch (_threadModelTag) {
            case USE_MAIN_THREAD:
                // import the file on the main thread
                threadData->busy = true;

                // in theory, we could force threadData->onlySafeComps to be false here,
                // in which case we can dispense with the retry logic just below;
                // for demo/testing purposes, I'm going to follow the user's explicit selection

                importTheMovie(threadData);
                
                if (threadData->retry) {
                    [statusField setStringValue:@"Retried import on main thread with any components!"];
                    threadData->onlySafeComps = false;
        
                    importTheMovie(threadData);
                }
                
                threadData->busy = false;
                [self updateQDMovieView:threadData updateTime:YES];

                break;

            case USE_POSIX_THREAD:
                // import the file on a pthread; create, configure, and send a new worker request
                err = createWorkerRequest(_worker, &wkrRequest);
                if (err == noErr) {
                    setWorkerRequestThreadData(wkrRequest, threadData);
                    setWorkerRequestDoc(wkrRequest, (UInt32)self);
                    threadData->request = wkrRequest;
                }

                if (err == noErr) {
                    threadData->busy = true;
                    err = sendWorkerRequest(wkrRequest);
                }
                break;
        }
    }
}

// table data source methods

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [[self fileArray] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(id)column row:(int)row
{
    FileObject *aFileObject;
    
    aFileObject = [[self fileArray] objectAtIndex:row];
    return [NSString stringWithCString: [aFileObject fileName]];
}

    //////////
    //
    // auto-run settings
    //
    //////////

- (void)setIterations:(UInt32)iterations
{
    _autoRunIterations = iterations;
}

- (void)setRandom:(UInt32)random
{
    _randomAutoRun = random;
}

    //////////
    //
    // menu validator and handlers
    //
    //////////

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    BOOL isValid = NO;
    SEL action = [item action];
    
    if ((action == @selector(usePOSIXThreads:)) || 
        (action == @selector(useMainThread:))) {
        [item setState: ([item tag] == _threadModelTag) ? NSOnState : NSOffState];
        isValid = YES;
        
        // disable POSIX threads on systems earlier than 10.3
        if (gOSVersion < 0x00001030)
            if (action == @selector(usePOSIXThreads:))
                isValid = NO;
    }
    
    if ((action == @selector(useHandleDH:)) || 
        (action == @selector(usePointerDH:)) || 
        (action == @selector(useFileDH:)) || 
        (action == @selector(useURLDH:))) {
        [item setState: ([item tag] == _dhTag) ? NSOnState : NSOffState];
        isValid = YES;
    }
        
    if (action == @selector(toggleThreadGuard:)) {
        [item setState: _onlySafeComps ? NSOnState : NSOffState];
        isValid = YES;
    }
    
    if (action == @selector(doAutoRunSettingsBox:)) {
        isValid = YES;
    }
    
    if (action == @selector(useFileName:)) {
        [item setState: _useFileName ? NSOnState : NSOffState];
        if ((_dhTag == USE_HANDLE_DH) || (_dhTag == USE_POINTER_DH)) {
            if (_useFileType == NSOffState && _useMIMEType == NSOffState) {
                _useFileName = NSOnState;
                [item setState: _useFileName];
            }
            isValid = YES;
        }
    }
    
    if (action == @selector(useFileType:)) {
        [item setState: _useFileType ? NSOnState : NSOffState];
        if ((_dhTag == USE_HANDLE_DH) || (_dhTag == USE_POINTER_DH))
            isValid = YES;
    }
    
    if (action == @selector(useMIMEType:)) {
        [item setState: _useMIMEType ? NSOnState : NSOffState];
        if ((_dhTag == USE_HANDLE_DH) || (_dhTag == USE_POINTER_DH))
            isValid = YES;
    }
    
    return isValid;
}

- (IBAction)useHandleDH:(id)sender
{
    _dhTag = USE_HANDLE_DH;
    [self updateWindowTitle];
}

- (IBAction)usePointerDH:(id)sender
{
    _dhTag = USE_POINTER_DH;
    [self updateWindowTitle];
}

- (IBAction)useFileDH:(id)sender
{
    _dhTag = USE_FILE_DH;
    [self updateWindowTitle];
}

- (IBAction)useURLDH:(id)sender
{
    _dhTag = USE_URL_DH;
    [self updateWindowTitle];
}

- (IBAction)usePOSIXThreads:(id)sender
{
    _threadModelTag = USE_POSIX_THREAD;
    [self updateWindowTitle];
}

- (IBAction)useMainThread:(id)sender
{
    _threadModelTag = USE_MAIN_THREAD;
    [self updateWindowTitle];
}

- (IBAction)toggleThreadGuard:(id)sender
{
    _onlySafeComps = !_onlySafeComps;
    [self updateWindowTitle];
}

- (IBAction)useFileName:(id)sender
{
    _useFileName = !_useFileName;
}

- (IBAction)useFileType:(id)sender
{
    _useFileType = !_useFileType;
}

- (IBAction)useMIMEType:(id)sender
{
    _useMIMEType = !_useMIMEType;
}

- (IBAction)doAutoRunSettingsBox:(id)sender
{
    // show the autorun settings box
    [autoRunSettings showSettingsPanel];
}

- (void)updateWindowTitle
{
    // set the window title to reflect the current thread/data handler/etc. settings
    NSMutableString *titleString = [NSMutableString string];
    
    switch (_threadModelTag) {
        case USE_POSIX_THREAD:
            [titleString appendFormat: @"PThreads * "];
            break;
    
        case USE_MAIN_THREAD:
            [titleString appendFormat: @"Main Thread * "];
    }
    
    switch (_dhTag) {
        case USE_HANDLE_DH:
            [titleString appendFormat: @"Handle DH * "];
            break;
    
        case USE_POINTER_DH:
            [titleString appendFormat: @"Pointer DH * "];
            break;
    
        case USE_FILE_DH:
            [titleString appendFormat: @"File DH * "];
            break;
    
        case USE_URL_DH:
            [titleString appendFormat: @"URL DH * "];
    }
    
    if (_onlySafeComps)
        [titleString appendFormat: @"Safe Components"];
    else
        [titleString appendFormat: @"Any Components"];

    [[folderBtn window] setTitle:titleString];
}

    //////////
    //
    // getters and setters
    //
    //////////

- (id)statusField;
{
    return statusField;
}

- (Rect)qdViewBounds
{
    GrafPtr port = NULL;
    Rect viewRect = {0, 0, 0, 0};
    
    port = [quickdrawView qdPort];
    
    GetPortBounds(port, &viewRect);
    return viewRect;
}

- (void *)currThreadData
{
    return _currThreadData;
}

- (void)setCurrThreadData:(ThreadData *)threadData
{
    if (_currThreadData && (_currThreadData != threadData) && (!_currThreadData->busy)) {
        [self disposeThreadData:_currThreadData];
    }
    
    _currThreadData = threadData;
}

- (void)disposeThreadData:(ThreadData *)threadData
{
    if (threadData) {
        if (threadData->gWorld)
            DisposeGWorld(threadData->gWorld);
        
        if (threadData->tinyGW)
            DisposeGWorld(threadData->tinyGW);

        free(threadData);
    }
}

- (NSMutableArray *)fileArray
{
    return _fileArray;
}

- (void)setFileArray:(NSMutableArray *)array
{
    [_fileArray release];
    [array retain];
    _fileArray = array;
}

- (NSTimer *)autorunTimer
{
    return _autorunTimer;
}

- (void)setAutoRunTimer:(NSTimer *)theTimer
{
    [_autorunTimer invalidate];
    [_autorunTimer release];
    [theTimer retain];
    _autorunTimer = theTimer;
}

@end

//////////
//
// static functions
//
//////////

static OSErr importTheMovie (ThreadData *threadData)
{
    FileObject *aFileObject = nil;
    FSSpec fileSpec;
    FSRef fileRef;
    Rect naturalBounds;
    Rect dstRect;
    OSType drType;
    UInt32 dhTag;
    char strLenByte = 0;
    Movie movie = NULL;
    void *moviePointer = NULL;
    Handle movieHandle = NULL;
    Handle drHandle = NULL;
    short fileResNum = -1;
    long atoms[3];
    ComponentResult err = noErr;
    CGrafPtr savedPort = NULL;
    GDHandle savedGDevice = NULL;

    if (threadData == NULL)
        return paramErr;

    aFileObject = threadData->fileObject;
    if (aFileObject == nil) return paramErr;

    dhTag = threadData->dhTag;
    
    // override the thread mode (for testing/demo purposes)
    CSSetComponentsThreadMode(threadData->onlySafeComps ? kCSAcceptThreadSafeComponentsOnlyMode : kCSAcceptAllComponentsMode);
    
    // get the current port and device
    GetGWorld(&savedPort, &savedGDevice);
    
    if (threadData->cancelled)
        goto bail;

    //////////
    //
    // create the appropriate type of data reference
    //
    //////////
    
    switch (dhTag) {
        case USE_POINTER_DH:
        case USE_HANDLE_DH: {
            short fileRefNum;
            long numbytes;
                
            err = FSPathMakeRef([aFileObject pathName], &fileRef, NULL);
            if (err != noErr) {
                fprintf(stderr, "FSPathMakeRef(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
 
            err = FSGetCatalogInfo(&fileRef, kFSCatInfoNone, NULL, NULL, &fileSpec, NULL);
            if (err != noErr) {
                fprintf(stderr, "FSGetCatalogInfo(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
 
            err = FSpOpenDF(&fileSpec, fsRdPerm, &fileRefNum);
            if (err != noErr) {
                fprintf(stderr, "FSpOpenDF(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
 
            err = GetEOF(fileRefNum, &numbytes);
            if (err != noErr) {
                fprintf(stderr, "GetEOF(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }

            if (dhTag == USE_HANDLE_DH) {
                movieHandle = NewHandleClear(numbytes);
                HLock(movieHandle);
                moviePointer = (void *)*movieHandle;
            } else {
                moviePointer = calloc(1, numbytes);
            }
                
            if (moviePointer == NULL) {
                fprintf(stderr, "NewHandleClear or calloc(\"%s\") failed (%d)\n", [aFileObject fileName], (int)memFullErr);
                goto bail;
            }
 
            err = FSRead(fileRefNum, &numbytes, moviePointer);
            FSClose(fileRefNum);
            if (err != noErr) {
                fprintf(stderr, "FSRead(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
            
            if (dhTag == USE_HANDLE_DH) {
                drHandle = QTDR_MakeHandleDataRef(movieHandle);
                drType = HandleDataHandlerSubType;
            } else {
                drHandle = QTDR_MakePointerDataRef(moviePointer, numbytes);
                drType = PointerDataHandlerSubType;
            }
            
            if (drHandle == NULL) {
                fprintf(stderr, "QTDR_MakeHandleDataRef or QTDR_MakePointerDataRef(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
            
            // for more information regarding tagging Handle and Pointer Data References see TN1195
            // http://developer.apple.com/technotes/tn/tn1195.html
            if (threadData->useFileName) {
                // add a filenaming extension
                strLenByte = strlen([aFileObject fileName]);
                err = PtrAndHand(&strLenByte, drHandle, 1);
                err = PtrAndHand([aFileObject fileName], drHandle, strlen([aFileObject fileName]));
            } else if (threadData->useFileType || threadData->useMIMEType) {
                // when adding other extensions file name must be included even if it's just empty
                strLenByte = 0;
                err = PtrAndHand(&strLenByte, drHandle, sizeof(strLenByte));
            }

            if (threadData->useFileType) {
                // add a file type extension
                OSType fileType = 0;
                
                fileType = [aFileObject fileType];
                if (fileType) {
                    atoms[0] = EndianU32_NtoB(sizeof(long) * 3);
                    atoms[1] = EndianU32_NtoB(kDataRefExtensionMacOSFileType);
                    atoms[2] = EndianU32_NtoB(fileType);
                
                    err = PtrAndHand(atoms, drHandle, sizeof(long) * 3);
                    if (err) goto bail;
                } 
            }

            if (threadData->useMIMEType) {
                // add a MIME type extension
                StringPtr mimeTypePStringPtr;
                
                mimeTypePStringPtr = [aFileObject mimeType];

                atoms[0] = EndianU32_NtoB(sizeof(long) * 2 + mimeTypePStringPtr[0] + 1);
                atoms[1] = EndianU32_NtoB(kDataRefExtensionMIMEType);
                
                err = PtrAndHand(atoms, drHandle, sizeof(long) * 2);
                if (err) goto bail;
                
                err = PtrAndHand(mimeTypePStringPtr, drHandle, mimeTypePStringPtr[0] + 1);
                if (err) goto bail;
            }
            
            break;
        }
            
        case USE_FILE_DH:
            err = FSPathMakeRef([aFileObject pathName], &fileRef, NULL);
            if (err != noErr) {
                fprintf(stderr, "FSPathMakeRef(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
 
            err = FSGetCatalogInfo(&fileRef, kFSCatInfoNone, NULL, NULL, &fileSpec, NULL);
            if (err != noErr) {
                fprintf(stderr, "FSGetCatalogInfo(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
 
            drHandle = QTDR_MakeFileDataRef(&fileSpec);
            if (drHandle == NULL) {
                fprintf(stderr, "QTDR_MakeFileDataRef(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                goto bail;
            }
            
            drType = rAliasType;
            break;
            
        case USE_URL_DH: {
            char *url = [aFileObject url];
            
            if (url != NULL) {
                drHandle = QTDR_MakeURLDataRef(url);
                if (drHandle == NULL) {
                    fprintf(stderr, "QTDR_MakeURLDataRef(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
                    goto bail;
                }
            }
            
            drType = URLDataHandlerSubType;
            break;
        }
    }
    
    Microseconds(&threadData->startTime);

    //////////
    //
    // open the file using the data reference and draw it into a new GWorld
    //
    //////////
    
    if (threadData->cancelled)
        goto bail;
        
    // gotta have a valid port for when we open movies
    SetGWorld(threadData->tinyGW, NULL);
    
    err = NewMovieFromDataRef(&movie, newMovieActive, &fileResNum, drHandle, drType);
    if (err != noErr) {
        // if we get componentNotThreadSafeErr, we need to retry importing on the main thread
        if (err == componentNotThreadSafeErr) {
            if (threadData->onlySafeComps) {
                // set a flag to indicate we need to retry on main thread, allowing non-safe components
                threadData->retry = true;
                goto bail;
            } else {
                // this should *really* never happen....
                fprintf(stderr, "NewMovieFromDataRef(\"%s\") returned componentNotThreadSafeErr but with any components allowed!\n", [aFileObject fileName]);
                goto bail;
            }
        }

	fprintf(stderr, "NewMovieFromDataRef(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
        goto bail;
    }
    
    GetMovieNaturalBoundsRect(movie, &naturalBounds);
    err = GetMoviesError();
    if (err != noErr) {
	fprintf(stderr, "GetMovieNaturalBounds(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
        goto bail;
    }
    
    // save the natural width and height of the Movie
    threadData->naturalWidth = naturalBounds.right - naturalBounds.left;
    threadData->naturalHeight = naturalBounds.bottom - naturalBounds.top;
    
    // create a GWorld for the natural bounds of the movie
    // when we draw we preservethe aspect ratio of the Movie depending on the
    // NSQuickDrawView bounds and the Movies natural bounds
    dstRect = naturalBounds;
    OffsetRect(&dstRect, -naturalBounds.left, -naturalBounds.top);
        
/*    // create a GWorld for the smaller of qdViewBounds and naturalBounds, while preserving the aspect ratio of the Movie
    float movieWidth, movieHeight;
    float viewWidth, viewHeight;
    float newWidth, newHeight;

    qdViewBounds = threadData->movieRect;

    movieWidth = naturalBounds.right - naturalBounds.left;
    movieHeight = naturalBounds.bottom - naturalBounds.top;
    viewWidth = qdViewBounds.right - qdViewBounds.left;
    viewHeight = qdViewBounds.bottom - qdViewBounds.top;
    
    dstRect.top = 0;
    dstRect.left = 0;
    
    if (((movieWidth) <= (viewWidth)) && ((movieHeight) <= (viewHeight))) {
        dstRect.right = movieWidth;
        dstRect.bottom = movieHeight;
    } else {
        float movieRatio = movieWidth / movieHeight;
        float viewRatio = viewWidth / viewHeight;
        
        if (movieRatio > viewRatio) {
            // the Movie is wider than will fit; rescale
            newHeight = viewWidth / movieRatio;
            newWidth = newHeight * movieRatio;
            
            dstRect.right = newWidth;
            dstRect.bottom = newHeight;
        } else {
            // the Movie is taller than will fit; rescale
            newWidth = viewHeight * movieRatio;
            newHeight = newWidth / movieRatio;
            
            dstRect.right = newWidth;
            dstRect.bottom = newHeight;
        }
    }
    
    // enforce a minimum rectangle
    if (dstRect.right == 0)
        dstRect.right = viewWidth;
    
    if (dstRect.bottom == 0)
        dstRect.bottom = viewHeight;
*/
    
    err = QTNewGWorld(&threadData->gWorld, 32, &dstRect, NULL, NULL, 0);
    if (err != noErr) {
	fprintf(stderr, "QTNewGWorld(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
        goto bail;
    }
    
    LockPixels( GetGWorldPixMap( threadData->gWorld ) );

    SetGWorld( threadData->gWorld, NULL );
    EraseRect( &dstRect );
    
    SetMovieGWorld( movie, threadData->gWorld, NULL );
    err = GetMoviesError();
    if( err ) {
        fprintf(stderr, "SetMovieGWorld(\"%s\") returned %d\n", [aFileObject fileName], (int)err);
        goto bail;
    }

    SetMovieBox( movie, &dstRect );
    err = GetMoviesError();
    if( err ) {
        fprintf(stderr, "SetMovieBox(\"%s\") returned %d\n", [aFileObject fileName], (int)err);
        goto bail;
    }

    // draw a frame from the middle of the movie into the GWorld
    SetMovieTimeValue(movie, GetMovieDuration(movie)/2);
    MoviesTask(movie, 0);
    err = GetMoviesError();
    if (err == noErr) 
        err = GetMovieStatus(movie, NULL);
        
    if (err != noErr) {
        // if we get componentNotThreadSafeErr, then we need to retry importing on the main thread
        if (err == componentNotThreadSafeErr) {
            if (threadData->onlySafeComps == true) {
                // set a flag to indicate we need to retry on main thread, allowing non-safe components
                threadData->retry = true;
                goto bail;
            } else {
                // this should *really* never happen....
                fprintf(stderr, "MoviesTask(\"%s\") returned componentNotThreadSafeErr but with any components allowed!\n", [aFileObject fileName]);
                goto bail;
            }
        }
    
        // if we get codecAbortErr or we know we cancelled, AND if we are not the current image, dispose of the memory
        if ((err == codecAbortErr) || (threadData->cancelled)) {
            UInt32 doc = 0L;
            MyDocument *docCtrlr = nil;

            getWorkerRequestDoc(threadData->request, &doc);
            docCtrlr = (MyDocument *)doc;

            if (threadData != [docCtrlr currThreadData])
                [docCtrlr disposeThreadData:threadData];
        } else {
            fprintf(stderr, "MoviesTask(\"%s\") failed (%d)\n", [aFileObject fileName], (int)err);
        }
    }
    
bail:

    //////////
    //
    // clean up
    //
    //////////

    // we're done with the data reference
    if (drHandle != NULL) {
        DisposeHandle(drHandle);
        drHandle = NULL;
    }
    
    // we're done with the Movie data
    if (dhTag == USE_POINTER_DH && moviePointer != NULL)
        free(moviePointer);
    
    if (movieHandle != NULL) {
        DisposeHandle(movieHandle);
        movieHandle = NULL;
    }
    
    // we're done with the movie
    if (movie != 0) {
        DisposeMovie(movie);
        movie = 0;
    }
    
    // set the saved port and device
    SetGWorld(savedPort, savedGDevice);

    return err;
}

static OSErr movieProgressProc (Movie theMovie, short message, short whatOperation, Fixed percentDone, long refcon)
{
    ThreadData *threadData = (ThreadData *)refcon;

    if (threadData == nil)
        return paramErr;

    if (threadData->cancelled)
        return userCanceledErr;
    else
        return noErr;
}

//////////
//
// worker thread routines
//
//////////

// The workerActionRoutine is called on the worker thread to do the work.
// It should not return until the work is done or cancelled. Make sure you
// make only thread-safe calls in this routine!

void workerActionRoutine (void *refcon, WorkerRequestRef request)
{
    ThreadData *threadData = nil;

    if (request == NULL) return;
    
    getWorkerRequestThreadData(request, (void **)&threadData);
    if (threadData != NULL)
        importTheMovie(threadData);
}


// The workerCancelRoutine is called on the main thread to try to cancel work in progress.
// If possible, it should just set a flag that will cause the action routine to exit early.

void workerCancelRoutine (void *refcon, WorkerRequestRef request)
{
    ThreadData *threadData = nil;

    if (request == NULL) return;
    
    getWorkerRequestThreadData(request, (void **)&threadData);
    if (threadData != NULL)
        threadData->cancelled = true;
}


// The workerResponseMainThreadCallback is called on the main thread after the work is done or cancelled.
// It can call wasWorkerRequestCancelled to find out which. In our case, it should draw the result of the
// movie import operation. After the results of the work are used, it should release any memory 
// associated with the request.
// (This is a good place to release request-local memory because it's certain to be called for each request.)

void workerResponseMainThreadCallback (void *refcon, WorkerRequestRef request)
{
    UInt32 doc = 0L;
    MyDocument *docCtrlr = nil;
    ThreadData *threadData = nil;
    
    if (request == NULL) return;

    getWorkerRequestThreadData(request, (void **)&threadData);
    if (threadData == NULL)
        return;
    
    getWorkerRequestDoc(request, &doc);
    docCtrlr = (MyDocument *)doc;
    if (docCtrlr == NULL)
        return;

    if (wasWorkerRequestCancelled(request)) {
        // the request was cancelled
        
    } else {
        // the request completed, but we might still need to retry on the main thread
        if (threadData->retry) {
            // we need to retry the import on the main thread with any components
            if (threadData->gWorld != NULL)
                DisposeGWorld(threadData->gWorld);
            
            threadData->gWorld = NULL;
            threadData->retry = false;

            [[docCtrlr statusField] setStringValue:@"Retried import on main thread with any components!"];
            threadData->onlySafeComps = false;
            threadData->threadModelTag = USE_MAIN_THREAD;
            threadData->busy = true;

            importTheMovie(threadData);
            
            threadData->busy = false;
            [docCtrlr updateQDMovieView:threadData updateTime:YES];
        } else {
            // the request completed successfully; hand off the GWorld to the window for redrawing
            threadData->busy = false;
            [docCtrlr updateQDMovieView:threadData updateTime:YES];
            [[docCtrlr statusField] setStringValue:@""];
        }
        
    }
    
    releaseWorkerRequest(request);
    
    if (threadData->closeWhenSafe) {
        [docCtrlr close];
    }
}