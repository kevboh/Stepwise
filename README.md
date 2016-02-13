# Stepwise

Stepwise is a Swift framework for executing a series of steps asynchronously. Steps are just closures that take an input and return an output. Outputs are passed as inputs to the next step in the chain. A chain of steps is cancelable and handles errors. Here's a totally contrived example of steps to fetch an image from the Internet and shrink it by half:

```swift
let fetchAndResizeImage = toStep { (url : NSURL) -> UIImage in
    // Fetch the image and create it. Obviously we'd be using Alamofire or something irl.
    guard let imageData = NSData(contentsOfURL: url), image = UIImage(data: imageData) else {
        throw NSError(domain: "com.my.domain", code: -1, userInfo: nil)
    }
    
    // Pass it to the next step
    return image

}.then { (image : UIImage) -> UIImage in
    // Resize it
    let targetSize = CGSize(width: image.size.width / 2.0, height: image.size.height / 2.0)
    UIGraphicsBeginImageContextWithOptions(targetSize, true, 0.0)
    image.drawInRect(CGRect(origin: CGPoint(x: 0, y: 0), size: targetSize))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    // Return it
    return resizedImage
}.then { image in
    // Do something with image here.
    // Set it on a view, pass it to another step, etc.
}

// Having set up the chain of steps, pass in a URL to get fetching. You can also do this one the chain directly by just following up the final `then { }` with `.start(...)`. 
let importantImageURL = NSURL(string: "http://i1.kym-cdn.com/entries/icons/original/000/000/774/lime-cat.jpg")!
fetchAndResizeImage.start(importantImageURL)
```

The first step, created by the `toStep` function, accepts a closure (or function) with a single input parameter. The input parameter is of type `NSURL` and outputs a `UIImage` if successful. The first step fetches the data from the URL and tries to create an image from it. If it fails the step throws an error. If all is well the step resolves by calling `return image`.

When a step resolves successfully it passes its output as input to the next step, which is created by calling `then()`. In this example the second step resizes the image to half-size, then resolves with it. There is no error case.

The third step, also enqueued with `then()`, is just an example of a step with a `Void` output. Steps with `Void` outputs don't need to `return` anything, just as steps with `Void` inputs don't need to declare an input at the start of the closure.

### Errors

In the example above there is no matching `catch` for the `throw` in the first step, but you can easily catch errors at any point in the chain by calling `onError()`. `onError()` accepts a simple closure with an `ErrorType` parameter and allows your code to react to errors generated by steps. Here's a quick example:

```swift
// prints "ERROR: Error in step 1!"
toStep { () -> String in
    throw NSError(domain: "com.my.domain", code: -1, userInfo: [NSLocalizedDescriptionKey : "Error in step 1!"])
}.then { (input : String) -> Int in
    // This never executes.
    print("I never execute!")
    return input.characters.count
}.onError { error in
    print("ERROR: \((error as NSError).localizedDescription)")
}.start()
```

An important limitation to note is that, at present, a chain of steps can only have a single `onError` closure. You can multiplex responses to errors in `onError` by checking the result of conditional casts against `error`.

### Handlers 

Sometimes a step may need to be resolved asynchronously: often this occurs when a step makes a network request or calls some API with a callback argument. You can easily cover this case by adding an additional `Handler` argument to your step closures. Instead of returning a value from the step closure, you may call `handler.pass(output)` or `handler.fail(error)` to resolve the step. A step will wait until one of these methods is called, then pass the result to the next step in the chain or the `onError` closure, if present. It looks like this:

```swift
toStep { (input: [String : AnyObject], handler: Handler<String>) in
    Alamofire.request(.GET, "http://httpbin.org/get", parameters: input)
             .responseString { _, _, result in
                handler.pass(result.value)
             }
}
.then { input in
    print(input) // Request results. Do something with them!
}.start(["foo": "bar"])
```

### Cancellation

Cancellation is baked into Stepwise. Every step chain has a `cancellationToken` property that returns a `CancellationToken` object. This object provides a single method, `cancel()`, which cancels any step that has this token. Every step in a chain will consult the token before and during execution to see if it has been canceled. Here's an example:

```swift
let willCancelStep = toStep { () -> String in
    // Will never execute.
    step.resolve("some result")
}.start()

// Grab the step's token and cancel it.
let token = willCancelStep.cancellationToken
token.cancel(reason: "Canceling for a really good reason.")
```

You may optionally provide a `String` reason in the cancel method for logging purposes.

### Finally

Each chain also provides a `finally` method which you can call to attach a handler that will *always* execute when the chain ends, errors, or is canceled. A parameter of type `ChainState` is passed into the handler to indicate the result of the chain. Relying on `finally` to process the result of a chain is discouraged; instead, use another `then` step with a `Void` output type. `finally` is provided for must-occur situations regardless of error or cancel state, like closing file resources. Here's an example:

```swift
// In this extremely contrived example, assume we already have an open `NSOutputStream`
// that we must close after our steps complete, regardless of success or erroring out.
let outputStream : NSOutputStream = ...
let someDataURL : NSURL = ...

toStep { () -> NSData in
    guard let someData = NSData(contentsOfURL: someDataURL) else {
        throw NSError(domain: "com.my.domain.fetch-data", code: -1, userInfo: nil)
    }
    return someData
}.then { data in
    // Write our data
    var bytes = UnsafePointer<UInt8>(data.bytes)
    var bytesRemaining = data.length

    while bytesRemaining > 0 {
        let written = outputStream.write(bytes, maxLength: bytesRemaining)
        if written == -1 {
            throw NSError(domain: "com.my.domain.write-data", code: -1, userInfo: nil)
        }

        bytesRemaining -= written
        bytes += written
    }
}.onError { error in
    // Handle error here...
}.finally { resultState in
    // Close the stream here
    outputStream.close()
}.start()
```

### A Note on Closure Signatures

Sometimes Xcode can't guess the input and output types based on what's happening inside a step closure. This is especially true if you save the steps to a variable and `start` it later. When you get type errors, help poor Xcode out by adding a signature to the start of the closure, like this (from example #1 above):

```swift
let fetchAndResizeImage = toStep { (url : NSURL) -> UIImage in
    // Let's not repeat ourselves
}

// Start the chain
fetchAndResizeImage.start(url)
```

A closure that takes a `Void` and returns a `Void` would be

```swift
toStep { () -> Void in
    // Gaze into the void
}.start()
```

### Installing

Use CocoaPods!

    $ gem install cocoapods

if you don't have it, then in your Podfile:

    pod 'Stepwise', '~> 2.1'

### Tests

All of the examples in this README and others can be found in the library's tests, in [StepwiseTests.swift](https://github.com/websdotcom/Stepwise/blob/master/StepwiseTests/StepwiseTests.swift).

### Random Goodies

Stepwise is lovingly crafted by and used in [Pagemodo.app](https://itunes.apple.com/us/app/pagemodo-for-social-media/id937853905?mt=8). Check it out if you want to make posting to social networks not terrible.

Set `Stepwise.StepDebugLoggingEnabled` to `true` to get log messages of what's happening in your steps.

### Swift Versions

Stepwise uses Swift 2.0. The following table tracks older Swift versions and the corresponding git tag to use for that version.

Swift Version | Tag
------------- | ---
1.0 | swift-1.1
1.1 | swift-1.1
1.2 | swift-1.2
2.0 | 2.0+


### License

    Copyright (c) 2014-2015, Webs <kevin@webs.com>

    Permission to use, copy, modify, and/or distribute this software for any
    purpose with or without fee is hereby granted, provided that the above
    copyright notice and this permission notice appear in all copies.

    THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
    WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
    MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
    ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
    WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
    ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
    OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.