The file CFStreamAbstract.h comes from http://opensource.apple.com, specifically
from CF-1153.18. It contains declarations for a quasi-private CoreFoundation API
that is requred in order to correctly implement custom CFReadStreams. This file
isn't distributed as part of the SDK, but it is in the open source CF release,
and is considered reasonably stable (certainly more stable than the undocumented
NSInputStream methods that you have to override if you go that route).

For context, WebKit also includes a bunch of these same declarations for its own
use, though it uses the deprecated V1 version of the callback struct.

The V2 callbacks can be used at least as far back as iOS 8 / OS X 10.10.

https://trac.webkit.org/browser/trunk/Source/WebCore/platform/network/cf/FormDataStreamCFNet.cpp?rev=199544
http://lists.apple.com/archives/macnetworkprog/2007/May/msg00056.html
