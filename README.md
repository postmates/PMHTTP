# PMHTTP

[![Version](https://img.shields.io/badge/version-v4.4.3-blue.svg)](https://github.com/postmates/PMHTTP/releases/latest)
![Platforms](https://img.shields.io/badge/platforms-ios%20%7C%20osx%20%7C%20watchos%20%7C%20tvos-lightgrey.svg)
![Languages](https://img.shields.io/badge/languages-swift%20%7C%20objc-orange.svg)
![License](https://img.shields.io/badge/license-MIT%2FApache-blue.svg)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)][Carthage]
[![CocoaPods](https://img.shields.io/cocoapods/v/PMHTTP.svg)](http://cocoadocs.org/docsets/PMHTTP)

[Carthage]: https://github.com/carthage/carthage

PMHTTP is an HTTP framework built around `URLSession` and designed for Swift while retaining Obj-C compatibility.

We think `URLSession` is great. But it was designed for Obj-C and it doesn't handle anything beyond the networking
aspect of a request. This means no handling of JSON, and it doesn't even provide `multipart/form-data` uploads. PMHTTP
leaves the networking to `URLSession` and provides everything else. Features include:

* Requests can define parse handlers that execute asynchronously separately from the completion block, and
  requests can be canceled while parsing and the completion block sees the correct result.
* First-class JSON support using [PMJSON][].
* Structured results and high-quality errors; no more treating `URLError.cancelled` as a network error.
* Strongly-typed results.
* Thread safety.
* [Intelligent cache handling](#cache-handling).
* Requests can be defined once (including a parse handler) and executed many times, just like `URLRequest`.
* Configurable automatic retrying of failed requests when safe.
* A configurable base URL, allowing for switching between staging and production with no change to the code
  constructing the requests.
* Support for Basic authentication.
* `multipart/form-data`, `application/x-www-form-urlencoded`, and JSON upload support.
* Built-in request mocking support without using method swizzling.
* Nothing uses the main thread, not even completion blocks, unless you explicitly ask it to.

PMHTTP was designed specifically for the HTTP functionality that [Postmates][] needs. This means
first-class REST support with a focus on JSON. But there's some functionality it doesn't handle
which we may get around to doing at some point ([see issues][]). Pull requests are welcome.

[Postmates]: https://postmates.com
[PMJSON]: https://github.com/postmates/PMJSON "postmates/PMJSON on GitHub"
[see issues]: https://github.com/postmates/PMHTTP/labels/TODO

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
    .parseAsJSON(using: { (response, json) in
        return try JSON.map(json.getArray(), Cat.init(json:))
    })
    .performRequest(withCompletionQueue: .main) { task, result in
        switch result {
        case let .success(response, cats):
            // Do something with the Cats.
        case let .error(response, error):
            // Handle the error. This includes network errors, JSON parse errors,
            // and any error thrown by Cat.init(json:).
        case .canceled:
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
    .parseAsJSON(using: { result in
        // POST parse blocks take a single `result` argument because 204 No Content is a valid
        // response. The `result` enum vends an optional `value` property, and has a
        // `getValue()` method that throws an error if the response was 204 No Content.
        return try SubmitCatResponse(json: result.getValue())
    })
    .performRequest(withCompletionQueue: .main) { task, result in
        switch result {
        case let .success(response, value):
            // value is a SubmitCatResponse.
        case let .error(response, error):
            // Handle the error. This could be a network error, a JSON parse error, or
            // any error thrown by SubmitCatResponse.init(json:).
        case .canceled:
            // The task was canceled.
        }
}
```

A `multipart/form-data` upload might look like:

```swift
// https://api.example.com/v1/submit_cat with photo
let req = HTTP.request(POST: "submit_cat", parameters: ["name": "Fluffles", "color": "tabby"])!
// We could add the image synchronously, but it's better to be asynchronous.
// Note: There is a convenience function to do this already, this is just an example.
req.addMultipartBody { upload in
    // This block executes on a background queue.
    if let data = UIImageJPEGRepresentation(catPhoto, 0.9) {
        upload.addMultipart(data: data, withName: "photo", mimeType: "image/jpeg")
    }
}
let task = req.parseAsJSON(using: { try SubmitCatResponse(json: $0.getValue()) })
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
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        // PMHTTP defines a default User-Agent but we can supply our own
        config.HTTPAdditionalHeaders = ["User-Agent": myUserAgent]
        httpManager.sessionConfiguration = config
        if let (username, apiKey) = getAPICredentials() {
            httpManager.defaultCredential = URLCredential(user: username, password: apiKey, persistence: .forSession)
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
simple wrapper around a `URL` and represents the base URL that requests should use if the request
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
objects in order to be compatible with Obj-C. Unlike `URLRequest`, PMHTTP requests are inherently
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
of `URLSessionTask` and is completely thread-safe. It provides properties for inspecting the
current state of the request, including for accessing the underlying `URLSessionTask`, and it
provides a `cancel()` method for canceling the request. Unlike `URLSessionTask.cancel()`,
`HTTPManagerTask.cancel()` can be used to cancel a request while the parse handler is executing, not
just canceling the networking portion. PMHTTP guarantees that if you execute
`HTTPManagerTask.cancel()` from the same queue that the completion block is targeting, prior to the
completion block itself executing, the completion block will always be given a result of `.canceled`
even if it had already finished parsing before `cancel()` was invoked. This means that if you target
the main queue for your completion block, you can be confident that a canceled task will never
behave as though it succeeded or failed.

Like `URLSessionTask`, `HTTPManagerTask` supports key-value observing (although, like
`URLSessionTask`, the KVO messages will occur on some background queue).

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
However, this behavior is inappropriate for most REST API requests, and `URLSession` does not
document its caching strategy for such responses. To handle this case, PMHTTP inspects JSON
responses for appropriate caching headers and explicitly prevents responses from being cached
if they do not include the appropriate cache directives. By default this behavior is only applied
to requests created with `.parseAsJSON()`, `.parseAsJSON(using:)`, or `.decodeAsJSON(_:)`, although
it can be overridden on a per-request basis (see
`HTTPManagerRequest.defaultResponseCacheStoragePolicy`). Notably, requests created with
`.parse(using:)` do not use this cache strategy as it would interfere with caching image requests.

#### Mocking

PMHTTP has built-in support for mocking network requests. This is done without swizzling (so it's
safe to mock requests even in App Store builds), and it's done in a fashion that still creates a
valid `URLSessionTask` (so any code that inspects `HTTPManagerTask.networkTask` will function as
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
github "postmates/PMHTTP" ~> 4.0
```

This release supports Swift 4.0. For Swift 3.x you can use

```
github "postmates/PMHTTP" ~> 3.0
```

### CocoaPods
To install using [CocoaPods](https://cocoapods.org), add the following to your Podfile:

```
pod "PMHTTP", "~> 4.0"
```

This release supports Swift 4.0. For Swift 3.x you can use:

```
pod "PMHTTP", "~> 3.0"
```

## License

Licensed under either of
 * Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
   http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   http://opensource.org/licenses/MIT) at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the
work by you shall be dual licensed as above, without any additional terms or conditions.

## Version History

#### Development

* Add Obj-C convenience functions for creating upload requests with an `NSData` but no explicit `contentType` ([#65][]).
* Fix the Obj-C `-setValue:forHeaderField:` and `-setValue:forDefaultHeaderField:` methods to take a nullable value ([#67][]).
* Add `HTTPManagerRetryBehavior.init(any:)` to combine multiple retry behaviors together ([#69][]).
* Add `HTTPManagerRequest.HTTPHeaders` methods `init(minimumCapacity:`) and `reserveCapacity(_:)` and property `capacity` ([#66][]).

[#65]: https://github.com/postmates/PMHTTP/issues/65 "Obj-C convenience functions for requests with data"
[#66]: https://github.com/postmates/PMHTTP/issues/66 "Add HTTPManagerRequest.HTTPHeaders.init(minimumCapacity:) and .reserveCapacity(_:)"
[#67]: https://github.com/postmates/PMHTTP/issues/67 "Obj-C -[HTTPManagerRequest setValue:forHeaderField:] should take nullable value"
[#69]: https://github.com/postmates/PMHTTP/issues/69 "HTTPManagerRetryBehavior should support composition"

#### v4.4.3 (2019-11-14)

* Support PMJSON 4.x in addition to PMJSON 3.x with CocoaPods. Carthage doesn't support that kind of version range so it's now just set to PMJSON 4.x only.

#### v4.4.2 (2019-08-13)

* Fix a bug with the deprecated `HTTPManagerObjectParseRequest.credential` property where assigning to the property wouldn't work.

#### v4.4.1 (2019-04-24)

* Work around a CocoaPods bug with Swift versions ([CocoaPods/CocoaPods#8635][]).

[CocoaPods/CocoaPods#8635]: https://github.com/CocoaPods/CocoaPods/issues/8635 "Unrecognized 'swift_version' key · Issue #8635 · CocoaPods/CocoaPods"

#### v4.4.0 (2019-04-23)

* Fix a bug when parsing images where we passed the wrong value for the type identifier hint, resulting in a warning being logged to the console ([#62][]).
* Add computed properties on `HTTPManagerError` for convenient access to the associated values (e.g. `.response`, `.body`, etc).
* Add computed property `HTTPManagerError.statusCode` that returns the failing status code for the error, or `nil` for `.unexpectedContentType` ([#60][]).
* Add Obj-C function `PMHTTPErrorGetStatusCode()` that returns the failing status code for the error, or `nil` for `PMHTTPErrorUnexpectedContentType` or for non-PMHTTP errors ([#60][]).
* Provide `PMHTTPStatusCodeErrorKey` user info key for more error types ([#59][]).
* Add computed property `URLResponse.isUnmockedInterceptedRequest` that can be used to test if a response comes from a request that was intercepted by the mock manager without a mock installed ([#46][]).

[#46]: https://github.com/postmates/PMHTTP/issues/46 "Consider making intercepted unmocked requests return 501 instead of 500 · Issue #46 · postmates/PMHTTP"
[#59]: https://github.com/postmates/PMHTTP/issues/59 "PMHTTPStatusCodeErrorKey should be used for unauthorized and unexpectedNoContent · Issue #59 · postmates/PMHTTP"
[#60]: https://github.com/postmates/PMHTTP/issues/60 "HTTPManagerError should have .statusCode property · Issue #60 · postmates/PMHTTP"
[#62]: https://github.com/postmates/PMHTTP/issues/62 "Unknown Hint Identifier for Image MIME Types · Issue #62 · postmates/PMHTTP"

#### v4.3.3 (2019-04-07)

* Update `PMHTTPErrorIsFailedResponse` to handle `PMHTTPErrorUnexpectedNoContent` and `PMHTTPErrorUnexpectedRedirect` in addition to `PMHTTPErrorFailedResponse` and `PMHTTPErrorUnauthorized`.
* Fix warnings introduced by Xcode 10.2.

#### v4.3.2 (2018-11-14)

* Fix bug where requests constructed from a `URL` would not inherit environmental defaults (e.g. auth, headers, etc) ([#52][]).

[#52]: https://github.com/postmates/PMHTTP/issues/52 "Requests constructed with relative URLs do not inherit environment configuration · Issue #52 · postmates/PMHTTP"

#### v4.3.1 (2018-08-01)

* Add `URLProtocol` method overloads to query and set protocol properties on `HTTPManagerRequest`s ([#43][]).

[#43]: https://github.com/postmates/PMHTTP/issues/43 "Let me attach arbitrary URLProtocol properties to a request · Issue #43 · postmates/PMHTTP"

#### v4.3.0 (2018-07-26)

* Expose `HTTPManagerTask.userInitiated` as a public property ([#42][]).
* Add another parameter to the `HTTPManager.MetricsCallback` callback. In order to retain backwards compatibility, the old initializer and property were deprecated and a new initializer and property were added with different names ([#41][]).

[#41]: https://github.com/postmates/PMHTTP/issues/41
[#42]: https://github.com/postmates/PMHTTP/issues/42

#### v4.2.0 (2018-07-10)

* Percent-encode more characters for `application/x-www-form-urlencoded` bodies and query strings. Notably, semicolon (;) is now percent-encoded, as some servers treat it as a separator.
* Optimize task metrics collection such that metrics are not collected if `metricsCallback` is `nil` ([#37][]).
* Extend built-in retry behaviors to support custom strategies ([#35][]).
* Add `HTTPManagerRequest` properties that correspond to the `URLRequest` properties `mainDocumentURL` and `httpShouldHandleCookies` ([#40][]).

[#35]: https://github.com/postmates/PMHTTP/issues/35
[#37]: https://github.com/postmates/PMHTTP/issues/37
[#40]: https://github.com/postmates/PMHTTP/issues/40

#### v4.1.1 (2018-06-21)

* Add `HTTPHeaders.merge(_:uniquingKeysWith:)` and `HTTPHeaders.merging(_:uniquingKeysWith:)`.
* Deprecate `HTTPHeaders.append(contentsOf:)`.
* Merge header fields when calling `HTTPManagerRequest.setDefaultEnvironmentalProperties()`, giving priority to existing request header fields in the case
  of a conflict.

#### v4.1.0 (2018-06-15)

* Support mocking relative URLs when no environment has been set.
* Shrink the default mock delay to 10ms.
* Make `HTTPManagerRequest.headerFields` mutable in Obj-C.
* Add `HTTPManager.defaultHeaderFields` which defines the default header fields to attach to requests and, like `defaultAuth`, only applies to requests within the current environment.
* Declare conformance to `Equatable` for `HTTPManagerRequest.HTTPHeaders`.
* Fix fatal error when using deferred multipart bodies along with `serverRequiresContentLength`.
* Add `HTTPManager.metricsCallback` to collect task metrics (`URLSessionTaskMetrics`) from all tasks associated with the `HTTPManager`.

#### v4.0.1 (2018-05-17)

* Fix `<PMHTTP/PMHTTP.h>` so it can be imported from Obj-C++ code.

#### v4.0.0 (2018-02-23)

* Convert to Swift 4.
* Add a method `HTTPManagerParseRequest.map(_:)`.
* Add methods `HTTPManagerDataRequest.decodeAsJSON(_:with:options:)` and `HTTPManagerActionRequest.decodeAsJSON(_:with:options:)`.

#### v3.0.5 (2017-09-11)

* Extend `HTTPAuth` to support handling 403 Forbidden errors as well.

#### v3.0.4 (2017-09-05)

* Support Swift 3.2.
* Handle `serverRequiresContentLength` correctly in `preparedURLRequest`.

#### v3.0.3 (2017-08-18)

* Add overloads to the request creation methods that take a `URL`. These overloads return a non-optional request.
* Add new property `HTTPManagerRequest.serverRequiresContentLength`. This disables streaming body support (for JSON and multipart/mixed) and instead encodes the body synchronously so it can provide a `"Content-Length"` header to the server. There is a corresponding `HTTPManager.defaultServerRequiresContentLength` property as well.
* Add a method `HTTPManagerRequest.setDefaultEnvironmentalProperties()` that sets properties to the `HTTPManager`-defined defaults that otherwise are only set if the request's path matches the environment. This is primarily intended for requests constructed using absolute paths (e.g. `HTTP.request(GET: "/foo")`) that should still use the environment defaults. Right now this method only sets `auth` and `serverRequiresContentLength`.

#### v3.0.2 (2017-05-01)

* Add `@discardableResult` to Obj-C `-performRequest…` methods.

#### v3.0.1 (2017-03-28)

* Fix Xcode 8.3 compatibility.

#### v3.0.0 (2017-02-27)

* Preserve network task priority when retrying tasks.
* Add convenience Obj-C function `PMHTTPErrorIsFailedResponse` to test PMHTTP errors easily.
* Add methods `.parseAsImage(scale:)` and `.parseAsImage(scale:using:)` to `HTTPManagerDataRequest` and `HTTPManagerActionRequest`.
* When a session is reset, cancel any tasks that were created but never resumed.
* Ensure that the completion block is always deallocated on either the completion queue or on the thread that created the task. Previously there was a very subtle race that meant the completion block could deallocate on the `URLSession`'s delegate queue instead. This only matters if your completion block captures values whose `deinit` cares about the current thread.
* Expand dictionaries, arrays, and sets passed as parameters. Dictionaries produce keys of the form `"foo[bar]"` and arrays and sets just use the key multiple times (e.g. `"foo=bar&foo=qux"`). The expansion is recursive. The order of values from expanded dictionaries and sets is implementation-defined. If you want `"array[]"` syntax, then put the `"[]"` in the key itself. See the documentation comments for more details. Do note that this behavior is slightly different from what AFNetworking does.
* Also expand nested `URLQueryItem`s in parameters. The resulting parameter uses dictionary syntax (`"foo[bar]"`).
* Change the type signature of the Obj-C parse methods that take handlers to make the error parameter non-optional.
* Provide a callback that can be used for session-level authentication challenges. This can be used to implement SSL pinning using something like [TrustKit](https://github.com/datatheorem/TrustKit).
* Fix a small memory leak when retrying tasks.
* Rework how authorization works. The `defaultCredential` and `credential` properties have been replaced with `defaultAuth` and `auth`, using a brand new protocol `HTTPAuth`. An implementation of Basic authentication is provided with the `HTTPBasicAuth` object. This new authentication mechanism has been designed to allow for OAuth2-style refreshes, and a helper class `HTTPRefreshableAuth` is provided to make it easy to implement refreshable authentication.

#### v2.0.1 (2017-01-05)

* Fix PMJSON dependency in CocoaPods podspec.

#### v2.0.0 (2017-01-03)

* Support `text/json` in addition to `application/json`.
* Add 2 convenience methods for uploading `UIImage`s as PNG or JPEG data.
* Add `objcError` property to `PMHTTPResult`.
* Change `objcError` on `HTTPManagerTaskResult` to `Error?` instead of `NSError?`.
* Fix Xcode 8.1 compatibility of unit tests.
* Add optional `options` parameter to `parseAsJSON()` and `parseAsJSON(with:)`.
* Add `withMultipartBody(using:)` to `HTTPManagerUploadFormRequest`.
* Rename `parse(with:)`, `parseAsJSON(options:with:)`, and `addMultipartBody(with:)` to use the parameter name `using:` instead, which is more in line with Swift 3 Foundation naming conventions.

#### v1.0.4 (2016-10-20)

* Add more Obj-C request constructors.
* Fix encoding of `+` characters in query strings and `application/x-www-form-urlencoded` bodies.

#### v1.0.3 (2016-09-23)

* Fix obj-c name of `HTTPManager.parsedDateHeader(from:)`.

#### v1.0.2 (2016-09-22)

* Add fix-its for the Swift 3 API changes.

#### v1.0.1 (2016-09-12)

* Adopt `CustomNSError` and deprecate the `NSError` bridging methods.
* Add autoreleasepools to dispatch queues where appropriate.
* Fix CocoaPods support.

#### v1.0.0 (2016-09-09)

* Support Swift 3.0.

#### v0.9.3 (2016-09-09)

* Fix building for tvOS.

#### v0.9.2 (2016-09-09)

* Support Swift 2.3.

#### v0.9.1 (2016-08-17)

* Rename Source folder to Sources.
* CocoaPods support.

#### v0.9 (2016-08-05)

Initial release.
