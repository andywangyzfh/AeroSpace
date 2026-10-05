#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
extern AXError _AXUIElementGetWindow(AXUIElementRef, CGWindowID *);
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static CFMutableDictionaryRef generations;
static int generation(void) {
 const char *path=getenv("AEROSPACE_TEST_STALE_AX_FILE");
 return path && access(path,F_OK)==0 ? 1 : 0;
}
static void track(AXUIElementRef ax, int gen) {
 if (!ax) return;
 pthread_mutex_lock(&lock);
 if (!generations) generations=CFDictionaryCreateMutable(NULL,0,NULL,&kCFTypeDictionaryValueCallBacks);
 CFDictionarySetValue(generations,ax,gen ? kCFBooleanTrue : kCFBooleanFalse);
 pthread_mutex_unlock(&lock);
}
static bool stale(AXUIElementRef ax) {
 if (!generation()) return false;
 pthread_mutex_lock(&lock);
 const void *value=generations ? CFDictionaryGetValue(generations,ax) : NULL;
 bool result=value==kCFBooleanFalse;
 pthread_mutex_unlock(&lock);
 return result;
}
static AXUIElementRef replacementCreate(pid_t pid) {
 AXUIElementRef result=AXUIElementCreateApplication(pid);
 track(result,generation());return result;
}
static AXError replacementCopy(AXUIElementRef ax, CFStringRef attr, CFTypeRef *value) {
 const char *mode=getenv("AEROSPACE_TEST_AX_MODE");
 if(generation() && mode && strcmp(mode,"transient")==0) {
  if(value)*value=NULL;return kAXErrorCannotComplete;
 }
 pid_t pid=0; AXUIElementGetPid(ax,&pid);
 const char *target=getenv("AEROSPACE_TEST_AX_TARGET_PID");
 if(generation() && mode && strcmp(mode,"empty")==0 && target && pid==atoi(target) && CFEqual(attr,kAXWindowsAttribute)) {
  if(value)*value=CFArrayCreate(NULL,NULL,0,&kCFTypeArrayCallBacks);return kAXErrorSuccess;
 }
 if ((!mode || strcmp(mode,"stale")==0) && stale(ax)) { if(value)*value=NULL;return kAXErrorInvalidUIElement; }
 AXError error=AXUIElementCopyAttributeValue(ax,attr,value);
 if(error==kAXErrorSuccess && value && *value && CFEqual(attr,kAXWindowsAttribute) && CFGetTypeID(*value)==CFArrayGetTypeID()) {
  CFArrayRef windows=(CFArrayRef)*value;
  for(CFIndex i=0;i<CFArrayGetCount(windows);i++) track((AXUIElementRef)CFArrayGetValueAtIndex(windows,i),generation());
 }
 return error;
}
static AXError replacementWindow(AXUIElementRef ax,CGWindowID *id) {
 const char *mode=getenv("AEROSPACE_TEST_AX_MODE");
 pid_t pid=0;AXUIElementGetPid(ax,&pid);
 const char *target=getenv("AEROSPACE_TEST_AX_TARGET_PID");
 if(generation() && mode && strcmp(mode,"empty")==0 && target && pid==atoi(target)) {
  if(id)*id=0;return kAXErrorInvalidUIElement;
 }
 if((!mode || strcmp(mode,"stale")==0) && stale(ax)){if(id)*id=0;return kAXErrorInvalidUIElement;}
 return _AXUIElementGetWindow(ax,id);
}
// A read-only diagnostic must never compete with the original window manager's keys.
static OSStatus replacementRegister(UInt32 key,UInt32 modifiers,EventHotKeyID id,EventTargetRef target,OptionBits options,EventHotKeyRef *result) {
 if(result)*result=NULL;return eventHotKeyExistsErr;
}
#define INTERPOSE(replacement,original) \
 __attribute__((used)) static const struct {const void *replacement;const void *original;} interpose_##original \
 __attribute__((section("__DATA,__interpose"))) = {(const void *)(unsigned long)&replacement,(const void *)(unsigned long)&original};
INTERPOSE(replacementCreate,AXUIElementCreateApplication)
INTERPOSE(replacementCopy,AXUIElementCopyAttributeValue)
INTERPOSE(replacementWindow,_AXUIElementGetWindow)
INTERPOSE(replacementRegister,RegisterEventHotKey)
