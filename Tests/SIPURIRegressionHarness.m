#import <Foundation/Foundation.h>
@import UseCases;
#import "AKSIPURI.h"
#import "AKSIPURIParser.h"
#import <pjsua-lib/pjsua.h>

// Private parser initialisation from the exact vendored 2.17 archive.
// No endpoint, transports, accounts, media, AppController or defaults are created.
extern void init_sip_parser(void);
extern void deinit_sip_parser(void);
static pj_caching_pool factory;
PJ_DEF(pj_pool_t *) pjsua_pool_create(const char *name, pj_size_t initial, pj_size_t increment) {
    return pj_pool_create(&factory.factory, name, initial, increment, NULL);
}
@interface URIProbeAgent : NSObject
@end
@implementation URIProbeAgent
- (BOOL)isStarted { return YES; }
@end
@interface AccountControllerToAccountAdapter : NSObject
- (instancetype)initWithController:(id)controller;
- (void)makeCallTo:(URI *)uri label:(NSString *)label;
@end
@interface URIProbeController : NSObject
@property(nonatomic, strong) AKSIPURI *captured;
@end
@implementation URIProbeController
- (void)makeCallToURI:(AKSIPURI *)uri phoneLabel:(NSString *)label { self.captured = uri; }
@end
@interface URI (NativeAdapterProbe)
- (instancetype)initWithURI:(AKSIPURI *)uri;
- (instancetype)initWithURI:(AKSIPURI *)uri transport:(Transport)transport;
@end
static NSDictionary *nativeReference(NSString *input) {
    pj_pool_t *pool = pjsua_pool_create("safe-uri-reference", 1024, 1024);
    char *bytes = strdup(input.UTF8String);
    pjsip_name_addr *name = (pjsip_name_addr *)pjsip_parse_uri(pool, bytes, strlen(bytes), PJSIP_PARSE_URI_AS_NAMEADDR);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{@"parsed": @(name != NULL)}];
    if (name && PJSIP_URI_SCHEME_IS_SIP(name)) {
        pjsip_sip_uri *sip = (pjsip_sip_uri *)pjsip_uri_get_uri(name);
        result[@"host"] = [[NSString alloc] initWithBytes:sip->host.ptr length:sip->host.slen encoding:NSUTF8StringEncoding] ?: @"";
        result[@"port"] = @(sip->port);
    }
    free(bytes);
    pj_pool_release(pool);
    return result;
}
int main(void) {
    @autoreleasepool {
        if (pj_init() || pjlib_util_init()) return 2;
        pj_log_set_level(0);
        pj_caching_pool_init(&factory, NULL, 0);
        init_sip_parser();
        URIProbeAgent *agent = [URIProbeAgent new];
        AKSIPURIParser *parser = [[AKSIPURIParser alloc] initWithUserAgent:(id)agent];
        NSMutableArray *results = [NSMutableArray array];
        NSArray *inputs = @[@"\"Rene Example\" <sip:alice@example.invalid>", @"\"René Example\" <sip:alice@example.invalid>", @"\"私用\" <sip:alice@example.invalid>", @"sip:alice@example.invalid:5070", @"sip:alice@[2001:db8::1]:5070", @"sip:alice@example.invalid;transport=tcp"];
        for (NSString *input in inputs) {
            AKSIPURI *value = [parser SIPURIFromString:input];
            URI *swiftURI = [[URI alloc] initWithString:input];
            AKSIPURI *typed = [[AKSIPURI alloc] initWithString:input];
            URI *callAdapter = value ? [[URI alloc] initWithURI:value transport:TransportTCP] : nil;
            URI *historyAdapter = value ? [[URI alloc] initWithURI:value] : nil;
            [results addObject:@{@"input": input, @"utf16Units": @(input.length), @"utf8Bytes": @([input lengthOfBytesUsingEncoding:NSUTF8StringEncoding]), @"reference": nativeReference(input), @"productionNativeParsed": @(value != nil), @"productionNativeHost": value.host ?: [NSNull null], @"productionNativePort": @(value.port), @"productionNativeString": value.description ?: [NSNull null], @"swiftParsedString": swiftURI.stringValue ?: [NSNull null], @"swiftReparsed": swiftURI ? nativeReference(swiftURI.stringValue) : [NSNull null], @"typedAKString": typed.description ?: [NSNull null], @"callAdapterString": callAdapter.stringValue ?: [NSNull null], @"historyAdapterString": historyAdapter.stringValue ?: [NSNull null]}];
        }
        AKSIPURI *constructed = [[AKSIPURI alloc] initWithUser:@"alice" host:@"example.invalid" displayName:@"" port:5070];
        [results addObject:@{@"constructedPortInput": @5070, @"port": @(constructed.port), @"copyPort": @(((AKSIPURI *)constructed.copy).port), @"string": constructed.description}];
        URIProbeController *controller = [URIProbeController new];
        AccountControllerToAccountAdapter *adapter = [[AccountControllerToAccountAdapter alloc] initWithController:controller];
        URI *structured = [[URI alloc] initWithUser:@"alice" address:[[ServiceAddress alloc] initWithHost:@"example.invalid" port:@"5070"] displayName:@"" transport:TransportUDP];
        [adapter makeCallTo:structured label:@"synthetic"];
        [results addObject:@{@"historyMakeAdapterInput": structured.stringValue, @"output": controller.captured.description, @"outputPort": @(controller.captured.port)}];
        NSData *json = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        deinit_sip_parser(); pj_caching_pool_destroy(&factory); pj_shutdown();
    }
    return 0;
}
