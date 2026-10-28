#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>
#import <Contacts/Contacts.h>
#import <objc/runtime.h>
#include <unistd.h>
static unsigned guardAttempts;
static unsigned syntheticSharedRequests;
static id syntheticDirectory;
static id Shared(id object,SEL selector) {++syntheticSharedRequests;return syntheticDirectory;}
@interface SyntheticDirectory:NSObject
-(NSInteger)defaultNameOrdering;
@end
@implementation SyntheticDirectory
-(NSInteger)defaultNameOrdering {return kABFirstNameFirst;}
-(void)abGlobalAPILockInFile:(const char*)file line:(NSInteger)line {}
-(void)abGlobalAPIUnlockInFile:(const char*)file line:(NSInteger)line {}
-(ABPropertyType)typeOfProperty:(NSString*)property forTable:(id)table {
 if([@[kABFirstNameProperty,kABLastNameProperty,kABOrganizationProperty] containsObject:property]) return kABStringProperty;
 if([property isEqual:kABPersonFlags]) return kABIntegerProperty;
 if([@[kABPhoneProperty,kABEmailProperty] containsObject:property]) return kABMultiStringProperty;
 fprintf(stderr,"UNEXPECTED_PROPERTY_TYPE %s\n",property.UTF8String);_exit(75);
}
-(void)doesNotRecognizeSelector:(SEL)selector {fprintf(stderr,"UNEXPECTED_SYNTHETIC_DIRECTORY_SELECTOR %s\n",sel_getName(selector));_exit(74);}
@end
static id Reject(id object,SEL selector,...) { ++guardAttempts; fprintf(stderr,"UNEXPECTED_STORE_ENTRY %s %s\n",class_getName(object_getClass(object)),sel_getName(selector)); _exit(70); }
static void FenceAllocation(const char *name) {
 Class cls=objc_getClass(name); if (!cls) {fprintf(stderr,"Missing fenced class %s\n",name);_exit(71);}
 class_replaceMethod(object_getClass(cls),@selector(allocWithZone:),(IMP)Reject,"@@:^v");
}
@interface SyntheticPerson:NSObject
@property(copy) NSDictionary *values;
-(id)valueForProperty:(NSString*)property;
@end
@implementation SyntheticPerson
+(ABPropertyType)nts_TypeOfProperty:(NSString*)property withAddressBook:(id)book {return [book typeOfProperty:property forTable:nil];}
-(id)valueForProperty:(NSString*)property {return self.values[property];}
-(id)nts_ValueForProperty:(NSString*)property {return self.values[property];}
-(id)addressBook {return syntheticDirectory;}
-(id)nts_AddressBook {return syntheticDirectory;}
-(BOOL)isKindOfClass:(Class)cls {return cls==objc_getClass("ABPerson")||[super isKindOfClass:cls];}
@end
int main(void) { @autoreleasepool {
 Class book=objc_getClass("ABAddressBook");
 class_replaceMethod(object_getClass(book),@selector(addressBook),(IMP)Reject,"@@:");
 class_replaceMethod(object_getClass(book),@selector(sharedAddressBook),(IMP)Shared,"@@:");
 FenceAllocation("ABAddressBook"); FenceAllocation("ABRecord"); FenceAllocation("ABPerson"); FenceAllocation("CNContactStore");
 syntheticDirectory=[SyntheticDirectory new];
 ABMutableMultiValue *phones=[ABMutableMultiValue new]; [phones addValue:@"020123" withLabel:kABPhoneHomeLabel]; [phones addValue:@"+44123" withLabel:kABPhoneMobileLabel];
 ABMutableMultiValue *emails=[ABMutableMultiValue new]; [emails addValue:@"Anne@SIP.invalid" withLabel:@"sip"]; [emails addValue:@"Other@SIP.invalid" withLabel:@"sip"];
 NSArray *cases=@[
 @{ @"property":kABPhoneProperty,@"stored":phones,@"query":@"020",@"comparison":@(kABPrefixMatch),@"expected":@YES},
 @{ @"property":kABPhoneProperty,@"stored":phones,@"query":@"441",@"comparison":@(kABPrefixMatch),@"expected":@NO},
 @{ @"property":kABEmailProperty,@"stored":emails,@"query":@"other@",@"comparison":@(kABPrefixMatchCaseInsensitive),@"expected":@YES},
 @{ @"property":kABFirstNameProperty,@"stored":@"Anne",@"query":@"an",@"comparison":@(kABPrefixMatchCaseInsensitive),@"expected":@YES},
 @{ @"property":kABFirstNameProperty,@"stored":@"Anne",@"query":@"zo",@"comparison":@(kABPrefixMatchCaseInsensitive),@"expected":@NO},
 @{ @"property":kABLastNameProperty,@"stored":@"Smith",@"query":@"SMITH",@"comparison":@(kABEqualCaseInsensitive),@"expected":@YES},
 @{ @"property":kABLastNameProperty,@"stored":@"Smith",@"query":@"Smithy",@"comparison":@(kABEqualCaseInsensitive),@"expected":@NO},
 @{ @"property":kABPersonFlags,@"stored":@(kABShowAsPerson),@"query":@(kABShowAsPerson),@"comparison":@(kABBitsInBitFieldMatch),@"expected":@YES},
 @{ @"property":kABPersonFlags,@"stored":@(kABShowAsCompany),@"query":@(kABShowAsPerson),@"comparison":@(kABBitsInBitFieldMatch),@"expected":@NO}];
 NSMutableArray *results=[NSMutableArray array];
 @try { for(NSDictionary *item in cases) {
  SyntheticPerson *person=[SyntheticPerson new]; person.values=@{item[@"property"]:item[@"stored"]};
  ABSearchElement *predicate=[ABPerson searchElementForProperty:item[@"property"] label:nil key:nil value:item[@"query"] comparison:[item[@"comparison"] intValue]];
  BOOL match=[predicate matchesRecord:(ABRecord*)person];
  [results addObject:@{@"property":item[@"property"],@"query":item[@"query"],@"expected":item[@"expected"],@"actual":@(match)}];
  if(match!=[item[@"expected"] boolValue]) {fprintf(stderr,"TRUTH_TABLE_MISMATCH\n");return 72;}
 }} @catch(NSException *e){fprintf(stderr,"DETACHED_RECORD_REJECTED %s %s\n",e.name.UTF8String,e.reason.UTF8String);return 73;}
 NSDictionary *output=@{@"qualified":@YES,@"storeEntryAttempts":@(guardAttempts),@"syntheticSharedRequests":@(syntheticSharedRequests),@"results":results,@"recordConstruction":@"Detached NSObject shape; ABRecord/ABPerson allocation fenced"};
 NSData *data=[NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:nil];
 fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
 }return 0;}
