//
//  RealtimeArray.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Add RealtimeValueActions implementation

public extension RTNode where RawValue == String {
    func array<Element>(from node: Node?) -> RealtimeArray<Element> {
        return RealtimeArray(in: Node(key: rawValue, parent: node))
    }
}
public extension Node {
    func array<Element>() -> RealtimeArray<Element> {
        return RealtimeArray(in: self)
    }
}

// MARK: Implementation RealtimeCollection`s

public extension RealtimeArray {
    convenience init<E>(in node: Node?, elements: LinkedRealtimeArray<E>) {
        self.init(in: node, viewSource: elements._view.source)
    }
}

/// # Realtime Array
/// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
/// Comment writing guide
public final class RealtimeArray<Element>: RC where Element: RealtimeValue & RealtimeValueEvents & Linkable {
    public internal(set) var node: Node?
    public internal(set) var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[_PrototypeValue], _PrototypeValuesSerializer>>

    public convenience init(in node: Node?) {
        self.init(in: node, viewSource: RealtimeProperty(in: node?.child(with: Nodes.items.rawValue).linksNode))
    }

    init(in node: Node?, viewSource: RealtimeProperty<[_PrototypeValue], _PrototypeValuesSerializer>) {
        precondition(node != nil)
        self.node = node
        self.storage = RCArrayStorage(sourceNode: node!, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(viewSource)
    }

    // Implementation

    public func contains(_ element: Element) -> Bool {
        return _view.source.value.contains { $0.dbKey == element.dbKey }
    }
    public subscript(position: Int) -> Element { return storage.object(for: _view.source.value[position]) }
    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem {
        return _view.source.listeningItem(.guarded(self) { _, this in
            this._view.isPrepared = true
            handler()
        })
    }
    public func runObserving() { _view.source.runObserving() }
    public func stopObserving() { _view.source.stopObserving() }
    public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) {
        _view.prepare(forUse: completion.with(work: .weak(self) { err, `self` in
            if err == nil {
                self.map { $0._snapshot.map($0.apply) }
            }
        }))
    }
    
    // TODO: Create Realtime wrapper for DatabaseQuery
    // TODO: Check filter with difficult values aka dictionary
    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        checkPreparation()

        query(dbRef!).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)
            
            completion(self.filter { snapshot.hasChild($0.dbKey) }, nil)
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    // TODO: Add parameter for sending local event (after write to db, or immediately)
    @discardableResult
    public func insert(element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }

        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    try! collection.insert(element: element, at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        guard element.node.map({ _ in !contains(element) }) ?? true
            else { fatalError("Element with such key already exists") }

        let elementNode = element.node.map { $0.moveTo(storage.sourceNode); return $0 } ?? storage.sourceNode.childByAutoId()
        let transaction = transaction ?? RealtimeTransaction()
        let link = elementNode.generate(linkTo: _view.source.node!.child(with: elementNode.key))
        let key = _PrototypeValue(dbKey: elementNode.key, linkID: link.link.id, index: index ?? count)

        let oldValue = _view.source.value
        _view.source.value.insert(key, at: key.index)
        storage.store(value: element, by: key)
        transaction.addReversion { [weak self] in
            self?._view.source.value = oldValue
            self?.storage.elements.removeValue(forKey: key)
            element.remove(linkBy: link.link.id)
        }
        transaction.addValue(_ProtoValueSerializer.serialize(entity: key), by: _view.source.node!.child(with: key.dbKey))
        transaction.addValue(link.link.localValue, by: link.node)
        if let elem = element as? RealtimeObject { // TODO: Fix it
            transaction._update(elem, by: elementNode)
        } else {
            transaction._set(element, by: elementNode)
        }
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    @discardableResult
    public func remove(element: Element, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        if let index = _view.source.value.index(where: { $0.dbKey == element.dbKey }) {
            return remove(at: index, in: transaction)
        }
        return transaction
    }

    @discardableResult
    public func remove(at index: Int, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    collection.remove(at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        let element = self[index]
        element.willRemove(in: transaction)

        let oldValue = _view.source.value
        let key = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addValue(nil, by: _view.source.node!.child(with: key.dbKey))
        transaction.addValue(nil, by: storage.sourceNode.child(with: key.dbKey))
        transaction.addCompletion { [weak self] result in
            if result {
                self?.storage.elements.removeValue(forKey: key)
                element.didRemove()
                self?.didSave()
            }
        }
        return transaction
    }
    
    // MARK: Realtime
    
    public var localValue: Any? {
        let split = storage.elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(_PrototypeValue, Element)], removed: [(_PrototypeValue, Element)]) in
            guard _view.source.value.contains(keyValue.key) else {
                return (res.exists, res.removed + [keyValue])
            }
            
            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keyValues: split.exists, mapKey: { $0.dbKey }, mapValue: { $0.localValue })
        value[_view.source.dbKey] = _view.source.localValue
        split.removed.forEach { value[$0.0.dbKey] = nil }
        
        return value
    }

    public required convenience init(snapshot: DataSnapshot) {
        self.init(in: Node.root.child(with: snapshot.ref.rootPath))
        apply(snapshot: snapshot)
    }

    var _snapshot: (DataSnapshot, Bool)?
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        guard _view.isPrepared else {
            _snapshot = (snapshot, strongly)
            return
        }
        _snapshot = nil
        _view.source.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly { storage.elements.removeValue(forKey: key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = storage.elements[key] {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                storage.elements[key] = Element(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }
    
    public func didSave(in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value has been saved to node: \(parent) by key: \(key), but current node has key: \(node!.key).")
        debugFatalError(condition: !parent.isRooted, "Value has been saved non rooted node: \(parent)")

        if let node = self.node {
            node.parent = parent
        } else {
            self.node = Node(key: key, parent: parent)
        }

        _view.source.didSave()
        storage.elements.forEach { $1.didSave(in: storage.sourceNode, by: $0.dbKey) }
    }

    public func willRemove(in transaction: RealtimeTransaction) { transaction.addValue(nil, by: node!.linksNode) }
    public func didRemove(from node: Node) {
        _view.source.didRemove()
        storage.elements.values.forEach { $0.didRemove(from: storage.sourceNode) }
    }
}
