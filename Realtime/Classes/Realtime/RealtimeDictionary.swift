//
//  RealtimeDictionary.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation
import FirebaseDatabase

public extension RTNode where RawValue == String {
    func dictionary<Key, Element>(from node: Node?, keys: Node) -> RealtimeDictionary<Key, Element> {
        return RealtimeDictionary(in: Node(key: rawValue, parent: node), keysNode: keys)
    }
}

public struct RCDictionaryStorage<K, V>: MutableRCStorage where K: RealtimeDictionaryKey {
    public typealias Value = V
    let sourceNode: Node
    let keysNode: Node
    let elementBuilder: (Node) -> Value
    var elements: [K: Value] = [:]

    func buildElement(with key: String) -> V {
        return elementBuilder(sourceNode.child(with: key))
    }

    mutating func store(value: Value, by key: K) { elements[for: key] = value }
    func storedValue(by key: K) -> Value? { return elements[for: key] }

    internal mutating func element(by key: String) -> (Key, Value) {
        guard let element = storedElement(by: key) else {
            let value = buildElement(with: key)
            let storeKey = Key(in: keysNode.child(with: key))
            store(value: value, by: storeKey)

            return (storeKey, value)
        }

        return element
    }
    fileprivate func storedElement(by key: String) -> (Key, Value)? {
        return elements.first(where: { $0.key.dbKey == key })
    }
}

public typealias RealtimeDictionaryKey = Hashable & RealtimeValue & Linkable
public final class RealtimeDictionary<Key, Value>: RC
where Value: RealtimeValue & RealtimeValueEvents, Key: RealtimeDictionaryKey {
    //    public let dbRef: DatabaseReference?
    public var node: Node?
    public var view: RealtimeCollectionView { return _view }
    public var storage: RCDictionaryStorage<Key, Value>
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[_PrototypeValue], _PrototypeValueSerializer>>

    public init(in node: Node, keysNode: Node) {
        self.node = node
        self.storage = RCDictionaryStorage(sourceNode: node, keysNode: keysNode, elementBuilder: Value.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(in: node.child(with: Nodes.items.rawValue)))
    }

    // MARK: Implementation

    private var shouldLinking = true // TODO: Create class family for such cases
    public func unlinked() -> RealtimeDictionary<Key, Value> { shouldLinking = false; return self }

    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return _view.source.listeningItem(.just { _ in handler() }) }
    public func runObserving() { _view.source.runObserving() }
    public func stopObserving() { _view.source.stopObserving() }
    public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: @escaping (Error?) -> Void) { _view.prepare(forUse: completion) }

    public typealias Element = (key: Key, value: Value)

    public func makeIterator() -> IndexingIterator<RealtimeDictionary> { return IndexingIterator(_elements: self) }
    public subscript(position: Int) -> Element { return storage.element(by: _view[position].dbKey) }
    public subscript(key: Key) -> Value? { return containsValue(byKey: key) ? storage.object(for: key) : nil }

    public func containsValue(byKey key: Key) -> Bool { _view.checkPreparation(); return _view.source.value.contains(where: { $0.dbKey == key.dbKey }) }

    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }

    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        checkPreparation()

        query(dbRef!).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)

            completion(self.filter { snapshot.hasChild($0.key.dbKey) }, nil)
        }) { (error) in
            completion([], error)
        }
    }

    // MARK: Mutating

    @discardableResult
    public func set(element: Value, for key: Key, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        guard element.isStandalone else { fatalError("Element already saved to database") }

        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: { collection, err in
                    collection.set(element: element, for: key, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }



        var oldElement: Value?
        if let p_value = _view.source.value.first(where: { $0.dbKey == key.dbKey }) {
            oldElement = storage.object(for: key)
            transaction.addPrecondition { [unowned transaction] (promise) in
                oldElement!.willRemove { err, refs in
                    refs?.filter { $0.key != key.dbKey }.forEach { transaction.addNode(item: ($0, .value(nil))) }
                    transaction.addNode(oldElement!.node!.linksNode.child(with: p_value.linkId), value: nil)
                    promise.fulfill(err)
                }
            }
        }

        let needLink = shouldLinking
        let elementNode = storage.sourceNode.child(with: key.dbKey)
        let link = key.node!.generate(linkTo: [_view.source.node!, elementNode])
        let prototypeValue = _PrototypeValue(dbKey: key.dbKey, linkId: link.link.id, index: count)
        let oldValue = _view.source.value
        _view.source.value.append(prototypeValue)
        storage.store(value: element, by: key)
        transaction.addReversion { [weak self] in
            self?._view.source.value = oldValue
            if let old = oldElement {
                self?.storage.store(value: old, by: key)
            } else {
                self?.storage.elements.removeValue(forKey: key)
            }
        }

        if needLink {
            transaction.addNode(link.sourceNode, value: link.link.localValue)
            let valueLink = elementNode.generate(linkKeyedBy: link.link.id, to: [_view.source.node!.child(with: key.dbKey), link.sourceNode])
            transaction.addNode(valueLink.sourceNode, value: valueLink.link.localValue)
        }
        if let e = element as? RealtimeObject {
            transaction.update(e, by: elementNode)
        } else {
            transaction.set(element, by: elementNode)
        }
        transaction.addNode(_view.source.node!.child(with: prototypeValue.dbKey), value: [prototypeValue.linkId    : _view.count])
        transaction.addCompletion { [weak self] result in
            if result {
                if needLink {
                    key.add(link: link.link)
                }
                element.didSave(in: elementNode)
                self?.didSave()
            }
        }
        return transaction
    }

    @discardableResult
    public func remove(for key: Key, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: { collection, err in
                    collection.remove(for: key, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        guard let index = _view.source.value.index(where: { $0.dbKey == key.dbKey }) else { return transaction }

        let transaction = transaction ?? RealtimeTransaction()

        let element = self[key]!
        transaction.addPrecondition { [unowned transaction] (promise) in
            element.willRemove { err, refs in
                refs?.forEach { transaction.addNode(item: ($0, .value(nil))) }
                transaction.addNode(element.node!.linksNode, value: nil)
                promise.fulfill(err)
            }
        }

        let oldValue = _view.source.value
        let p_value = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(_view.source.node!, value: _view.source.localValue)
        transaction.addNode(storage.sourceNode.child(with: key.dbKey), value: nil)
        transaction.addNode(key.node!.linksNode.child(with: p_value.linkId), value: nil)
        transaction.addCompletion { [weak self] result in
            if result {
                key.remove(linkBy: p_value.linkId)
                self?.storage.elements.removeValue(forKey: key)
                element.didRemove()
                self?.didSave()
            }
        }
        return transaction
    }

    // MARK: Realtime

    public var localValue: Any? {
        let split = storage.elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(Key, Value)], removed: [(Key, Value)]) in
            guard _view.contains(where: { $0.dbKey == keyValue.key.dbKey }) else {
                return (res.exists, res.removed + [keyValue])
            }

            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keyValues: split.exists, mapKey: { $0.dbKey }, mapValue: { $0.localValue })
        value[_view.source.dbKey] = _view.source.localValue
        split.removed.forEach { value[$0.0.dbKey] = nil }

        return value
    }

    public init(in node: Node?) {
        fatalError("Realtime dictionary cannot be initialized with init(in:) initializer")
    }

    public required convenience init(snapshot: DataSnapshot) {
        fatalError("Realtime dictionary cannot be initialized with init(snapshot:) initializer")
    }

    public convenience init(snapshot: DataSnapshot, keysNode: Node) {
        self.init(in: Node.root.child(with: snapshot.ref.rootPath), keysNode: keysNode)
        apply(snapshot: snapshot)
    }

    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.items.has(in: snapshot) {
            _view.source.apply(snapshot: Nodes.items.snapshot(from: snapshot))
            _view.isPrepared = true
        }
        _view.source.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly, let contained = storage.elements.first(where: { $0.0.dbKey == key.dbKey }) { storage.elements.removeValue(forKey: contained.key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = storage.elements.first(where: { $0.0.dbKey == key.dbKey })?.value {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                let keyEntity = Key(in: storage.keysNode.child(with: key.dbKey))
                storage.elements[keyEntity] = Value(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }

    public func didSave(in node: Node) {
        _view.source.didSave()
    }

    public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) { _view.source.willRemove(completion: completion) }
    public func didRemove(from node: Node) {
        _view.source.didRemove()
    }
}
