//
//  Observable.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

/// -------------------------------------------------------------------

public struct Promise {
    let action: () -> Void
    let error: (Error) -> Void

    public func fulfill() {
        action()
    }

    public func reject(_ error: Error) {
        self.error(error)
    }
}
public struct ResultPromise<T> {
    let receiver: (T) -> Void
    let error: (Error) -> Void

    public func fulfill(_ result: T) {
        receiver(result)
    }

    public func reject(_ error: Error) {
        self.error(error)
    }
}

public struct Closure<I, O> {
    let closure: (I) -> O
}
public struct ThrowsClosure<I, O> {
    let closure: (I) throws -> O
}
extension ThrowsClosure {
    func map<U>(_ transform: @escaping (U) throws -> I) -> ThrowsClosure<U, O> {
        return ThrowsClosure<U, O>(closure: { try self.closure(try transform($0)) })
    }
    func map<U>(_ transform: @escaping (O) throws -> U) -> ThrowsClosure<I, U> {
        return ThrowsClosure<I, U>(closure: { try transform(try self.closure($0)) })
    }
}
extension Closure {
    func `throws`() -> ThrowsClosure<I, O> {
        return ThrowsClosure(closure: closure)
    }
    func map<U>(_ transform: @escaping (U) -> I) -> Closure<U, O> {
        return Closure<U, O>(closure: { self.closure(transform($0)) })
    }
    func map<U>(_ transform: @escaping (O) -> U) -> Closure<I, U> {
        return Closure<I, U>(closure: { transform(self.closure($0)) })
    }
}

extension Closure where O == Void {
    func filter(_ predicate: @escaping (I) -> Bool) -> Closure<I, O> {
        return Closure<I, O>(closure: { (input) -> O in
            if predicate(input) {
                return self.closure(input)
            }
        })
    }
}

/// Configurable wrapper for closure that receives listening value.
public struct Assign<A> {
    let assign: (A) -> Void

    public func call(_ arg: A) {
        assign(arg)
    }

    /// simple closure without side effects
    static public func just(_ assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: assign)
    }

    /// closure associated with object using weak reference
    static public func weak<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner?) -> Void) -> Assign<A> {
        return Assign(assign: { [weak owner] v in assign(v, owner) })
    }
    

    /// closure associated with object using unowned reference
    static public func unowned<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return Assign(assign: { [unowned owner] v in assign(v, owner) })
    }

    /// closure associated with object using weak reference, that called only when object alive
    static public func guarded<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return weak(owner) { if let o = $1 { assign($0, o) } }
    }

    /// closure that called on specified dispatch queue
    static public func on(_ queue: DispatchQueue, assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign<A>(assign: { v in
            queue.async {
                assign(v)
            }
        })
    }

    /// returns new closure wrapped using queue behavior
    public func on(queue: DispatchQueue) -> Assign<A> {
        return Assign.on(queue, assign: assign)
    }

    public func with(work: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { (v) in
            work(v)
            self.assign(v)
        })
    }
    public func after(work: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { (v) in
            self.assign(v)
            work(v)
        })
    }
    public func with(work: Assign<A>) -> Assign<A> {
        return with(work: work.assign)
    }
    public func after(work: Assign<A>) -> Assign<A> {
        return after(work: work.assign)
    }
    public func with(work: Assign<A>?) -> Assign<A> {
        return work.map(with) ?? self
    }
    public func after(work: Assign<A>?) -> Assign<A> {
        return work.map(after) ?? self
    }

    public func map<U>(_ transform: @escaping (U) -> A) -> Assign<U> {
        return Assign<U>(assign: { (u) in
            self.assign(transform(u))
        })
    }

    public func filter(_ predicate: @escaping (A) -> Bool) -> Assign<A> {
        return Assign(assign: { (a) in
            if predicate(a) {
                self.assign(a)
            }
        })
    }
}

prefix operator <-
public prefix func <-<A>(rhs: Assign<A>) -> (A) -> Void {
    return rhs.assign
}
public prefix func <-<A>(rhs: @escaping (A) -> Void) -> Assign<A> {
    return Assign(assign: rhs)
}

// MARK: Connections

public enum ListenEvent<T> {
    case value(T)
    case error(Error)
}
public extension ListenEvent {
    var value: T? {
        guard case .value(let v) = self else { return nil }
        return v
    }
    var error: Error? {
        guard case .error(let e) = self else { return nil }
        return e
    }
    func map<U>(_ transform: (T) throws -> U) rethrows -> ListenEvent<U> {
        switch self {
        case .value(let v): return .value(try transform(v))
        case .error(let e): return .error(e)
        }
    }
    func flatMap<U>(_ transform: (T) throws -> U) rethrows -> U? {
        switch self {
        case .value(let v): return try transform(v)
        case .error: return nil
        }
    }
    func map(to value: inout T) {
        if let v = self.value {
            value = v
        }
    }
}

/// Common protocol for all objects that ensures listening value. 
public protocol Listenable {
    associatedtype OutData

    /// Disposable listening of value
    func listening(_ assign: Assign<ListenEvent<OutData>>) -> Disposable

    /// Listening with possibility to control active state
    func listeningItem(_ assign: Assign<ListenEvent<OutData>>) -> ListeningItem
}
public extension Listenable {
    func listening(_ assign: @escaping (ListenEvent<OutData>) -> Void) -> Disposable {
        return listening(.just(assign))
    }
    func listeningItem(_ assign: @escaping (ListenEvent<OutData>) -> Void) -> ListeningItem {
        return listeningItem(.just(assign))
    }
    func listening(onValue assign: Assign<OutData>) -> Disposable {
        return listening(Assign(assign: {
            if let v = $0.value {
                assign.assign(v)
            }
        }))
    }
    func listeningItem(onValue assign: Assign<OutData>) -> ListeningItem {
        return listeningItem(Assign(assign: {
            if let v = $0.value {
                assign.assign(v)
            }
        }))
    }
    func listening(onValue assign: @escaping (OutData) -> Void) -> Disposable {
        return listening(onValue: .just(assign))
    }
    func listeningItem(onValue assign: @escaping (OutData) -> Void) -> ListeningItem {
        return listeningItem(onValue: .just(assign))
    }

    func listening(onError assign: Assign<Error>) -> Disposable {
        return listening(Assign(assign: {
            if let v = $0.error {
                assign.assign(v)
            }
        }))
    }
    func listeningItem(onError assign: Assign<Error>) -> ListeningItem {
        return listeningItem(Assign(assign: {
            if let v = $0.error {
                assign.assign(v)
            }
        }))
    }
    func listening(onError assign: @escaping (Error) -> Void) -> Disposable {
        return listening(onError: .just(assign))
    }
    func listeningItem(onError assign: @escaping (Error) -> Void) -> ListeningItem {
        return listeningItem(onError: .just(assign))
    }
}
struct AnyListenable<Out>: Listenable {
    let _listening: (Assign<ListenEvent<Out>>) -> Disposable
    let _listeningItem: (Assign<ListenEvent<Out>>) -> ListeningItem

    init<L: Listenable>(_ base: L) where L.OutData == Out {
        self._listening = base.listening
        self._listeningItem = base.listeningItem
    }
    init(_ listening: @escaping (Assign<ListenEvent<Out>>) -> Disposable,
         _ listeningItem: @escaping (Assign<ListenEvent<Out>>) -> ListeningItem) {
        self._listening = listening
        self._listeningItem = listeningItem
    }

    func listening(_ assign: Assign<ListenEvent<Out>>) -> Disposable {
        return _listening(assign)
    }
    func listeningItem(_ assign: Assign<ListenEvent<Out>>) -> ListeningItem {
        return _listeningItem(assign)
    }
}

/// Provides calculated listening value
public struct ReadonlyProperty<Value>: Listenable {
    let repeater: Repeater<Value>
    private let store: ListeningDisposeStore

    public init<L: Listenable>(_ source: L, repeater: Repeater<Value> = .unsafe(), calculation: @escaping (L.OutData) -> Value) {
        var store = ListeningDisposeStore()
        repeater.depends(on: source.map(calculation)).add(to: &store)
        self.repeater = repeater
        self.store = store
    }

    public func listening(_ assign: Assign<ListenEvent<Value>>) -> Disposable {
        return repeater.listening(assign)
    }
    public func listeningItem(_ assign: Assign<ListenEvent<Value>>) -> ListeningItem {
        return repeater.listeningItem(assign)
    }
}

/// Provides listening value based on async action
public struct AsyncReadonlyProperty<Value>: Listenable {
    let repeater: Repeater<Value>
    private let store: ListeningDisposeStore
    
    public init<L: Listenable>(_ source: L, repeater: Repeater<Value> = .unsafe(), fetching: @escaping (L.OutData, ResultPromise<Value>) -> Void) {
        var store = ListeningDisposeStore()
        repeater.depends(on: source.onReceiveMap(fetching)).add(to: &store)
        self.repeater = repeater
        self.store = store
    }

    public func listening(_ assign: Assign<ListenEvent<Value>>) -> Disposable {
        return repeater.listening(assign)
    }
    public func listeningItem(_ assign: Assign<ListenEvent<Value>>) -> ListeningItem {
        return repeater.listeningItem(assign)
    }
}

/// Common protocol for entities that represents some data
public protocol ValueWrapper {
    associatedtype V
    var value: V { get set }
}

public extension ValueWrapper {
    static func <==(_ prop: inout Self, _ value: V) {
        prop.value = value
    }
    static func <==(_ value: inout V, _ prop: Self) {
        value = prop.value
    }
    static func <==(_ value: inout V?, _ prop: Self) {
        value = prop.value
    }
}
public extension ValueWrapper {
    func mapValue<U>(_ transform: (V) -> U) -> U {
        return transform(value)
    }
}
public extension ValueWrapper where V: _Optional {
    static func <==(_ value: inout V?, _ prop: Self) {
        value = prop.value
    }
    func mapValue<U>(_ transform: (V.Wrapped) -> U) -> U? {
        return value.map(transform)
    }
    func flatMapValue<U>(_ transform: (V.Wrapped) -> U?) -> U? {
        return value.flatMap(transform)
    }
}

public extension Repeater {
    /// Makes notification depending
    ///
    /// - Parameter other: Listenable that will be invoke notifications himself listenings
    /// - Returns: Disposable
    @discardableResult
    func depends<L: Listenable>(on other: L) -> Disposable where L.OutData == T {
        return other.listening(self.send)
    }
}
public extension Listenable {
    /// Binds values new values to value wrapper
    ///
    /// - Parameter other: Value wrapper that will be receive value
    /// - Returns: Disposable
    @discardableResult
    func bind<Other: AnyObject & ValueWrapper>(to other: Other) -> Disposable where Other.V == Self.OutData {
        return livetime(other).listening(onValue: { [weak other] val in
            other?.value = val
        })
    }

    /// Binds events to repeater
    ///
    /// - Parameter other: Repeater that will be receive value
    /// - Returns: Disposable
    @discardableResult
    func bind(to other: Repeater<OutData>) -> Disposable {
        return other.depends(on: self)
    }

    /// Binds events to property
    ///
    /// - Parameter other: Repeater that will be receive value
    /// - Returns: Disposable
    @discardableResult
    func bind(to other: Property<OutData>) -> Disposable {
        return listening({ (e) in
            switch e {
            case .value(let v): other.value = v
            case .error(let e): other.sendError(e)
            }
        })
    }
}
