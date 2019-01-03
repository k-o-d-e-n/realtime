//
//  view.collection.realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 21/11/2018.
//

import Foundation

public struct RCItem: WritableRealtimeValue, Comparable {
    public var raw: RealtimeDataValue?
    public var payload: [String : RealtimeDataValue]?
    public var node: Node?
    public let dbKey: String!
    var priority: Int?
    var linkID: String?

    init(key: String?, value: RealtimeValue) {
        self.raw = value.raw
        self.payload = value.payload
        self.dbKey = key ?? value.dbKey
    }

    public init(in node: Node?, options: [ValueOption : Any]) {
        self.node = node
        self.dbKey = node?.key
        self.raw = options[.rawValue] as? RealtimeDataValue
        self.payload = options[.userPayload] as? [String: RealtimeDataValue]
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard let key = data.key else {
            throw RealtimeError(initialization: RCItem.self, data)
        }

        let valueData = InternalKeys.value.child(from: data)
        self.dbKey = key
        self.raw = try valueData.rawValue()
        self.linkID = try InternalKeys.link.map(from: data)
        self.priority = try InternalKeys.index.map(from: data)
        self.payload = try InternalKeys.payload.map(from: valueData)
    }

    public func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(try defaultRepresentation(), by: node)
    }

    private func defaultRepresentation() throws -> Any {
        var representation: [String: RealtimeDataValue] = [:]
        representation[InternalKeys.link.rawValue] = linkID
        representation[InternalKeys.index.rawValue] = priority
        var value: [String: RealtimeDataValue] = [:]
        if let p = self.payload {
            value[InternalKeys.payload.rawValue] = p
        }
        if let raw = self.raw {
            value[InternalKeys.raw.rawValue] = raw
        }
        representation[InternalKeys.value.rawValue] = value

        return representation
    }

    public var hashValue: Int { return dbKey.hashValue }
    public static func ==(lhs: RCItem, rhs: RCItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
    public static func < (lhs: RCItem, rhs: RCItem) -> Bool {
        if (lhs.priority ?? 0) < (rhs.priority ?? 0) {
            return true
        } else if (lhs.priority ?? 0) > (rhs.priority ?? 0) {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

public struct RDItem: WritableRealtimeValue, Comparable {
    public var raw: RealtimeDataValue?
    public var payload: [String : RealtimeDataValue]?
    public var node: Node? { return rcItem.node }
    var rcItem: RCItem

    public var dbKey: String! { return rcItem.dbKey }
    var priority: Int? {
        set { rcItem.priority = newValue }
        get { return rcItem.priority }
    }
    var linkID: String? {
        set { rcItem.linkID = newValue }
        get { return rcItem.linkID }
    }

    init(key: RealtimeValue, value: RealtimeValue) {
        self.rcItem = RCItem(key: key.dbKey, value: value)
        self.raw = key.raw
        self.payload = key.payload
    }

    public init(in node: Node?, options: [ValueOption : Any]) {
        self.rcItem = RCItem(in: node, options: options)
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.rcItem = try RCItem(data: data, event: event)
        let keyData = InternalKeys.key.child(from: data)
        self.raw = try keyData.rawValue()
        self.payload = try InternalKeys.payload.map(from: keyData)
    }

    public func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(try defaultRepresentation(), by: node)
    }

    private func defaultRepresentation() throws -> Any {
        var representation: [String: RealtimeDataValue] = [:]
        representation[InternalKeys.link.rawValue] = rcItem.linkID
        representation[InternalKeys.index.rawValue] = rcItem.priority

        var value: [String: RealtimeDataValue] = [:]
        if let p = rcItem.payload {
            value[InternalKeys.payload.rawValue] = p
        }
        if let raw = rcItem.raw {
            value[InternalKeys.raw.rawValue] = raw
        }
        representation[InternalKeys.value.rawValue] = value

        var key: [String: RealtimeDataValue] = [:]
        if let p = self.payload {
            key[InternalKeys.payload.rawValue] = p
        }
        if let raw = self.raw {
            key[InternalKeys.raw.rawValue] = raw
        }
        representation[InternalKeys.key.rawValue] = key

        return representation
    }

    public var hashValue: Int { return dbKey.hashValue }
    public static func ==(lhs: RDItem, rhs: RDItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
    public static func < (lhs: RDItem, rhs: RDItem) -> Bool {
        if (lhs.priority ?? 0) < (rhs.priority ?? 0) {
            return true
        } else if (lhs.priority ?? 0) > (rhs.priority ?? 0) {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

public struct AnyRealtimeCollectionView: RealtimeCollectionView {
    var _value: RealtimeCollectionActions
    let _contains: (String, @escaping (Bool, Error?) -> Void) -> Void
    let _view: AnyBidirectionalCollection<String>

    internal(set) var isSynced: Bool = false

    init<CV: RealtimeCollectionView>(_ view: CV) where CV.Element: DatabaseKeyRepresentable {
        self._value = view
        self._contains = view.contains(elementWith:completion:)
        self._view = AnyBidirectionalCollection(view.lazy.map({ $0.dbKey }))
    }

    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        _contains(key, completion)
    }

    public func load(timeout: DispatchTimeInterval, completion: Closure<Error?, Void>?) {
        _value.load(timeout: timeout, completion: completion)
    }

    public var canObserve: Bool { return _value.canObserve }
    public var keepSynced: Bool {
        set { _value.keepSynced = newValue }
        get { return _value.keepSynced }
    }
    public var isObserved: Bool { return _value.isObserved }
    public func runObserving() -> Bool { return _value.runObserving() }
    public func stopObserving() { _value.stopObserving() }

    public var startIndex: AnyIndex { return _view.startIndex }
    public var endIndex: AnyIndex { return _view.endIndex }
    public func index(after i: AnyIndex) -> AnyIndex { return _view.index(after: i) }
    public func index(before i: AnyIndex) -> AnyIndex { return _view.index(before: i) }
    public subscript(position: AnyIndex) -> String { return _view[position] }
}

extension SortedArray: RealtimeDataRepresented where Element: RealtimeDataRepresented & Comparable {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.init(try data.map(Element.init))
    }
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent, sorting: @escaping SortedArray<Element>.Comparator<Element>) throws {
        self.init(unsorted: try data.map(Element.init), areInIncreasingOrder: sorting)
    }
}

enum ViewDataExplorer {
    case value(ascending: Bool)
    case page(PagingController)
}

public final class SortedCollectionView<Element: WritableRealtimeValue & Comparable>: _RealtimeValue, RealtimeCollectionView {
    typealias Source = SortedArray<Element>
    private var _elements: Source = Source()
    private var dataExplorer: ViewDataExplorer = .value(ascending: false)
    internal(set) var isSynced: Bool = false
    override var _hasChanges: Bool { return isStandalone && _elements.count > 0 }
    public override var isObserved: Bool {
        switch dataExplorer {
        case .value: return super.isObserved
        case .page(let controller): return controller.isStarted
        }
    }

    var elements: Source {
        set { _elements = newValue }
        get { return _elements }
    }

    var changes: Preprocessor<(RealtimeDataProtocol, DatabaseDataEvent), RCEvent> {
        return dataObserver
            .filter({ [unowned self] e in
                if e.1 != .value {
                    switch self.dataExplorer {
                    case .value: return self.isSynced
                    case .page(let controller): return controller.isStarted
                    }
                } else {
                    return true
                }
            })
            .map { [unowned self] (value) -> RCEvent in
                switch value.1 {
                case .value:
                    return .initial
                case .child(.added):
                    let indexes: [Int]
                    if value.0.key == self.node?.key {
                        let elements = try value.0.map(Element.init)
                        self._elements.insert(contentsOf: elements)
                        indexes = elements.compactMap(self._elements.index(of:))
                    } else {
                        let item = try Element(data: value.0)
                        indexes = [self._elements.insert(item)]
                    }
                    return .updated(deleted: [], inserted: indexes, modified: [], moved: [])
                case .child(.removed):
                    let indexes: [Int]
                    if value.0.key == self.node?.key {
                        indexes = try value.0.map(Element.init).compactMap({ self._elements.remove($0)?.index })
                    } else {
                        let item = try Element(data: value.0)
                        indexes = self._elements.remove(item).map({ [$0.index] }) ?? []
                    }
                    if indexes.count == value.0.childrenCount {
                        return .updated(deleted: indexes, inserted: [], modified: [], moved: [])
                    } else {
                        throw RealtimeError(source: .coding, description: "Element has been removed in remote collection, but couldn`t find in local storage.")
                    }
                case .child(.changed):
                    let item = try Element(data: value.0)
                    if let indexes = self._elements.move(item) {
                        if indexes.from != indexes.to {
                            return .updated(deleted: [], inserted: [], modified: [], moved: [indexes])
                        } else {
                            return .updated(deleted: [], inserted: [], modified: [indexes.to], moved: [])
                        }
                    } else {
                        throw RealtimeError(source: .collection, description: "Cannot move items")
                    }
                default:
                    throw RealtimeError(source: .collection, description: "Unexpected data event: \(value)")
                }
            }
    }

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    public required init(in node: Node?, options: [ValueOption: Any]) {
        super.init(in: node, options: options)
    }

    public required convenience init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.init(in: data.node, options: [.database: data.database as Any, .storage: data.storage as Any])
        try apply(data, event: event)
    }

    @discardableResult
    public func runObserving() -> Bool {
        switch dataExplorer {
        case .value:
            let isNeedLoadFull = !isObserved
            let added = _runObserving(.child(.added))
            let removed = _runObserving(.child(.removed))
            let changed = _runObserving(.child(.changed))
            if isNeedLoadFull {
                if isRooted {
                    load(completion: .just { [weak self] e in
                        self.map { this in
                            this.isSynced = this.isObserved && e == nil
                        }
                    })
                } else {
                    isSynced = true
                }
            }
            return added && removed && changed
        case .page(let controller):
            if !controller.isStarted {
                controller.start()
            }
            return controller.isStarted
        }
    }

    public func stopObserving() {
        switch dataExplorer {
        case .value:
            // checks 'added' only, can lead to error
            guard !keepSynced || (observing[.child(.added)].map({ $0.counter > 1 }) ?? true) else {
                return
            }

            _stopObserving(.child(.added))
            _stopObserving(.child(.removed))
            _stopObserving(.child(.changed))
            if !isObserved {
                isSynced = false
            }
        case .page(let controller):
            if controller.isStarted {
                controller.stop()
                isSynced = false
            }
        }
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        let view = _elements
        transaction.addReversion { [weak self] in
            self?._elements = view
        }
        _elements.removeAll()
        for item in view {
            let itemNode = node.child(with: item.dbKey)
            try item.write(to: transaction, by: itemNode)
        }
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        /// partial data processing see in `changes`
        guard event == .value else { return }

        switch dataExplorer {
        case .value(let ascending):
            self._elements = try SortedArray(data: data, event: event, sorting: ascending ? (<) : (>))
        case .page(let c):
            self._elements = try SortedArray(data: data, event: event, sorting: c.ascending ? (<) : (>))
        }
    }

    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        _contains(with: key, completion: completion)
    }

    public var startIndex: Int { return _elements.startIndex }
    public var endIndex: Int { return _elements.endIndex }
    public func index(after i: Int) -> Int { return _elements.index(after: i) }
    public func index(before i: Int) -> Int { return _elements.index(before: i) }
    public subscript(position: Int) -> Element { return _elements[position] }

    func didChange(dataExplorer: RCDataExplorer) {
        switch (dataExplorer, self.dataExplorer) {
        case (.view(let ascending), .page(let controller)):
            self.dataExplorer = .value(ascending: ascending)
            if controller.isStarted {
                controller.stop()
                runObserving()
            }
        case (.viewByPages(let control, let size, let ascending), .value):
            _setPageController(with: control, pageSize: size, ascending: ascending)
        case (.viewByPages(let control, let size, let ascending), .page(let oldController)):
            guard oldController.isStarted else {
                return _setPageController(with: control, pageSize: size, ascending: ascending)
            }
            guard control === oldController, ascending == oldController.ascending else {
                fatalError("In observing state available to change page size only")
            }
            oldController.pageSize = size
        case (.view(let collectionAscending), .value(let viewAscending)):
            if collectionAscending != viewAscending {
                self.dataExplorer = .value(ascending: collectionAscending)
                self._elements = SortedArray.init(unsorted: _elements, areInIncreasingOrder: collectionAscending ? (<) : (>))
            }
        }
    }

    private func _setPageController(with control: PagingControl, pageSize: UInt, ascending: Bool) {
        guard let database = self.database, let node = self.node else { return }
        let controller = PagingController(
            database: database,
            node: node,
            pageSize: pageSize,
            ascending: ascending,
            delegate: self
        )
        control.controller = controller
        self.dataExplorer = .page(controller)
        if super.isObserved {
            _invalidateObserving()
            controller.start()
        }
    }

    @discardableResult
    func insert(_ element: Element) -> Int {
        return _elements.insert(element)
    }

    @discardableResult
    func remove(at index: Int) -> Element {
        return _elements.remove(at: index)
    }

    func removeAll() {
        _elements.removeAll()
    }

    func load(_ completion: Assign<(Error?)>) {
        guard !isSynced else { completion.assign(nil); return }

        super.load(completion: completion)
    }

    func _contains(with key: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let db = database, let node = self.node else {
            fatalError("Unexpected behavior")
        }
        db.load(
            for: node.child(with: key),
            timeout: .seconds(10),
            completion: { (data) in
                completion(data.exists(), nil)
        },
            onCancel: { completion(false, $0) }
        )
    }

    func _item(for key: String, completion: @escaping (Source.Element?, Error?) -> Void) {
        guard let db = database, let node = self.node else {
            fatalError("Unexpected behavior")
        }
        db.load(
            for: node.child(with: key),
            timeout: .seconds(10),
            completion: { (data) in
                if data.exists() {
                    do {
                        completion(try Element(data: data), nil)
                    } catch let e {
                        completion(nil, e)
                    }
                } else {
                    completion(nil, nil)
                }
        },
            onCancel: { completion(nil, $0) }
        )
    }
}
extension SortedCollectionView: PagingControllerDelegate {
    func firstKey() -> String? {
        return first?.dbKey
    }

    func lastKey() -> String? {
        return last?.dbKey
    }

    func pagingControllerDidReceive(data: RealtimeDataProtocol, with event: DatabaseDataEvent) {
        do {
            if event == .value {
                try self.apply(data, event: event)
            }
            self.dataObserver.send(.value((data, event)))
        } catch let e {
            self.dataObserver.send(.error(e))
        }
    }

    func pagingControllerDidCancel(with error: Error) {
        self.dataObserver.send(.error(error))
    }
}