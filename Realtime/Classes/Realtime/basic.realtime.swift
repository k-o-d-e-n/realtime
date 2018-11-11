//
//  RealtimeBasic.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
import FirebaseDatabase

// #
// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
// Comment writing guide

internal let lazyStoragePath = ".storage"

public struct RealtimeError: LocalizedError {
    let description: String
    public let source: Source

    public var localizedDescription: String { return description }

    init(source: Source, description: String) {
        self.source = source
        self.description = description
    }

    /// Shows part or process of Realtime where error is happened.
    ///
    /// - value: Error from someone class of property
    /// - collection: Error from someone class of collection
    /// - listening: Error from Listenable part
    /// - coding: Error on coding process
    /// - transaction: Error in `Transaction`
    /// - cache: Error in cache
    public enum Source {
        case value
        case file
        case collection

        case listening
        case coding
        case transaction([Error])
        case cache
    }

    init<T>(initialization type: T.Type, _ data: Any) {
        self.init(source: .coding, description: "Failed initialization type: \(T.self) with data: \(data)")
    }
    init<T>(decoding type: T.Type, _ data: Any, reason: String) {
        self.init(source: .coding, description: "Failed decoding data: \(data) to type: \(T.self). Reason: \(reason)")
    }
    init<T>(encoding value: T, reason: String) {
        self.init(source: .coding, description: "Failed encoding value of type: \(value). Reason: \(reason)")
    }
}

/// A type that contains key of database node
public protocol DatabaseKeyRepresentable {
    var dbKey: String! { get }
}

// MARK: RealtimeValue

public typealias SystemPayload = (version: Int?, raw: RealtimeDataValue?)

/// Key of RealtimeValue option
public struct ValueOption: Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
public extension ValueOption {
    /// Key for `RealtimeDatabase` instance
    static let database: ValueOption = ValueOption("realtime.database")
    /// Key for `[String : RealtimeDataValue]?` value
    static let userPayload: ValueOption = ValueOption("realtime.value.userPayload")
    /// Key for `SystemPayload` value
    static let systemPayload: ValueOption = ValueOption("realtime.value.systemPayload")
}
public extension Dictionary where Key == ValueOption {
    var version: Int? {
        return (self[.systemPayload] as? SystemPayload)?.version
    }
    var rawValue: RealtimeDataValue? {
        return (self[.systemPayload] as? SystemPayload)?.raw
    }
}
public extension RealtimeDataProtocol {
    func version() throws -> Int? {
        return try InternalKeys.modelVersion.map(from: self)
    }
    func rawValue() throws -> RealtimeDataValue? {
        return try InternalKeys.raw.map(from: self)
    }
}

/// Internal protocol
public protocol _RealtimeValueUtilities {
    static func _isValid(asReference value: Self) -> Bool
    static func _isValid(asRelation value: Self) -> Bool
}
extension _RealtimeValueUtilities where Self: _RealtimeValue {
    public static func _isValid(asReference value: Self) -> Bool {
        return value.isRooted
    }
    public static func _isValid(asRelation value: Self) -> Bool {
        return value.isRooted
    }
}
extension _RealtimeValue: _RealtimeValueUtilities {}

/// Base protocol for all database entities
public protocol RealtimeValue: DatabaseKeyRepresentable, RealtimeDataRepresented {
    /// Current version of value.
    var version: Int? { get }
    /// Indicates specific representation of this value, e.g. subclass or enum associated value
    var raw: RealtimeDataValue? { get }
    /// Some data associated with value
    var payload: [String: RealtimeDataValue]? { get }
    /// Node location in database
    var node: Node? { get }

    /// Creates new instance associated with database node
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    init(in node: Node?, options: [ValueOption: Any])
}
extension RealtimeValue {
    internal var systemPayload: SystemPayload {
        return (version, raw)
    }
}

extension Optional: RealtimeValue, DatabaseKeyRepresentable, _RealtimeValueUtilities where Wrapped: RealtimeValue {
    public var version: Int? { return self?.version }
    public var raw: RealtimeDataValue? { return self?.raw }
    public var payload: [String : RealtimeDataValue]? { return self?.payload }
    public var node: Node? { return self?.node }
    public init(in node: Node?, options: [ValueOption : Any]) {
        self = .some(Wrapped(in: node, options: options))
    }
    public mutating func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try self?.apply(data, exactly: exactly)
    }

    public static func _isValid(asReference value: Optional<Wrapped>) -> Bool {
        return value.map { $0.isRooted } ?? true
    }
    public static func _isValid(asRelation value: Optional<Wrapped>) -> Bool {
        return value.map { $0.isRooted } ?? true
    }
}
extension Optional: RealtimeDataRepresented where Wrapped: RealtimeDataRepresented {
    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        if data.exists() {
            self = .some(try Wrapped(data: data, exactly: exactly))
        } else {
            self = .none
        }
    }
}

public extension RealtimeValue {
    var dbKey: String! { return node?.key }

    /// Equals `isRooted`
    var isInserted: Bool { return isRooted }
    /// Indicates that value has no rooted node
    var isStandalone: Bool { return !isRooted }
    /// Indicates that value has parent node
    var isReferred: Bool { return node?.parent != nil }
    /// Indicates that value has rooted node
    var isRooted: Bool { return node?.isRooted ?? false }

    internal mutating func apply(parentDataIfNeeded parent: RealtimeDataProtocol, exactly: Bool) throws {
        guard exactly || dbKey.has(in: parent) else { return }

        /// if data has the data associated with current value,
        /// then data is full and we must pass `true` to `exactly` parameter.
        try apply(dbKey.child(from: parent), exactly: true)
    }
}

public extension Hashable where Self: RealtimeValue {
    var hashValue: Int { return dbKey.hashValue }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.node == rhs.node
    }
}

// MARK: Extended Realtime Value

/// A type that makes possible to do someone actions related with value
public protocol RealtimeValueActions: RealtimeValueEvents {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(completion: Assign<Error?>?)
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    var canObserve: Bool { get }
    /// Enables/disables auto downloading of the data and keeping in sync
    var keepSynced: Bool { get set }
    /// Runs or keeps observing value.
    ///
    /// If observing already run, value remembers each next call of function
    /// as requirement to keep observing while is not called `stopObserving()`.
    /// The call of function must be balanced with `stopObserving()` function.
    ///
    /// - Returns: True if running was successful or observing already run, otherwise false
    @discardableResult func runObserving() -> Bool
    /// Stops observing, if observers no more, else decreases the observers counter.
    func stopObserving()
}
/// A type that can receive Realtime database events
public protocol RealtimeValueEvents {
    /// Must call always before save(update) action
    ///
    /// - Parameters:
    ///   - transaction: Save transaction
    ///   - parent: Parent node to save
    ///   - key: Location in parent node
    func willSave(in transaction: Transaction, in parent: Node, by key: String)
    /// Notifies object that it has been saved in specified parent node
    ///
    /// - Parameter parent: Parent node
    /// - Parameter key: Location in parent node
    func didSave(in database: RealtimeDatabase, in parent: Node, by key: String)
    /// Must call always before removing action
    ///
    /// - Parameters:
    ///   - transaction: Remove transaction
    ///   - ancestor: Ancestor where remove action called
    func willRemove(in transaction: Transaction, from ancestor: Node)
    /// Notifies object that it has been removed from specified ancestor node
    ///
    /// - Parameter ancestor: Ancestor node
    func didRemove(from ancestor: Node)
}
extension RealtimeValueEvents where Self: RealtimeValue {
    func willSave(in transaction: Transaction, in parent: Node) {
        guard let node = self.node else {
            return debugFatalError("Unkeyed value will be saved to undefined location in parent node: \(parent.rootPath)")
        }
        willSave(in: transaction, in: parent, by: node.key)
    }
    func didSave(in database: RealtimeDatabase, in parent: Node) {
        if let node = self.node {
            didSave(in: database, in: parent, by: node.key)
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }
    func didSave(in database: RealtimeDatabase) {
        if let parent = node?.parent, let node = self.node {
            didSave(in: database, in: parent, by: node.key)
        } else {
            debugFatalError("Rootless value has been saved to undefined location")
        }
    }
    func willRemove(in transaction: Transaction) {
        if let parent = node?.parent {
            willRemove(in: transaction, from: parent)
        } else {
            debugFatalError("Rootless value will be removed from itself location")
        }
    }
    func didRemove() {
        if let parent = node?.parent {
            didRemove(from: parent)
        } else {
            debugFatalError("Rootless value has been removed from itself location")
        }
    }
}

/// Values that can writes as single values
public protocol WritableRealtimeValue: RealtimeValue {
    /// Writes all local stored data to transaction as is. You shouldn't call it directly.
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Database node where data will be store
    func write(to transaction: Transaction, by node: Node) throws
}

/// Values that can be changed partially
public protocol ChangeableRealtimeValue: RealtimeValue {
    /// Indicates that value was changed
    var hasChanges: Bool { get }

    /// Writes all changes of value to passed transaction
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Node for this value
    func writeChanges(to transaction: Transaction, by node: Node) throws
}
