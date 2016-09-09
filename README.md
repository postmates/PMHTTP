# PMHTTP

[![Version](https://img.shields.io/badge/version-v1.0.0-blue.svg)](https://github.com/postmates/PMHTTP/releases/latest)
![Platforms](https://img.shields.io/badge/platforms-ios%20%7C%20osx%20%7C%20watchos%20%7C%20tvos-lightgrey.svg)
![Languages](https://img.shields.io/badge/languages-swift%20%7C%20objc-orange.svg)
![License](https://img.shields.io/badge/license-MIT%2FApache-blue.svg)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)][Carthage]
[![CocoaPods](https://img.shields.io/cocoapods/v/PMHTTP.svg)](http://cocoadocs.org/docsets/PMHTTP)

[Carthage]: https://github.com/carthage/carthage

PMHTTP is an HTTP framework built around `NSURLSession` and designed for Swift while retaining Obj-C compatibility.

We think `NSURLSession` is great. But it was designed for Obj-C and it doesn't handle anything beyond the networking
aspect of a request. This means no handling of JSON, and it doesn't even provide `multipart/form-data` uploads. PMHTTP
leaves the networking to `NSURLSession` and provides everything else. Features include:

* Requests can define parse handlers that execute asynchronously separately from the completion block, and
  requests can be canceled while parsing and the completion block sees the correct result.
* First-class JSON support using [PMJSON][].
* Structured results and high-quality errors; no more treating `NSURLErrorCancelled` as a network error.
* Strongly-typed results.
* Thread safety.
* [Intelligent cache handling](#cache-handling).
* Requests can be defined once (including a parse handler) and executed many times, just like `NSURLRequest`.
* Configurable automatic retrying of failed requests when safe.
* A configurable base URL, allowing for switching between staging and production with no change to the code
  constructing the requests.
* Support for Basic authentication.
* `multipart/form-data`, `application/x-www-form-urlencoded`, and JSON upload support.
* Built-in request mocking support without using method swizzling.
* Nothing uses the main thread, not even completion blocks, unless you explicitly ask it to.

PMHTTP was designed specifically for the HTTP functionality that [Postmates][] needs. This means first-class REST
support with a focus on JSON. But there's some functionality it doesn't handle (such as TLS pinning) which we
may get around to doing at some point ([see issues](https://github.com/postmates/PMHTTP/labels/TODO)).
Pull requests are welcome.

[Postmates]: https://postmates.com
[PMJSON]: https://github.com/postmates/PMJSON "postmates/PMJSON on GitHub"

### Table of Contents

* [Usage](#usage)
  * [Setup](#setup)
* [Detailed Design](#detailed-design)
  * [`HTTPManager`](#httpmanager)
  * [Environments](#environments)
  * [Requests](#requests)
  * [Network Tasks](#network-tasks)
  * [Network Activity Indicator](#network-activity-indicator)
  * [Automatic Retrying of Failed Requests](#automatic-retrying-of-failed-requests)
  * [Cache Handling](#cache-handling)
  * [Mocking](#mocking)
  * [Testing](#testing)
* [Requirements](#requirements)
* [Installation](#installation)
* [License](#license)
* [Version History](#version-history)

## Usage

A typical GET request looks like:

```swift
// https://api.example.com/v1/search?query=%s
let task = HTTP.request(GET: "search", parameters: ["query": "cute cats"])
    .parseAsJSON()
    .performRequest(withCompletionQueue: .main) { task, result in
        switch result {
        case let .Success(response, json):
            // Do something with the parsed JSON.
        case let .Error(response, error):
            // Handle the error. This includes both network errors and JSON parse errors.
        case .Canceled:
            // The task was canceled. Ignore or handle as appropriate.
        }
}
// task can be canceled and can be queried for its state
// and this can be done from any thread.
```

A POST request might look like:

```swift
// https://api.example.com/v1/submit_cat
let task = HTTP.request(POST: "submit_cat", parameters: ["name": "Fluffles", "color": "tabby"])
    .parseAsJSON(with: { response, json in
        return try SubmitCatResponse(json: json)
    })
    .performRequest(withCompletionQueue: .main) { task, result in
        switch result {
        case let .Success(response, value):
            // value is a SubmitCatResponse
        case let .Error(response, error):
            // Handle the error. This could be a network error, a JSON parse error, or
            // any error thrown by SubmitCatResponse.init(json:)
        case .Canceled:
            // The task was canceled.
        }    
}
```

A `multipart/form-data` upload might look like:

```swift
// https://api.example.com/v1/submit_cat with photo
let req = HTTP.request(POST: "submit_cat", parameters: ["name": "Fluffles", "color": "tabby"])!
// We could add the image synchronously, but it's better to be asynchronous.
req.addMultipartBody { upload in
    // This block executes on a background queue.
    if let data = UIImageJPEGRepresentation(catPhoto, 0.9) {
        upload.addMultipart(data: data, withName: "photo", mimeType: "image/jpeg")
    }
}
let task = req.parseAsJSON(with: { try SubmitCatResponse(json: $1) })
    .performRequest(withCompletionQueue: .main) { task, result in
        // ...
}
```

#### Setup

You can modify the properties of the global `HTTPManager` object at any time, but to make setup
easier, if your `UIApplicationDelegate` or `NSApplicationDelegate` object conforms to the
`HTTPManagerConfigurable` protocol it will be asked to configure the `HTTPManager` the first time
the `HTTP` global variable is accessed. This might look like:

```swift
extension AppDelegate: HTTPManagerConfigurable {
    public func configure(httpManager: HTTPManager) {
        httpManager.environment = HTTPManager.Environment(string: /* ... */)
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        config.timeoutIntervalForRequest = 10
        // PMHTTP defines a default User-Agent but we can supply our own
        config.HTTPAdditionalHeaders = ["User-Agent": myUserAgent]
        httpManager.sessionConfiguration = config
        if let (username, apiKey) = getAPICredentials() {
            httpManager.defaultCredential = NSURLCredential(user: username, password: apiKey, persistence: .ForSession)
        }
        httpManager.defaultRetryBehavior = HTTPManagerRetryBehavior.retryNetworkFailureOrServiceUnavailable(withStrategy: .retryTwiceWithDefaultDelay)
    }
}
```

## Detailed Design

PMHTTP was designed with 6 goals in mind:

* Be as Swift-like as possible while retaining Obj-C compatibility.
* Speed, with an emphasis on being concurrent by default.
* Thread safety wherever it makes sense.
* Explicitness and type safety. For example, PMHTTP doesn't auto-detect the return type but requires
  you to declare what response format you're expecting.
* Correctness, which includes avoiding surprising behavior.
* Make it easy to add new functionality, such as auto-retrying and network mocking.

#### `HTTPManager`

The overall manager class for PMHTTP is `HTTPManager`. This is the class that allows you to
configure various global properties and to create new requests. Multiple managers can be created if
desired, but a single global instance is provided under the global property `HTTP` (for Obj-C this
is `[HTTPManager defaultManager]`). All properties and methods on this class are completely
thread-safe.

Configuration of the shared `HTTP` instance can be done by adopting the `HTTPManagerConfigurable`
protocol on your app delegate. This protocol provides a method that can be used to configure the
shared `HTTPManager` object the first time the `HTTP` property is accessed. This design allows you
to ensure the shared instance is properly configured prior to first use even if it's used prior to
the normal entry point for your application (e.g. inside some class's `+load` method). Do note,
however, that this method will be executed on whatever thread is first accessing the `HTTP`
property, and so it should be safe to run from any thread.

**Important:** The shared `HTTP` instance is a convenience intended for use by the application. If
you're writing a shared component (e.g. a framework) that uses PMHTTP, you need to carefully
consider whether using `HTTP` is appropriate or whether you should be using a separate instance of
`HTTPManager`. The use of `HTTP` is only appropriate if you want to automatically adopt any
configuration the application provides (including environment and default credential).

#### Environments

`HTTPManager` has a property `environment` of type `HTTPManager.Environment`. An environment is a
simple wrapper around an `NSURL` and represents the base URL that requests should use if the request
is not made with an absolute URL. You may wish to create your own extension that looks something
like:

```swift
extension HTTPManager.Environment {
    // @nonobjc works around "a declaration cannot be both 'final' and 'dynamic'" error.
    @nonobjc static let Production = HTTPManager.Environment(baseURL: productionURL)
    @nonobjc static let Staging = HTTPManager.Environment(baseURL: stagingURL)
}
```

The environment is also used to determine whether a given request should adopt the default
credential configured on the `HTTPManager`. Only requests for URLs that are prefixed by the
environment will use the default credential. Requests for any other URL will have no credential by
default, though a credential can always be added to any request.

#### Requests

Requests in PMHTTP are objects. In a pure-Swift world they'd be structs/protocols, but they're
objects in order to be compatible with Obj-C. Unlike `NSURLRequest`, PMHTTP requests are inherently
mutable (so they're like `NSMutableURLRequest`). They're also the only public component of PMHTTP
that is not thread-safe, though it is safe to access a request concurrently as long as no thread is
mutating the request (which is to say, reading values from the request does not perform any internal
mutation).

Requests are split into a hierarchy of classes:

* `HTTPManagerRequest` - The root request type, which contains parameters and methods that are
  applicable to all requests.
  * `HTTPManagerNetworkRequest` - The parent class for all requests that do not have a parse
    handler.
    * `HTTPManagerDataRequest` - The class for GET requests that do not have a parse handler.
    * `HTTPManagerActionRequest` - The class or parent class for POST/PUT/PATCH/DELETE requests that
      do not have a parse handler.
      * `HTTPManagerUploadFormRequest` - The class for POST/PUT/PATCH requests without a parse
        handler that have a body of either `application/x-www-form-urlencoded` or
        `multipart/form-data`.
      * `HTTPManagerUploadDataRequest` - The class for POST/PUT/PATCH requests without a parse
        handler that have a body consisting of an arbitrary `NSData`.
      * `HTTPManagerUploadJSONRequest` - The class for POST/PUT/PATCH requests without a parse
        handler that have a body consisting of a JSON value.
  * `HTTPManagerParseRequest<T>` - The class for any request that has a parse handler.
  * `HTTPManagerObjectParseRequest` - The class for requests made from Obj-C that have a parse
    handler. Similar to `HTTPManagerParseRequest<T>` but the parse result is always an `AnyObject?`.

This hierarchy means that every class can provide only the methods/properties that make sense for
all requests of that class type. For example, only `HTTPManagerUploadFormRequest` requests allow for
adding multipart bodies.

Requests include properties for configuring virtually every aspect of the network request. A few
properties inherit default values from the `HTTPManager` object, though these default values can
always be overridden. One property of note is `userInitiated`, which is a boolean property that
should be set if the request represents some action the user is waiting on. Setting this property to
`true` causes the underlying network task to be executed at a high priority and causes all
background queue processing to occur using `QOS_CLASS_USER_INITIATED`.

`HTTPManagerUploadFormRequest` provides support for creating `multipart/form-data` requests, which
can be used for uploading files/images. These requests are implemented in a streaming fashion, so
e.g. memory-mapped `NSData` objects won't be copied into a contiguous buffer, thus allowing you to
upload files without concerns about memory use.

`HTTPManagerRequest` conforms to `NSCopying` so copies can be made of any request if necessary.
Furthermore, when attaching a parse handler to a request (and therefore converting it into an
`HTTPManagerParseRequest<T>`) the original request data is copied so subsequent mutations to the
original request do not affect the parse request, and when a request is executed the request data is
copied so the request can be immediately mutated without affecting the executing network task.

Requests are also designed such that they can be easily created and executed using a
functional-style chain, as demonstrated by the [Usage](#usage) section above.

Parse requests always execute their parse handler on a background queue, with no option to run on a
given queue (or the main queue). This constraint exists both to encourage parsing in the background,
and for simplicity, as parsing on the main queue can always be accomplished by skipping the parse
handler and parsing in the completion block instead.

Request completion blocks are similarly executed on a background queue by default (for requests with
a parse handler, this will be the same queue that the parse handler executed on), although here a
specific queue can be provided where the completion block should run, such as the main queue.

#### Network Tasks

Executing a request returns a value of type `HTTPManagerTask`. This class is the PMHTTP equivalent
of `NSURLSessionTask` and is completely thread-safe. It provides properties for inspecting the
current state of the request, including for accessing the underlying `NSURLSessionTask`, and it
provides a `cancel()` method for canceling the request. Unlike `-[NSURLSessionTask cancel]`,
`HTTPManagerTask.cancel()` can be used to cancel a request while the parse handler is executing, not
just canceling the networking portion. PMHTTP guarantees that if you execute
`HTTPManagerTask.cancel()` from the same queue that the completion block is targeting, prior to the
completion block itself executing, the completion block will always be given a result of `.Canceled`
even if it had already finished parsing before `cancel()` was invoked. This means that if you target
the main queue for your completion block, you can be confident that a canceled task will never
behave as though it succeeded or failed.

Like `NSURLSessionTask`, `HTTPManagerTask` supports key-value observing (although, like
`NSURLSessionTask`, the KVO messages will occur on some background queue).

In the absence of automatic retrying, the `networkTask` property value will never change during the
lifetime of the task. If automatic retrying has been configured, `networkTask` will change if the
request is retried, and will broadcast any relevant key-value observing messages.

#### Network Activity Indicator

PMHTTP provides a callback you can use to implement support for the global network activity
indicator. Each request object has a property `affectsNetworkActivityIndicator` (which defaults to
`true`) that controls whether any tasks created from the request affect the callback. The callback
itself is configured by assigning a block to `HTTPManager.networkActivityHandler`. This block is run
on the main thread whenever the number of active tasks has changed. In order to display the global
network activity indicator you can configure this like so:

```swift
HTTPManager.networkActivityHandler = { active in
    UIApplication.sharedApplication().networkActivityIndicatorVisible = active > 0
}
```

#### Automatic Retrying of Failed Requests

PMHTTP includes support for automatically retrying failed requests according to a configurable
policy. The default retry policy can be configured with `HTTPManager.defaultRetryBehavior`, which
can be overridden on individual requests with `HTTPManagerRequest.retryBehavior`. A few common retry
policies are provided as convenience methods on `HTTPManagerRetryBehavior`, but any custom policy is
supported as well. The convenience policies implement intelligent handling of the various
`NSURLErrorDomain` errors, such as not retrying when encountering a non-transient error (such as
`NSURLErrorAppTransportSecurityRequiresSecureConnection`), or retrying non-idempotent requests if
the error indicates the server never received the request (e.g. `NSURLErrorCannotConnectToHost`). By
default, retrying is disabled.

#### Cache Handling

PMHTTP implements intelligent cache handling for JSON responses. The HTTP standard allows user
agents to cache responses at their discretion when the response does not include caching headers.
However, this behavior is inappropriate for most REST API requests, and `NSURLSession` does not
document its caching strategy for such responses. To handle this case, PMHTTP inspects JSON
responses for appropriate caching headers and explicitly prevents responses from being cached
if they do not include the appropriate cache directives. By default this behavior is only applied
to requests created with `.parseAsJSON()` or `.parseAsJSON(with:)`, although it can be
overridden on a per-request basis (see `HTTPManagerRequest.defaultResponseCacheStoragePolicy`).
Notably, requests created with `.parse(with:)` do not use this cache strategy as it would
interfere with caching image requests.

#### Mocking

PMHTTP has built-in support for mocking network requests. This is done without swizzling (so it's
safe to mock requests even in App Store builds), and it's done in a fashion that still creates a
valid `NSURLSessionTask` (so any code that inspects `HTTPManagerTask.networkTask` will function as
expected). Mocks can be registered on the `HTTPManager` as a whole, and individual requests can be
independently mocked (so you can control whether a request is mocked based on more than just the URL
in question).

#### Testing

PMHTTP itself has a comprehensive test suite, covering just about everything in the Swift API (the
Obj-C–specific API is not currently tested, see
[issue #7](https://github.com/postmates/PMHTTP/issues/7)). The tests are run against a custom
HTTP/1.1 server implemented in the test bundle that listens on the loopback interface. This allows
for testing all the functionality without any dependencies on external services and ensures the
tests are very fast. The HTTP/1.1 server currently relies on [CocoaAsyncSocket][], which can be
installed with `carthage bootstrap`. This dependency is not exposed to clients of PMHTTP as it's
only used by the test suite.

[CocoaAsyncSocket]: https://github.com/robbiehanson/CocoaAsyncSocket

The HTTP/1.1 server implements just about everything that I thought was useful. It has a few minor
dependencies on PMHTTP itself (most notably, it uses `HTTPManagerRequest.HTTPHeaders` instead of
reimplementing the functionality), but beyond that, it could actually be pulled out and used
anywhere else that an HTTP/1.1 server is required. However, as this server was written for the
purposes of testing and not production use, it does not have any built-in mitigation of DOS attacks
beyond rejecting uploads greater than 5MiB (for example, it does not impose any limit on headers,
which are kept in memory, and it does not have any sort of timeout on connection duration). It also
does not have any tests itself, beyond the fact that it behaves as expected when used in the PMHTTP
test suite.

## Requirements

Requires a minimum of iOS 8, macOS 10.10, watchOS 2.0, or tvOS 9.0.

## Installation

After installation with any mechanism, you can use this by adding `import PMHTTP` to your code.

### Carthage

To install using [Carthage][], add the following to your Cartfile:

```
github "postmates/PMHTTP" ~> 1.0
```

This release supports Swift 3.0. For Swift 2.3 you can use

```
github "postmates/PMHTTP" "v0.9.2"
```

### CocoaPods
To install using [CocoaPods](https://cocoapods.org), add the following to your Podfile:

```
pod "PMHTTP", "~> 1.0"
```

## License

Licensed under either of
 * Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
   http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   http://opensource.org/licenses/MIT) at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you shall be dual licensed as above, without any additional terms or conditions.

## Version History

#### v1.0.0 (2016-09-09)

* Support Swift 3.0.

#### v0.9.2 (2016-09-09)

* Support Swift 2.3.

#### v0.9.1 (2016-08-17)

* Rename Source folder to Sources.
* CocoaPods support.

#### v0.9 (2016-08-05)

Initial release.
