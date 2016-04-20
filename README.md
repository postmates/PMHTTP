# PMHTTP

[![Version](https://img.shields.io/badge/version-v0.5-blue.svg)](https://github.com/postmates/PMHTTP/releases/latest)
![Platforms](https://img.shields.io/badge/platforms-ios%20%7C%20osx%20%7C%20tvos-lightgrey.svg)
![Languages](https://img.shields.io/badge/languages-swift%20%7C%20objc-orange.svg)
![License](https://img.shields.io/badge/license-MIT%2FApache-blue.svg)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)][Carthage]

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

## Usage

A typical GET request looks like:

```swift
// https://api.example.com/v1/search?query=%s
let task = HTTP.request(GET: "search", parameters: ["query": "cute cats"])
    .parseAsJSON()
    .performRequestWithCompletion(onQueue: .mainQueue()) { task, result in
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
    .parseAsJSONWithHandler({ response, json in
        return try SubmitCatResponse(json: json)
    })
    .performRequestWithCompletion(onQueue: .mainQueue()) { task, result in
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
let req = HTTP.request(POST: "submit_cat", parameters: ["name": "Fluffles", "color": "tabby"])
// We could add the image synchronously, but it's better to be asynchronous.
req.addMultipartBodyWithBlock { upload in
    // This block executes on a background queue.
    if let data = UIImageJPEGRepresentation(catPhoto, 0.9) {
        upload.addMultipartData(data, withName: "photo", mimeType: "image/jpeg")
    }
}
let task = req.parseAsJSONWithHandler({ try SubmitCatResponse(json: $1) })
    .performRequestWithCompletion(onQueue: .mainQueue()) { task, result in
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
    public func configureHTTPManager(httpManager: HTTPManager) {
        httpManager.environment = HTTPManager.Environment(string: /* ... */)
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        config.timeoutIntervalForRequest = 10
        // PMHTTP defines a default User-Agent but we can supply our own
        config.HTTPAdditionalHeaders = ["User-Agent": myUserAgent]
        httpManager.sessionConfiguration = config
        if let (username, apiKey) = getAPICredentials() {
            httpManager.defaultCredential = NSURLCredential(user username, password: apiKey, persistence: .ForSession)
        }
        httpManager.defaultRetryBehavior = HTTPManagerRetryBehavior.retryNetworkFailureOrServiceUnavailable(withStrategy: .retryTwiceWithDefaultDelay)
    }
}
```

### Cache Handling

PMHTTP implements intelligent cache handling for JSON responses. The HTTP standard allows user
agents to cache responses at their discretion when the response does not include caching headers.
However, this behavior is inappropriate for most REST API requests, and `NSURLSession` does not
document its caching strategy for such responses. To handle this case, PMHTTP inspects JSON
responses for appropriate caching headers and explicitly prevents responses from being cached
if they do not include the appropriate cache directives. By default this behavior is only applied
to requests created with `.parseAsJSON()` or `.parseAsJSONWithHandler(_:)`, although it can be
overridden on a per-request basis (see `HTTPManagerRequest.defaultResponseCacheStoragePolicy`).
Notably, requests created with `.parseWithHandler(_:)` do not use this cache strategy as it would
interfere with caching image requests.

## Requirements

Requires a minimum of iOS 8, OS X 10.9, watchOS 2.0, or tvOS 9.0.

### watchOS and extensions

The framework project declares support for watchOS, but because of the network activity indicator
code it can't be built with `APPLICATION_EXTENSION_API_ONLY`. I'm not sure offhand if watchOS 2.0
requires that setting or if it's only required for watchOS 1.x and other extensions (see
[issue #6](https://github.com/postmates/PMHTTP/issues/6)).

## Installation

### Carthage

To install using [Carthage][], add the following to your Cartfile:

```
github "postmates/PMHTTP" ~> 0.5
```

Once installed, you can use this by adding `import PMHTTP` to your code.

## License

Licensed under either of
 * Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
   http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   http://opensource.org/licenses/MIT) at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you shall be dual licensed as above, without any additional terms or conditions.

## Version History

#### v0.5 (2016-04-19)

Initial release.
