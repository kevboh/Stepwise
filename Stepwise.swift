//
//  Stepwise.swift
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

import Foundation

// TODO: Once/if we can specialize generic top-level functions, consider a new DSL syntax.
// TODO: Add debug log flag.

// MARK: DSL

private let DefaultStepQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

/// Package the supplied closure as the first step in a chain. Schedules the nameless step on default global queue.
///
/// :param: body The body of the step, which takes InputType as input and outputs OutputType.
/// :returns: A StepChain object. Can be extended with then() and started with start().
public func toStep<InputType, OutputType>(body: (Step<InputType, OutputType>) -> ()) -> StepChain<InputType, OutputType, InputType, OutputType> {
    return toStep(nil, DefaultStepQueue, body)
}

/// Package the supplied closure as the first step, named name, in a chain. Schedules on default global queue.
///
/// :param: named Name of the step. Logged for debugging.
/// :param: body The body of the step, which takes InputType as input and outputs OutputType.
/// :returns: A StepChain object. Can be extended with then() and started with start().
public func toStep<InputType, OutputType>(named: String?, body: (Step<InputType, OutputType>) -> ()) -> StepChain<InputType, OutputType, InputType, OutputType> {
    return toStep(named, DefaultStepQueue, body)
}

/// Package the supplied closure on queue as the first step in a chain. Schedules a nameless step.
///
/// :param: inQueue Queue on which to execute the step.
/// :param: body The body of the step, which takes InputType as input and outputs OutputType.
/// :returns: A StepChain object. Can be extended with then() and started with start().
public func toStep<InputType, OutputType>(inQueue: dispatch_queue_t!, body: (Step<InputType, OutputType>) -> ()) -> StepChain<InputType, OutputType, InputType, OutputType> {
    return toStep(nil, inQueue, body)
}

/// Package the supplied closure on queue as the first step, named name, in a chain.
///
/// :param: named Name of the step. Logged for debugging.
/// :param: inQueue Queue on which to execute the step.
/// :param: body The body of the step, which takes InputType as input and outputs OutputType.
/// :returns: A StepChain object. Can be extended with then() and started with start().
public func toStep<InputType, OutputType>(named: String?, inQueue: dispatch_queue_t!, body: (Step<InputType, OutputType>) -> ()) -> StepChain<InputType, OutputType, InputType, OutputType> {
    let step = StepNode<InputType, OutputType>(name: named, queue: inQueue, body)
    return StepChain(step, step)
}

/// A closure that accepts an NSError. Used when handling errors in Steps.
public typealias StepErrorHandler = (NSError) -> ()

/// The result of any Step scheduling operation (step(), then()).
/// Provides a model that can be started or canceled.
/// New operations can be added to the chain with then().
/// StepChains are not reusable and can only be started once.
public class StepChain<StartInputType, StartOutputType, CurrentInputType, CurrentOutputType> {
    /// A CancellationToken that provides a one-time cancel operation that will abort execution at whatever step is currently in progress.
    public var cancellationToken : CancellationToken { return firstNode.cancellationToken }
    
    // Private node-tracking.
    private let firstNode : StepNode<StartInputType, StartOutputType>
    private let lastNode : StepNode<CurrentInputType, CurrentOutputType>
    
    private init(_ first: StepNode<StartInputType, StartOutputType>, _ last: StepNode<CurrentInputType, CurrentOutputType>) {
        self.firstNode = first
        self.lastNode = last
    }
    
    /// Add a new step named name on queue to the receiver and return the result.
    ///
    /// :param: name The name of the step. Defaults to nil.
    /// :param: queue The queue on which to execute the step. Defaults to default priority global queue.
    /// :param: body The body of the step, which takes InputType as input and outputs OutputType.
    /// :returns: A new StepChain that ends in the added step. Can be extended with then() and started with start().
    public func then<NextOutputType>(name: String? = nil, queue: dispatch_queue_t! = DefaultStepQueue, body: (Step<CurrentOutputType, NextOutputType>) -> ()) -> StepChain<StartInputType, StartOutputType, CurrentOutputType, NextOutputType> {
        let step = StepNode<CurrentOutputType, NextOutputType>(name: name, queue: queue, body)
        return then(step)
    }
    
    /// Add all steps in chain to the receiver and return the result.
    ///
    /// :param: chain The StepChain to append to the receiver.
    /// :returns: A new StepChain that includes all steps in the receiver, then all steps in chain. Can be extended with then() and started with start().
    public func then<Value1, Value2, Value3>(chain: StepChain<CurrentOutputType, Value1, Value2, Value3>) -> StepChain<StartInputType, StartOutputType, Value2, Value3> {
        // Connect first step of incoming chain
        lastNode.then(chain.firstNode)
        
        // Return last step of incoming chain
        return StepChain<StartInputType, StartOutputType, Value2, Value3>(firstNode, chain.lastNode)
    }
    
    private func then<NextOutputType>(nextStep: StepNode<CurrentOutputType, NextOutputType>) -> StepChain<StartInputType, StartOutputType, CurrentOutputType, NextOutputType> {
        lastNode.then(nextStep)
        return StepChain<StartInputType, StartOutputType, CurrentOutputType, NextOutputType>(firstNode, nextStep)
    }
    
    /// Begins execution of each step in the chain, in order.
    ///
    /// :param: input The input for the first step.
    public func start(input: StartInputType) {
        firstNode.start(input)
    }
    
    /// Adds an error handler to every step in the chain.
    /// NOTE: Each chain may only have a single error handler.
    ///
    /// :param: errorHandler The handler to add to the chain.
    /// :returns: The step chain.
    public func onError(errorHandler: StepErrorHandler) -> StepChain<StartInputType, StartOutputType, CurrentInputType, CurrentOutputType> {
        firstNode.errorHandler = errorHandler
        return self
    }
}

/// A step in an asynchronous step chain. Used to control the result of the step body.
public class Step<InputType, OutputType> {
    /// The input passed to this step.
    public let input : InputType

    private var node : StepNode<InputType, OutputType>?
    
    private init(input: InputType, step: StepNode<InputType, OutputType>) {
        self.input = input
        self.node = step
    }
    
    /// Mark the step as successfully generating output.
    ///
    /// :param: output The output of the step.
    public func resolve(output: OutputType) {
        if let step = node {
            println("Resolved \(step) with output: \(output)")
            step.resolveHandler?(output)
        }
        node = nil
    }
    
    /// Mark the step as successfully generating output and then continue to a new chain of steps.
    ///
    /// :param: output The output of the step.
    /// :param: chain The next chain of steps to execute. The first step in this chain will accept output as its input.
    public func resolve<Value2, Value3, Value4>(output: OutputType, then chain: StepChain<OutputType, Value2, Value3, Value4>) {
        if let step = node {
            println("Resolving \(step) to new chain...")
            step.then(chain.firstNode)
        }
        resolve(output)
    }
    
    /// Mark the step as having failed with error.
    ///
    /// :param: error The error generated in this step.
    public func error(error: NSError) {
        if let step = node {
            println("\(step) errored: \(error)")
            step.errorHandler?(error)
        }
        node = nil
    }
    
    private func stepWasCanceled() {
        node = nil
    }
}

/// A token that can signal a one-time cancellation of a step chain.
/// An optional reason can be given and will be logged.
public class CancellationToken {
    /// Whether the token was given a cancel signal.
    public var cancelled : Bool {
        var result : Bool = false
        dispatch_sync(queue) {
            result = self._cancelled
        }
        return result
    }
    /// An optional reason supplied when the cancel signal was sent.
    public var reason : String?
    
    private let queue = dispatch_queue_create("com.pagemodo.posts.cancel-token.lock", nil)
    private var _cancelled : Bool = false
    
    /// Marks the token as cancelled. Irreversible.
    /// All steps with this token will check for cancellation and cease execution if true.
    ///
    /// :param: reason An optional reason for canceling. Defaults to nil.
    /// :returns: true if cancel was successful, false if the token was already cancelled.
    public func cancel(reason: String? = nil) -> Bool {
        if self._cancelled { return false }
        dispatch_sync(queue) {
            self._cancelled = true
            self.reason = reason
        }
        return true
    }
}

/// MARK: Private

// Node that encapsulates each step body in the chain
private class StepNode<InputType, OutputType> : Printable {
    private typealias StepBody = (Step<InputType, OutputType>) -> ()
    
    // Name of the step.
    private var name : String?
    // Queue on which to execute the step.
    private let executionQueue : dispatch_queue_t!
    // Token, checked on start and on execution.
    private var cancellationToken : CancellationToken = CancellationToken()
    // true if token has been marked as cancelled, false if not.
    private var isCancelled : Bool { return cancellationToken.cancelled }
    private var description : String {
        if let name = name {
            return "[Step '" + name + "']"
        }
        return "[Step]"
    }
    // Closure body for step.
    private let body : StepBody
    // Executed when step is resolved.
    private var resolveHandler : ((OutputType) -> ())?
    // Executed when step errors.
    private var errorHandler : StepErrorHandler?
    // The control, publicly exposed as the "step," that's handed via the API and used to resolve/error.
    private weak var control : Step<InputType, OutputType>?
    
    private init(name: String?, queue: dispatch_queue_t!, body: StepBody) {
        self.name = name
        self.executionQueue = queue
        self.body = body
    }
    
    // Starts the step on the target queue.
    private func start(input: InputType) {
        if isCancelled { doCancel(); return }
        
        println("Starting \(self) with input: \(input)")
        dispatch_async(executionQueue) {
            if self.isCancelled { self.doCancel(); return }
            
            let thisControl = Step<InputType, OutputType>(input: input, step: self)
            self.control = thisControl
            self.body(thisControl)
        }
    }
    
    // Schedules a new step after this one.
    private func then<Value2>(nextStep: StepNode<OutputType, Value2>) {
        // Scheduling a step overwrites its cancellation token
        nextStep.cancellationToken = self.cancellationToken
        
        resolveHandler = { [weak self] output in
            let isCancelled = self?.isCancelled ?? false
            if isCancelled { self?.doCancel(); return }
            
            // Pass state the chain, if present and unset on future steps
            nextStep.cancellationToken = self?.cancellationToken ?? nextStep.cancellationToken
            nextStep.errorHandler = self?.errorHandler ?? nextStep.errorHandler
            nextStep.start(output)
        }
    }
    
    // Logs the cancellation of this step.
    private func doCancel() {
        if let reason = cancellationToken.reason {
            println("\(self) cancelled with reason: \(reason).")
        }
        else {
            println("\(self) cancelled.")
        }
    }
}