//
//  _concepts_.swift
//  Pods
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

struct Trivial<T>: Listenable, ValueWrapper {
    let repeater: Repeater<T>

    var value: T {
        didSet {
            repeater.send(.value(value))
        }
    }

    init(_ value: T, repeater: Repeater<T>) {
        self.value = value
        self.repeater = repeater
    }

    init(_ value: T) {
        self.init(value, repeater: Repeater.unsafe())
    }

    func sendError(_ error: Error) {
        repeater.send(.error(error))
    }

    func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listening(assign)
    }

    func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return repeater.listeningItem(assign)
    }
}

public final class _Promise<T>: Listenable {
    public typealias Dispatcher = Repeater<T>.Dispatcher

    var disposes: [Disposable] = []
    var _result: ListenEvent<T>? = .none
    var _dispatcher: _Dispatcher

    init(result: ListenEvent<T>? = .none, dispatcher: _Dispatcher) {
        self._result = result
        self._dispatcher = dispatcher
    }

    enum _Dispatcher {
        case direct
        case repeater(NSLocking, Repeater<T>)
    }

    public convenience init() {
        self.init(lock: NSRecursiveLock(), dispatcher: .default)
    }

    public convenience init(_ value: T) {
        self.init(unsafe: .value(value))
    }

    public convenience init(_ error: Error) {
        self.init(unsafe: .error(error))
    }

    /// Creates new instance with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public convenience init(unsafe value: ListenEvent<T>) {
        self.init(result: value, dispatcher: .direct)
    }

    /// Creates new instance with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public convenience init(lock: NSLocking = NSRecursiveLock(), dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        self.init(dispatcher: .repeater(lock, repeater))
    }

    /// Returns storage with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func locked(
        lock: NSLocking = NSRecursiveLock(),
        dispatcher: Dispatcher
        ) -> _Promise {
        return _Promise(lock: lock, dispatcher: dispatcher)
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        switch _dispatcher {
        case .repeater(let lock, let repeater):
            lock.lock()

            switch _result {
            case .none:
                let d = repeater.listening(assign)
                lock.unlock()
                return ListeningDispose {
                    lock.lock()
                    d.dispose()
                    lock.unlock()
                }
            case .some(let v):
                lock.unlock()
                assign.call(v)
                return EmptyDispose()
            }
        case .direct:
            assign.call(_result!)
            return EmptyDispose()
        }
    }
}
public extension _Promise {
    func fulfill(_ value: T) {
        _resolve(.value(value))
    }
    func reject(_ error: Error) {
        _resolve(.error(error))
    }

    internal func _resolve(_ result: ListenEvent<T>) {
        switch _dispatcher {
        case .direct: break
        case .repeater(let lock, let repeater):
            lock.lock()
            disposes.forEach { $0.dispose() }
            disposes.removeAll()
            self._result = .some(result)
            self._dispatcher = .direct
            lock.unlock()
            repeater.send(result)
        }
    }

    typealias Then<Result> = (T) throws -> Result

    @discardableResult
    func then(on queue: DispatchQueue = .main, make it: @escaping Then<Void>) -> _Promise {
        let promise = _Promise(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    try it(v)
                    promise.fulfill(v)
                } catch let e {
                    promise.reject(e)
                }
            }
        }).add(to: &promise.disposes)
        return promise
    }

    @discardableResult
    func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<Result>) -> _Promise<Result> {
        let promise = _Promise<Result>(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    promise.fulfill(try it(v))
                } catch let e {
                    promise.reject(e)
                }
            }
        }).add(to: &promise.disposes)
        return promise
    }

    @discardableResult
    func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<_Promise<Result>>) -> _Promise<Result> {
        let promise = _Promise<Result>(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    let p = try it(v)
                    p.listening({ (event) in
                        switch event {
                        case .error(let e): promise.reject(e)
                        case .value(let v): promise.fulfill(v)
                        }
                    }).add(to: &promise.disposes)
                } catch let e {
                    promise.reject(e)
                }
            }
        }).add(to: &promise.disposes)
        return promise
    }

    func `catch`(on queue: DispatchQueue = .main, make it: @escaping (Error) -> Void) -> _Promise {
        let promise = _Promise(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e):
                it(e)
                promise.reject(e)
            case .value(let v): promise.fulfill(v)
            }
        }).add(to: &promise.disposes)
        return promise
    }
}
extension _Promise: RealtimeTask {
    public var completion: AnyListenable<Void> { return AnyListenable(once().map({ _ in () })) }
}
