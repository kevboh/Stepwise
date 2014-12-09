//
//  StepwiseTests.swift
//  Webs
//
//  Copyright (c) 2014, Webs <kevin@webs.com>
//
//  Permission to use, copy, modify, and/or distribute this software for any
//      purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
//  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
//  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

import UIKit
import XCTest
import Stepwise

let ErrorDomain = "com.async-step.tests"
let AsyncDispatchSpecificKey : NSString = "AsyncDispatchSpecificKey"

class StepwiseTests: XCTestCase {
    
    func testDSL() {
        let expectation = expectationWithDescription("Chain creates a string from a number.")
        
        let chain = toStep { (step : Step<Int, Int>) in
            step.resolve(step.input + 1)
        }.then { (step : Step<Int, String>) in
            step.resolve("\(step.input)")
        }.then { (step : Step<String, Void>) in
            XCTAssertEqual(step.input, "3", "Assuming 2, chain adds 1, then transforms to string.")
            step.resolve()
            expectation.fulfill()
        }
        
        chain.start(2)
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testChaining() {
        // Different ways to chain:
        // step -> chain.then
        // step -> chain.then(chain:)
        // step -> resolve.then(chain:)
        
        // step -> chain.then
        let chain1Expectation = expectationWithDescription("Chain #1 completed.")
        
        toStep { (step : Step<Int, Int>) in
            step.resolve(step.input + 1)
        }.then { (step : Step<Int, Int>) in
            step.resolve(step.input + 2)
        }.then { (step : Step<Int, Int>) in
            step.resolve(step.input + 3)
        }.then { (step : Step<Int, Void>) in
            XCTAssertEqual(step.input, 7, "Assuming 1, should add 6.")
            step.resolve()
            chain1Expectation.fulfill()
        }.start(1)
        
        // step -> chain.then(chain:)
        let chain2Expectation = expectationWithDescription("Chain #2 completed.")
        
        let chain2 = toStep { (step: Step<Int, Int>) in
            step.resolve(step.input + 1)
        }
        let chain2b = toStep { (step: Step<Int, Int>) in
            step.resolve(step.input + 2)
        }
        let chain2c = toStep { (step: Step<Int, Int>) in
            step.resolve(step.input + 3)
        }
        let chain2d = toStep { (step: Step<Int, Void>) in
            XCTAssertEqual(step.input, 7, "Assuming 1, should add 6.")
            step.resolve()
            chain2Expectation.fulfill()
        }
        chain2.then(chain2b).then(chain2c).then(chain2d)
        chain2.start(1)
        
        // step -> resolve.then(chain:)
        let chain3Expectation = expectationWithDescription("Chain #3 completed.")
        
        let chain3d = toStep { (step: Step<Int, Void>) in
            XCTAssertEqual(step.input, 7, "Assuming 1, should add 6.")
            step.resolve()
            chain3Expectation.fulfill()
        }
        let chain3c = toStep { (step: Step<Int, Int>) in
            step.resolve(step.input + 3, then: chain3d)
        }
        let chain3b = toStep { (step: Step<Int, Int>) in
            step.resolve(step.input + 2, then: chain3c)
        }
        let chain3 = toStep { (step: Step<Int, Int>) in
            step.resolve(step.input + 1, then: chain3b)
        }
        chain3.start(1)
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testCustomStepQueue() {
        let customQueue = dispatch_queue_create("com.pagemodokit.tests.async-step.custom", nil)
        var context : NSString = "testCustomStepQueue() test context"
        dispatch_queue_set_specific(customQueue, AsyncDispatchSpecificKey.UTF8String, &context, nil)
        
        let expectatation = expectationWithDescription("Expect current queue to match specified queue.")
        
        toStep(customQueue) { (step: Step<Void, Void>) in
            let result = dispatch_get_specific(AsyncDispatchSpecificKey.UTF8String)
            if result != nil {
                expectatation.fulfill()
            }
        }.start()
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testStepError() {
        let errorExpectation = expectationWithDescription("Second step errored.")
        
        let errorStep = toStep { (step: Step<Void, String>) in
            step.error(NSError(domain: ErrorDomain, code: 0, userInfo: nil))
        }.onError { error in
            errorExpectation.fulfill()
        }
        
        errorStep.start()
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testChainErrorFirstStep() {
        let errorExpectation = expectationWithDescription("Second step errored.")
        
        let chain = toStep { (step: Step<Void, String>) in
            step.error(NSError(domain: ErrorDomain, code: 0, userInfo: nil))
        }.then { (step : Step<String, Int>) in
            XCTFail("This step should not execute.")
            step.resolve(1)
        }.onError { error in
            errorExpectation.fulfill()
        }
        
        chain.start()
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testChainErrorLaterStep() {
        let resolveExpectation = expectationWithDescription("First step resolved to second.")
        let errorExpectation = expectationWithDescription("Second step errored.")
        
        let chain = toStep { (step: Step<Void, String>) in
            step.resolve("some result")
        }.then { (step : Step<String, Int>) in
            resolveExpectation.fulfill()
            step.error(NSError(domain: ErrorDomain, code: 0, userInfo: nil))
        }.onError { error in
            errorExpectation.fulfill()
        }
        
        chain.start()
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testStepCancellation() {
        var didCancel = true
        
        let willCancelStep = toStep { (step: Step<Void, String>) in
            didCancel = false
            step.resolve("some result")
        }
        
        let token = willCancelStep.cancellationToken
        willCancelStep.start()
        token.cancel(reason: "Cancelling for a really good reason.")
        
        let expectation = expectationWithDescription("Waiting for cancel to take effect.")
        after(1.0) {
            if didCancel {
                XCTAssertEqual(token.reason!, "Cancelling for a really good reason.", "Token reason should match reason given")
                expectation.fulfill()
            }
            else {
                XCTFail("Step should have been cancelled.")
            }
        }
        
        waitForExpectationsWithTimeout(5, nil)
    }
    
    func testChainCancellation() {
        var didCancel = true
        
        let chain = toStep { (step: Step<Void, String>) in
            sleep(5)
            step.resolve("some result")
        }.then { (step: Step<String, Void>) in
            didCancel = false
            step.resolve()
        }
        
        let token = chain.cancellationToken
        chain.start()
        
        let expectation = expectationWithDescription("Waiting for cancel to take effect.")
        after(3.0) {
            let result = token.cancel(reason: "Cancelling for a really good reason.")
        }
        after(7.0) {
            if didCancel {
                expectation.fulfill()
            }
            XCTAssertEqual(token.reason!, "Cancelling for a really good reason.", "Cancellation reason should match one given.")
        }
        
        waitForExpectationsWithTimeout(10, nil)
    }
    
    func testDocumentationExamples() {
        // MARK: Example 1
        let example1Expectation = expectationWithDescription("Documentation example 1. Resolving a full chain.")
        
        let fetchAndResizeImageSteps = toStep { (step: Step<NSURL, UIImage>) in
            // This is the url we pass into the step chain
            let url = step.input
            
            // Fetch the image data. Obviously we'd be using Alamofire or something irl.
            if let imageData = NSData(contentsOfURL: url) {
                // Create the image
                let image = UIImage(data: imageData)!
                
                // Pass it to the next step
                step.resolve(image)
            }
            else {
                // Oh no! Something went wrong!
                step.error(NSError(domain: "com.my.domain", code: -1, userInfo: nil))
            }
        }.then { (step: Step<UIImage, UIImage>) in
            // Grab the fetched image
            let image = step.input
            
            // Resize it
            let targetSize = CGSize(width: image.size.width / 2.0, height: image.size.height / 2.0)
            UIGraphicsBeginImageContextWithOptions(targetSize, true, 0.0)
            image.drawInRect(CGRect(origin: CGPoint(x: 0, y: 0), size: targetSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // Return it
            step.resolve(resizedImage)
        }.then { (step: Step<UIImage, Void>) in
            // Get fetched, resized image
            let image = step.input
            
            XCTAssertEqual(image.size, CGSize(width: 240, height: 204), "Assuming input image of lime-cat.jpg, image should be shrunk in half.")
            example1Expectation.fulfill()
            
            // Do something with image here.
            // Set it to a shared variable, pass it to another step, etc.
            step.resolve()
        }
        
        let limecatFileURL = NSBundle(forClass: StepwiseTests.self).pathForResource("lime-cat", ofType: "jpg")!
        let importantImageURL = NSURL(fileURLWithPath: limecatFileURL)!
        fetchAndResizeImageSteps.start(importantImageURL)
        
        // MARK: Example 2
        let example2Expectation = expectationWithDescription("Documentation example 2. Erroring during a step.")
        
        toStep { (step: Step<Void, String>) in
            step.error(NSError(domain: "com.my.domain", code: -1, userInfo: [NSLocalizedDescriptionKey : "Error in step 1!"]))
        }.then { (step : Step<String, Int>) in
            // This never executes.
            println("I never execute!")
            step.resolve(countElements(step.input))
        }.onError { error in
            example2Expectation.fulfill()
            println("ERROR: \(error.localizedDescription)")
        }.start()
        
        // MARK: Example 3
        let example3Expectation = expectationWithDescription("Documentation example 3. Canceling during a step.")
        var example3DidCancel = true
        
        let willCancelStep = toStep { (step: Step<Void, String>) in
            // Will never execute.
            example3DidCancel = false
            step.resolve("some result")
        }
        
        willCancelStep.start()
        
        // Grab the step's token and cancel it.
        let token = willCancelStep.cancellationToken
        token.cancel(reason: "Cancelling for a really good reason.")
        
        // Test that cancellation happened
        after(1.0) {
            if example3DidCancel {
                XCTAssertEqual(token.reason!, "Cancelling for a really good reason.", "Token reason should match reason given")
                example3Expectation.fulfill()
            }
            else {
                XCTFail("Step should have been cancelled.")
            }
        }
        
        // Wait for all documentation expectations.
        waitForExpectationsWithTimeout(10, nil)
    }
}

private func after(delay: Double, closure: () -> ()) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC))), dispatch_get_main_queue(), closure)
}