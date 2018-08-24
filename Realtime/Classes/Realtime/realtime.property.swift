//
//  RealtimeProperty.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where Self.RawValue == String {
    internal func property<T>(from node: Node?, representer: Representer<T>) -> RealtimeProperty<T> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), representer: representer)
    }
    internal func property<T>(from node: Node?, representer: Representer<T>) -> RealtimeProperty<T?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), representer: representer)
    }

    func readonlyProperty<T: FireDataValue>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyRealtimeProperty<T> {
        return ReadonlyRealtimeProperty(in: Node(key: rawValue, parent: node), representer: representer)
    }
    func readonlyProperty<T: FireDataValue>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyRealtimeProperty<T?> {
        return ReadonlyRealtimeProperty(in: Node(key: rawValue, parent: node), representer: representer)
    }
    func property<T: FireDataValue>(from node: Node?) -> RealtimeProperty<T> {
        return property(from: node, representer: .any)
    }
    func property<T: FireDataValue>(from node: Node?) -> RealtimeProperty<T?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), representer: .any)
    }

    func `enum`<V: RawRepresentable>(from node: Node?, rawRepresenter: Representer<V.RawValue> = .any) -> RealtimeProperty<V> {
        return property(from: node, representer: Representer<V>.default(rawRepresenter))
    }
    func `enum`<V: RawRepresentable>(from node: Node?, rawRepresenter: Representer<V.RawValue> = .any) -> RealtimeProperty<V?> {
        return property(from: node, representer: Representer<V>.default(rawRepresenter))
    }
    func date(from node: Node?, strategy: DateCodingStrategy = .secondsSince1970) -> RealtimeProperty<Date> {
        return property(from: node, representer: Representer<Date>.date(strategy))
    }
    func date(from node: Node?, strategy: DateCodingStrategy = .secondsSince1970) -> RealtimeProperty<Date?> {
        return property(from: node, representer: Representer<Date>.date(strategy))
    }
    func url(from node: Node?) -> RealtimeProperty<URL> {
        return property(from: node, representer: Representer<URL>.default)
    }
    func url(from node: Node?) -> RealtimeProperty<URL?> {
        return property(from: node, representer: Representer<URL>.default)
    }
    func codable<V: Codable>(from node: Node?) -> RealtimeProperty<V> {
        return property(from: node, representer: Representer<V>.json)
    }
    func optionalCodable<V: Codable>(from node: Node?) -> RealtimeProperty<V?> {
        return property(from: node, representer: Representer<V>.json)
    }

    func reference<V: RealtimeObject>(from node: Node?, mode: ReferenceMode) -> RealtimeReference<V> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), mode: .required(mode))
    }
    func reference<V: RealtimeObject>(from node: Node?, mode: ReferenceMode) -> RealtimeReference<V?> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), mode: .optional(mode))
    }
    func relation<V: RealtimeObject>(from node: Node?, rootLevelsUp: Int? = nil, ownerLevelsUp: Int = 1, _ property: RelationMode) -> RealtimeRelation<V> {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                config: .required(rootLevelsUp: rootLevelsUp, ownerLevelsUp: ownerLevelsUp, property: property))
    }
    func relation<V: RealtimeObject>(from node: Node?, rootLevelsUp: Int? = nil, ownerLevelsUp: Int = 1, _ property: RelationMode) -> RealtimeRelation<V?> {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                config: .optional(rootLevelsUp: rootLevelsUp, ownerLevelsUp: ownerLevelsUp, property: property))
    }

    func nested<Type: RealtimeObject>(in object: RealtimeObject) -> Type {
        let property = Type(in: Node(key: rawValue, parent: object.node))
        property.parent = object
        return property
    }
}

public extension RealtimeValueOption {
    static let relation = RealtimeValueOption("realtime.relation")
    static let reference = RealtimeValueOption("realtime.reference")
}

public final class RealtimeReference<Referenced: RealtimeValue>: RealtimeProperty<Referenced> {
    public override var version: Int? { return super._version }
    public override var raw: FireDataValue? { return super._raw }
    public override var payload: [String : FireDataValue]? { return super._payload }

    public convenience init(in node: Node?, mode: Mode) {
        self.init(in: node, options: [.reference: mode])
    }

    public required init(in node: Node?, options: [RealtimeValueOption : Any]) {
        guard case let o as Mode = options[.reference] else { fatalError("Skipped required options") }
        super.init(in: node, options: [.representer: o.representer])
    }

    @discardableResult
    public override func setValue(_ value: Referenced, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard value.isRooted else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        try super._write(to: transaction, by: node)
    }

    public struct Mode {
        let representer: Representer<Referenced?>

        public static func required(_ mode: ReferenceMode) -> Mode {
            return Mode(representer: Representer.reference(mode).requiredProperty())
        }

        public static func optional<U: RealtimeValue>(_ mode: ReferenceMode) -> Mode where Referenced == Optional<U> {
            return Mode(representer: Representer.reference(mode).optionalProperty())
        }
    }
}

public final class RealtimeRelation<Related: RealtimeValue>: RealtimeProperty<Related> {
    var options: Options
    public override var version: Int? { return super._version }
    public override var raw: FireDataValue? { return super._raw }
    public override var payload: [String : FireDataValue]? { return super._payload }

    public convenience init(in node: Node?, config: Options) {
        self.init(in: node, options: [.relation: config])
    }

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard let node = node else { fatalError() }
        guard case let relation as RealtimeRelation<Related>.Options = options[.relation] else { fatalError("Skipped required options") }

        self.options = relation
        super.init(in: node, options: [.representer: relation.representer])
    }

    @discardableResult
    public override func setValue(_ value: Related, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard value.isRooted else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        guard let node = self.node, node.isRooted else {
            fatalError("Cannot get node")
        }
        removeOldValueIfExists(in: transaction, by: node)
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        if let ownerNode = node.ancestor(onLevelUp: options.ownerLevelsUp) {
            options.ownerNode.value = ownerNode
            try super._write(to: transaction, by: node)
            if let backwardValueNode = wrapped?.node {
                let backwardPropertyNode = backwardValueNode.child(with: options.property.path(for: ownerNode))
                let thisProperty = node.path(from: ownerNode)
                let backwardRelation = Relation(path: options.rootLevelsUp.map(ownerNode.path) ?? ownerNode.rootPath, property: thisProperty)
                transaction.addValue(backwardRelation.fireValue, by: backwardPropertyNode)
            }
        } else {
            throw RealtimeError(source: .value, description: "Cannot get owner node from levels up: \(options.ownerLevelsUp)")
        }
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        if hasChanges {
            try _write(to: transaction, by: node)
            removeOldValueIfExists(in: transaction, by: node)
        }
    }

    public override func apply(_ data: FireDataProtocol, exactly: Bool) throws {
        _apply_RealtimeValue(data, exactly: exactly)
        try super.apply(data, exactly: exactly)
    }

    private func removeOldValueIfExists(in transaction: RealtimeTransaction, by node: Node) {
        transaction.addPrecondition { [unowned transaction] (promise) in
            node.reference().observeSingleEvent(of: .value, with: { (data) in
                guard data.exists() else { return promise.fulfill() }
                do {
                    let relation = try Relation(fireData: data)
                    transaction.removeValue(by: Node.root.child(with: relation.targetPath).child(with: relation.relatedProperty))
                    promise.fulfill()
                } catch let e {
                    promise.reject(e)
                }
            }, withCancel: promise.reject)
        }
    }

    public struct Options {
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: Int
        /// String path from related object to his relation property
        let property: RelationMode
        /// Levels up by hierarchy to the same node for both related values. Default nil, that means root node
        let rootLevelsUp: Int?

        let ownerNode: Property<Node?>
        let representer: Representer<Related?>

        public static func required(rootLevelsUp: Int?, ownerLevelsUp: Int, property: RelationMode) -> Options {
            let ownerNode = Property<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                representer: Representer.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode).requiredProperty()
            )
        }

        public static func optional<U>(rootLevelsUp: Int?, ownerLevelsUp: Int, property: RelationMode) -> Options where Related == Optional<U> {
            let ownerNode = Property<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                representer: Representer.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode).optionalProperty()
            )
        }
    }
}

// MARK: Listenable realtime property

public extension RealtimeValueOption {
    static let representer: RealtimeValueOption = RealtimeValueOption("realtime.property.representer")
    static let initialValue: RealtimeValueOption = RealtimeValueOption("realtime.property.initialValue")
}

public extension _RealtimeValue {
    public enum State<T> {
        case local(T)
        case remote(T, exact: Bool)
        case removed
        indirect case error(Error, last: State<T>?)
        //    case reverted(ListenValue<T>?)
    }
}
extension _RealtimeValue.State: _Optional {
    public func map<U>(_ f: (T) throws -> U) rethrows -> U? {
        return try wrapped.map(f)
    }

    public func flatMap<U>(_ f: (T) throws -> U?) rethrows -> U? {
        return try wrapped.flatMap(f)
    }

    public var unsafelyUnwrapped: T {
        return wrapped!
    }

    public var wrapped: T? {
        switch self {
        case .removed: return nil
        case .local(let v): return v
        case .remote(let v, _): return v
        case .error(_, let v): return v?.wrapped
        }
    }

    public typealias Wrapped = T

    public init(nilLiteral: ()) {
        self = .removed
    }
}

public extension _RealtimeValue.State where T: _Optional {
    var wrapped: T.Wrapped? {
        switch self {
        case .removed: return nil
        case .local(let v): return v.wrapped
        case .remote(let v, _): return v.wrapped
        case .error(_, let v): return v?.wrapped
        }
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: _RealtimeValue.State<T>) {
        value = prop.wrapped
    }
}

infix operator =?
infix operator =!
public extension _RealtimeValue.State {
    static func ?? (optional: _RealtimeValue.State<T>, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: _RealtimeValue.State<T>, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func =?(_ value: inout T, _ prop: _RealtimeValue.State<T>) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func =?(_ value: inout T?, _ prop: _RealtimeValue.State<T>) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func <==(_ value: inout T?, _ prop: _RealtimeValue.State<T>) {
        value = prop.wrapped
    }
    static func =!(_ value: inout T, _ prop: _RealtimeValue.State<T>) {
        value = prop.wrapped!
    }
}

public class RealtimeProperty<T>: ReadonlyRealtimeProperty<T>, ChangeableRealtimeValue, WritableRealtimeValue, Reverting {
    fileprivate var oldValue: State<T>?
    internal var _changedValue: T? {
        switch _value {
        case .none: return nil
        case .some(.local(let v)): return v
        case .some(.remote), .some(.error), .some(.removed): return nil
        }
    }
    override var _hasChanges: Bool { return _changedValue != nil }

    public func revert() {
        guard hasChanges else { return }

        _value = oldValue
    }
    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }

    @discardableResult
    public func setValue(_ value: T, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard let node = self.node, node.isRooted else { fatalError("Mutation cannot be do. Value is not rooted") }

        _setLocalValue(value)
        let transaction = transaction ?? RealtimeTransaction()
        try _writeChanges(to: transaction, by: node)
        return transaction
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        if let changed = _changedValue {
//            super._writeChanges(to: transaction, by: node)
            transaction.addReversion(currentReversion())
            transaction._addValue(updateType, try representer.encode(changed), by: node)
        }
    }

    /// Property does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
//        super._write(to: transaction, by: node)
        switch _value {
        case .none:
            /// throws error if property required
            /// does not add to transaction with consideration about empty node to save operation
            /// otherwise need to use update operation
            _ = try representer.encode(nil)
        case .some(.local(let v)): transaction._addValue(updateType, try representer.encode(v), by: node)
        default:
            debugFatalError("Unexpected behavior")
            throw RealtimeError(encoding: T.self, reason: "Unexpected state for current operation")
        }
    }

    internal func _setLocalValue(_ value: T) {
        if !hasChanges {
            oldValue = _value
        }
        _setValue(.local(value))
    }
}

infix operator <==: AssignmentPrecedence
public extension RealtimeProperty {
    static func <== (_ prop: RealtimeProperty, _ value: @autoclosure () throws -> T) rethrows {
        prop._setLocalValue(try value())
    }
}

@available(*, introduced: 0.4.3)
public class ReadonlyRealtimeProperty<T>: _RealtimeValue {
    fileprivate var _value: State<T>?
    fileprivate let repeater: Repeater<State<T>> = Repeater.unsafe()
    fileprivate(set) var representer: Representer<T?>

    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }

    internal var _version: Int? { return super.version }
    internal var _raw: FireDataValue? { return super.raw }
    internal var _payload: [String : FireDataValue]? { return super.payload }
    
    // MARK: Initializers, deinitializer

    public convenience init<U>(in node: Node?, representer: Representer<U>) {
        self.init(in: node, options: [.representer: representer.requiredProperty()])
    }

    public convenience init<U>(in node: Node?, representer: Representer<U>) where Optional<U> == T {
        self.init(in: node, options: [.representer: representer.optionalProperty()])
    }
    
    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard case let representer as Representer<T?> = options[.representer] else { fatalError("Bad options") }

        self._value = (options[.initialValue] as? T).map { .local($0) }
        self.representer = representer
        super.init(in: node, options: options)
    }
    
    public override func load(completion: Assign<Error?>?) {
        super.load(
            completion: Assign.just({ (err) in
                if let e = err {
                    switch e {
                    case _ as RealtimeError: break
                    default: self._setError(e)
                    }
                }
            })
            .with(work: completion)
        )
    }

    @discardableResult
    public func loadValue(completion: Assign<T>, fail: Assign<Error>) -> Self {
        let failing = fail.with { (e) in
            switch e {
            case _ as RealtimeError: break
            default: self._setError(e)
            }
        }
        super.load(completion: .just { err in
            if let e = err {
                failing.assign(e)
            } else if let v = self._value {
                switch v {
                case .error(let e, last: _): fail.assign(e)
                case .remote(let v, _): completion.assign(v)
                default: failing.assign(RealtimeError(source: .value, description: "Undefined error in \(self)"))
                }
            } else {
                failing.assign(RealtimeError(source: .value, description: "Undefined error in \(self)"))
            }
        })

        return self
    }

    internal var updateType: ValueNode.Type { return ValueNode.self }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        /// readonly property cannot have changes
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        /// readonly property cannot write something
    }
    
    // MARK: Events
    
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        switch _value {
        case .some(.local(let v)):
            _setValue(.remote(v, exact: true))
        case .none:
            debugFatalError("Property has been saved but value does not exists")
        default:
            debugFatalError("Property has been saved using does not local value")
        }
    }
    
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _setRemoved()
    }
    
    // MARK: Changeable

    public convenience required init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        try apply(fireData, exactly: true)
    }

    override public func apply(_ data: FireDataProtocol, exactly: Bool) throws {
//        super.apply(data, exactly: exactly)
        do {
            if let value = try representer.decode(data) {
                _setValue(.remote(value, exact: exactly))
            } else {
                _setRemoved()
            }
        } catch let e {
            _setError(e)
            throw e
        }
    }

    internal func _setValue(_ value: State<T>) {
        _value = value
        repeater.send(.value(value))
    }

    func _setRemoved() {
        _value = nil
        repeater.send(.value(.removed))
    }

    internal func _setError(_ error: Error) {
        _value = .error(error, last: _value)
        repeater.send(.error(error))
    }

    public override var debugDescription: String {
        return """
        {
            ref: \(node?.debugDescription ?? "not referred")
            value: \(_value as Any)
        }
        """
    }
}
extension ReadonlyRealtimeProperty: Listenable {
    public func listening(_ assign: Assign<ListenEvent<State<T>>>) -> Disposable {
        return repeater.listening(assign)
    }
}
public extension ReadonlyRealtimeProperty {
    var lastEvent: State<T>? {
        return _value
    }

    var wrapped: T? {
        return _value?.wrapped
    }
}
public extension ReadonlyRealtimeProperty {
    public func then(_ f: (T) -> Void, else e: (() -> Void)? = nil) -> ReadonlyRealtimeProperty {
        if let v = wrapped {
            f(v)
        } else {
            e?()
        }
        return self
    }
    public func `else`(_ f: () -> Void) {
        if nil == wrapped {
            f()
        }
    }
}
public extension ReadonlyRealtimeProperty {
    static func ?? (optional: ReadonlyRealtimeProperty, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: ReadonlyRealtimeProperty, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func =?(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func <==(_ value: inout T?, _ prop: ReadonlyRealtimeProperty) {
        value = prop.wrapped
    }
}
func <== <T>(_ value: inout T?, _ prop: ReadonlyRealtimeProperty<T>?) {
    value = prop?.wrapped
}
public extension ReadonlyRealtimeProperty {
    func mapValue<U>(_ transform: (T) throws -> U) rethrows -> U? {
        return try wrapped.map(transform)
    }
    func flatMapValue<U>(_ transform: (T) throws -> U?) rethrows -> U? {
        return try wrapped.flatMap(transform)
    }
}
public extension ReadonlyRealtimeProperty where T: _Optional {
    var unwrapped: T.Wrapped? {
        return _value.flatMap { $0.wrapped }
    }
    static func ?? (optional: T.Wrapped?, property: ReadonlyRealtimeProperty<T>) -> T.Wrapped? {
        return optional ?? property.unwrapped
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: ReadonlyRealtimeProperty) {
        value = prop.unwrapped
    }
    public func then(_ f: (T.Wrapped) -> Void, else e: (() -> Void)? = nil) -> ReadonlyRealtimeProperty {
        if let v = unwrapped {
            f(v)
        } else {
            e?()
        }
        return self
    }
    public func `else`(_ f: () -> Void) {
        if nil == wrapped {
            f()
        }
    }
}
func <== <T>(_ value: inout T.Wrapped?, _ prop: ReadonlyRealtimeProperty<T>?) where T: _Optional {
    value = prop?.unwrapped
}
public extension ReadonlyRealtimeProperty where T: HasDefaultLiteral {
    static func <==(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        value = prop.wrapped ?? T()
    }
}
public extension ReadonlyRealtimeProperty where T: _Optional, T.Wrapped: HasDefaultLiteral {
    static func <==(_ value: inout T.Wrapped, _ prop: ReadonlyRealtimeProperty) {
        value = prop.unwrapped ?? T.Wrapped()
    }
}
infix operator ====: ComparisonPrecedence
infix operator !===: ComparisonPrecedence
public extension ReadonlyRealtimeProperty where T: Equatable {
    static func ====(lhs: T, rhs: ReadonlyRealtimeProperty) -> Bool {
        return rhs.wrapped == lhs
    }
    static func ====(lhs: ReadonlyRealtimeProperty, rhs: T) -> Bool {
        return lhs.wrapped == rhs
    }
    static func ====(lhs: ReadonlyRealtimeProperty, rhs: ReadonlyRealtimeProperty) -> Bool {
        return rhs.wrapped == lhs.wrapped
    }
    static func !===(lhs: T, rhs: ReadonlyRealtimeProperty) -> Bool {
        return !(lhs ==== rhs)
    }
    static func !===(lhs: ReadonlyRealtimeProperty, rhs: T) -> Bool {
        return !(lhs ==== rhs)
    }
    static func !===(lhs: ReadonlyRealtimeProperty, rhs: ReadonlyRealtimeProperty) -> Bool {
        return !(lhs ==== rhs)
    }
    static func ====(lhs: T?, rhs: ReadonlyRealtimeProperty) -> Bool {
        return rhs.wrapped == lhs
    }
    static func ====(lhs: ReadonlyRealtimeProperty, rhs: T?) -> Bool {
        return lhs.wrapped == rhs
    }
    static func !===(lhs: T?, rhs: ReadonlyRealtimeProperty) -> Bool {
        return !(lhs ==== rhs)
    }
    static func !===(lhs: ReadonlyRealtimeProperty, rhs: T?) -> Bool {
        return !(lhs ==== rhs)
    }
}
public extension ReadonlyRealtimeProperty where T: HasDefaultLiteral & _ComparableWithDefaultLiteral {
    static func <==(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        value = prop.wrapped ?? T()
    }
    func defaultOnEmpty() -> Self {
        self.representer = Representer(defaultOnEmpty: representer)
        return self
    }
}

// TODO: Reconsider usage it. Some RealtimeValue things are not need here.
public final class SharedProperty<T>: _RealtimeValue where T: FireDataValue & HasDefaultLiteral {
    private var _value: T
    public var value: T { return _value }
    let repeater: Repeater<T> = Repeater.unsafe()
    let representer: Representer<T> = .any

    // MARK: Initializers, deinitializer

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        self._value = T()
        super.init(in: node, options: options)
    }

    // MARK: Events

    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
    }

    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        setValue(T())
    }

    // MARK: Changeable

    public convenience required init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        try apply(fireData, exactly: true)
    }

    override public func apply(_ data: FireDataProtocol, exactly: Bool) throws {
        try super.apply(data, exactly: exactly)
        setValue(try representer.decode(data))
    }

    fileprivate func setValue(_ value: T) {
        self._value = value
        repeater.send(.value(value))
    }
}
extension SharedProperty: Listenable {
    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listening(assign)
    }
}

public extension SharedProperty {
    public func changeValue(use changing: @escaping (T) throws -> T, completion: ((Bool, T) -> Void)? = nil) {
        guard let ref = dbRef else  {
            fatalError("Can`t get database reference")
        }
        ref.runTransactionBlock({ data in
            do {
                let dataValue = data.exists() ? try T.init(fireData: data) : T()
                data.value = try changing(dataValue)
            } catch let e {
                debugFatalError(e.localizedDescription)

                return .abort()
            }
            return .success(withValue: data)
        }, andCompletionBlock: { [unowned self] error, commited, snapshot in
            guard error == nil else {
                completion?(false, self.value)
                return
            }

            if let s = snapshot {
                do {
                    self.setValue(try self.representer.decode(s))
                    completion?(true, self.value)
                } catch {
                    completion?(false, self.value)
                }
            } else {
                debugFatalError("Transaction completed without error, but snapshot does not exist")

                completion?(false, self.value)
            }
        })
    }
}

public final class MutationPoint<T> {
    public let node: Node
    public required init(in node: Node) {
        guard node.isRooted else { fatalError("Node must be rooted") }
        self.node = node
    }
}
public extension MutationPoint where T: FireDataRepresented & FireDataValueRepresented {
    func set(value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value.fireValue, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value.fireValue, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
public extension MutationPoint where T: FireDataValue {
    func set(value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
extension MutationPoint {
    func removeValue(for key: String, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.removeValue(by: node.child(with: key))

        return transaction
    }
}
