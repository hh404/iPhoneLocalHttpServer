#include <netdb.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#import "AsyncSocket.h"
#import "HTTPServer.h"
#import "HTTPConnection.h"


@implementation HTTPServer

@synthesize fileResourceDelegate;

/**
 * Standard Constructor.
 * Instantiates an HTTP server, but does not start it.
**/
- (id)init
{
	if(self = [super init])
	{
		// Initialize underlying asynchronous tcp/ip socket
		asyncSocket = [[AsyncSocket alloc] initWithDelegate:self];
		
		// Use default connection class of HTTPConnection
		connectionClass = [HTTPConnection self];
		
		// Configure default values for bonjour service
		
		// Use a default port of 0
		// This will allow the kernel to automatically pick an open port for us
		port = 0;
		
		// Bonjour domain. Use the local domain by default
		domain = @"local.";
		
		// If using an empty string ("") for the service name when registering,
		// the system will automatically use the "Computer Name".
		// Passing in an empty string will also handle name conflicts
		// by automatically appending a digit to the end of the name.
		name = @"";
		
		// Initialize an array to hold all the HTTP connections
		connections = [[NSMutableArray alloc] init];
		
		// And register for notifications of closed connections
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(connectionDidDie:)
													 name:HTTPConnectionDidDieNotification
												   object:nil];
	}
	return self;
}

/**
 * Standard Deconstructor.
 * Stops the server, and clients, and releases any resources connected with this instance.
**/
- (void)dealloc
{
	// Remove notification observer
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Stop the server if it's running
	[self stop];
	
	// Release all instance variables
	[documentRoot release];
	[netService release];
    [domain release];
    [name release];
    [type release];
	[txtRecordDictionary release];
	[asyncSocket release];
	[connections release];
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server Configuration:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the delegate connected with this instance.
**/
- (id)delegate
{
	return delegate;
}

/**
 * Sets the delegate connected with this instance.
**/
- (void)setDelegate:(id)newDelegate
{
	delegate = newDelegate;
}

/**
 * The document root is filesystem root for the webserver.
 * Thus requests for /index.html will be referencing the index.html file within the document root directory.
 * All file requests are relative to this document root.
**/
- (NSString *)documentRoot {
    return documentRoot;
}

- (void)setDocumentRoot:(NSString *)value
{
    if(![documentRoot isEqual:value])
	{
        [documentRoot release];
        documentRoot = [value copy];
    }
}

/**
 * The connection class is the class that will be used to handle connections.
 * That is, when a new connection is created, an instance of this class will be intialized.
 * The default connection class is HTTPConnection.
 * If you use a different connection class, it is assumed that the class extends HTTPConnection
**/
- (Class)connectionClass {
    return connectionClass;
}
- (void)setConnectionClass:(Class)value
{
    connectionClass = value;
}

/**
 * Domain on which to broadcast this service via Bonjour.
 * The default domain is @"local".
**/
- (NSString *)domain {
    return domain;
}
- (void)setDomain:(NSString *)value
{
	if(![domain isEqualToString:value])
	{
		[domain release];
        domain = [value copy];
    }
}

/**
 * The type of service to publish via Bonjour.
 * No type is set by default, and one must be set in order for the service to be published.
**/
- (NSString *)type {
    return type;
}
- (void)setType:(NSString *)value
{
	if(![type isEqualToString:value])
	{
		[type release];
		type = [value copy];
    }
}

/**
 * The name to use for this service via Bonjour.
 * The default name is the host name of the computer.
**/
- (NSString *)name {
    return name;
}
- (void)setName:(NSString *)value
{
	if(![name isEqualToString:value])
	{
        [name release];
        name = [value copy];
    }
}

/**
 * The port to listen for connections on.
 * By default this port is initially set to zero, which allows the kernel to pick an available port for us.
 * After the HTTP server has started, the port being used may be obtained by this method.
**/
- (UInt16)port {
    return port;
}
- (void)setPort:(UInt16)value {
    port = value;
}

/**
 * The extra data to use for this service via Bonjour.
**/
- (NSDictionary *)TXTRecordDictionary {
	return txtRecordDictionary;
}
- (void)setTXTRecordDictionary:(NSDictionary *)value
{
	if(![txtRecordDictionary isEqualToDictionary:value])
	{
		[txtRecordDictionary release];
		txtRecordDictionary = [value copy];
		
		// And update the txtRecord of the netService if it has already been published
		if(netService)
		{
			[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txtRecordDictionary]];
		}
	}
}

- (NSString*)hostName
{
	struct ifaddrs *addrs;
	const struct ifaddrs *cursor;
	int error;
	error = getifaddrs(&addrs);
	NSString *hostname = nil;
	
	if (error)
	{
		NSLog(@"%@", gai_strerror(error));
	}
	for (cursor = addrs; cursor; cursor = cursor->ifa_next)
	{
        if (cursor->ifa_addr->sa_family == AF_INET && (cursor->ifa_flags & IFF_LOOPBACK) == 0)
		{
            NSString *ifa_name = [NSString stringWithUTF8String:cursor->ifa_name];
			if([@"en0" isEqualToString:ifa_name] ||
               [@"en1" isEqualToString:ifa_name])
			{
				hostname = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)cursor->ifa_addr)->sin_addr)];
				NSLog(@"hostname:%@",hostname);
				break;
			}
		}
	}
	freeifaddrs(addrs);
	return hostname;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server Control:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)start:(NSError **)error
{
	BOOL success = [asyncSocket acceptOnPort:port error:error];
	
	if(success)
	{
		// Update our port number
		[self setPort:[asyncSocket localPort]];
		
		// Output console message for debugging purposes
		NSLog(@"Started HTTP server on port %hu", port);
		
		// We can only publish our bonjour service if a type has been set
		if(type != nil)
		{
			// Create the NSNetService with our basic parameters
			netService = [[NSNetService alloc] initWithDomain:domain type:type name:name port:port];
			
			[netService setDelegate:self];
			[netService publish];
			
			// Do not set the txtRecordDictionary prior to publishing!!!
			// This will cause the OS to crash!!!
			
			// Set the txtRecordDictionary if we have one
			if(txtRecordDictionary != nil)
			{
				[netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txtRecordDictionary]];
			}
		}
	}
	else
	{
		NSLog(@"Failed to start HTTP Server: %@", error);
	}
	
	return success;
}

- (BOOL)stop
{
	// First stop publishing the service via bonjour
	if(netService)
	{
		[netService stop];
		[netService release];
		netService = nil;
	}
	
	// Now stop the asynchronouse tcp server
	// This will prevent it from accepting any more connections
	[asyncSocket disconnect];
	
	// Now stop all HTTP connections the server owns
	[connections removeAllObjects];
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server Status:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the number of clients that are currently connected to the server.
**/
- (int)numberOfHTTPConnections
{
	return [connections count];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncSocket Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket
{
	id newConnection = [[connectionClass alloc] initWithAsyncSocket:newSocket forServer:self];
	[connections addObject:newConnection];
	[newConnection release];
}

/**
 * This method is automatically called when a notification of type HTTPConnectionDidDieNotification is posted.
 * It allows us to remove the connection from our array.
**/
- (void)connectionDidDie:(NSNotification *)notification
{
	[connections removeObject:[notification object]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Bonjour Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when our bonjour service has been successfully published.
 * This method does nothing but output a log message telling us about the published service.
**/
- (void)netServiceDidPublish:(NSNetService *)ns
{
	// Override me to do something here...
	
	NSLog(@"Bonjour Service Published: domain(%@) type(%@) name(%@)", [ns domain], [ns type], [ns name]);
}

/**
 * Called if our bonjour service failed to publish itself.
 * This method does nothing but output a log message telling us about the published service.
**/
- (void)netService:(NSNetService *)ns didNotPublish:(NSDictionary *)errorDict
{
	// Override me to do something here...
	
	NSLog(@"Failed to Publish Service: domain(%@) type(%@) name(%@)", [ns domain], [ns type], [ns name]);
	NSLog(@"Error Dict: %@", errorDict);
}

#pragma mark built-in web service

// setup the docroot for the http server
- (void)setupBuiltInDocroot
{
	NSString* docroot =[NSString stringWithFormat:@"%@/tmp/docroot", NSHomeDirectory()];
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error;
	if(![manager removeItemAtPath:docroot error:&error])
	{
		NSLog(@"Can not remove old docroot: %@", error);
	}
	NSString *path = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], @"docroot"];
	[manager createSymbolicLinkAtPath:docroot withDestinationPath:path error:&error];
	[self setDocumentRoot:docroot];
}

@end
