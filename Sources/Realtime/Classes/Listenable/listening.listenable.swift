//
//  Listening.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
#if os(Linux)
import Atomics

extension AtomicBool {
    var isTrue: Bool {
        mutating get { return value }
    }

    mutating func swapAndResult() -> Bool {
        guard !load() else { return false }
        store(true)
        return true
    }

    static func initialize(_ value: Bool) -> AtomicBool {
        var value = AtomicBool()
        value.initialize(false)
        return value
    }
}

#else
struct AtomicBool {
    var _invalidated: Int32

    private init(_ value: Bool) {
        self._invalidated = value ? 1 : 0
    }

    static func initialize(_ value: Bool) -> AtomicBool {
        return AtomicBool(value)
    }

    var isTrue: Bool { return _invalidated == 1 }

    mutating func swapAndResult() -> Bool {
        return OSAtomicCompareAndSwap32Barrier(0, 1, &_invalidated)
    }
}
#endif

// MARK: Cancellable listenings

/// Disposes existing connection
public protocol Disposable {
    func dispose()
}

public struct EmptyDispose: Disposable {
    public init() {}
    public func dispose() {}
}

public final class SingleRetainDispose: Disposable {
    var retained: AnyObject?
    public init(_ value: AnyObject) { self.retained = value }
    public func dispose() { self.retained = nil }
}

public final class ListeningDispose: Disposable {
    let _dispose: () -> Void
    var invalidated: AtomicBool = AtomicBool.initialize(false)
    public var isDisposed: Bool { return invalidated.isTrue }
    public init(_ dispose: @escaping () -> Void) {
        self._dispose = dispose
    }
    public func dispose() {
        if invalidated.swapAndResult() {
            _dispose()
        }
    }
    deinit {
        dispose()
    }
}
extension ListeningDispose {
    convenience init(_ base: Disposable) {
        self.init(base.dispose)
    }
}

/// Listening with possibility to control connection state
public final class ListeningItem {
    private let _resume: () -> Void
    private let _pause: () -> Void
    private let _dispose: () -> Void
    private let _isListen: () -> Bool

    public var isListen: Bool { return _isListen() }
    var invalidated: AtomicBool = AtomicBool.initialize(false)
    public var isDisposed: Bool { return invalidated.isTrue }

    public init<Token>(resume: @escaping () -> Token?, pause: @escaping (Token) -> Void, dispose: (() -> Void)? = nil, token: Token?) {
        var tkn = token
        self._isListen = { tkn != nil }
        self._resume = {
            guard tkn == nil else { return }
            tkn = resume()
        }
        let _pause = {
            guard let token = tkn else { return }
            pause(token)
            tkn = nil
        }
        self._pause = _pause
        self._dispose = dispose ?? _pause
    }

    init(base: ListeningItem) {
        self._isListen = base._isListen
        self._resume = base._resume
        self._pause = base._pause
        self._dispose = base._dispose
    }

    public func resume() {
        if !isListen {
            _resume()
        }
    }

    public func pause() {
        _pause()
    }

    deinit {
        dispose()
    }
}
extension ListeningItem: Disposable {
    public func dispose() {
        if invalidated.swapAndResult() {
            if isListen {
                _pause()
            }
            _dispose()
        }
    }
}

public extension ListeningItem {
    func add(to store: ListeningDisposeStore) {
        store.add(self)
    }
}

public extension Disposable {
    func add(to store: ListeningDisposeStore) {
        store.add(self)
    }
    func add(to disposes: inout [Disposable]) {
        disposes.append(self)
    }
}

/// Stores connections
public final class ListeningDisposeStore: Disposable, CustomStringConvertible {
    private var disposes = [Disposable]()
    private var listeningItems = [ListeningItem]()

    var isEmpty: Bool { return listeningItems.isEmpty && disposes.isEmpty }

    public init() {}

    deinit {
        dispose()
    }

    public func add(_ stop: Disposable) {
        disposes.append(stop)
    }

    public func add(_ item: ListeningItem) {
        listeningItems.append(item)
    }

    public func disposeDisposes() {
        disposes.forEach { $0.dispose() }
        disposes.removeAll()
    }
    public func disposeItems() {
        listeningItems.forEach { $0.dispose() }
        listeningItems.removeAll()
    }

    public func dispose() {
        disposeDisposes()
        disposeItems()
    }

    public func pause() {
        listeningItems.forEach { $0.pause() }
    }

    public func resume() {
        listeningItems.forEach { $0.resume() }
    }

    public var description: String {
        return """
        items: \(listeningItems.count),
        disposes: \(disposes.count)
        """
    }
}
