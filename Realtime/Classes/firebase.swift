//
//  Firebase.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 25/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import FirebaseDatabase
import FirebaseStorage

public typealias StorageMetadata = FirebaseStorage.StorageMetadata
public typealias DataSnapshot = FirebaseDatabase.DataSnapshot
public typealias DatabaseReference = FirebaseDatabase.DatabaseReference

public extension DatabaseReference {
    static func root(of database: Database = Database.database()) -> DatabaseReference { return database.reference() }
    static func fromRoot(_ path: String, of database: Database = Database.database()) -> DatabaseReference {
        return database.reference(withPath: path)
    }

    var rootPath: String { return path(from: root) }
    
    func path(from ref: DatabaseReference) -> String {
        return String(url[ref.url.endIndex...])
    }
    
    func isChild(for ref: DatabaseReference) -> Bool {
        return !isEqual(for: ref) && url.hasPrefix(ref.url)
    }
    func isEqual(for ref: DatabaseReference) -> Bool {
        return self === ref || url == ref.url
    }

    public typealias TransactionCompletion = (Error?, DatabaseReference) -> Void
    func update(use keyValuePairs: [String: Any], completion: TransactionCompletion?) {
        if let completion = completion {
            updateChildValues(keyValuePairs, withCompletionBlock: completion)
        } else {
            updateChildValues(keyValuePairs)
        }
    }
}


public struct Event: Listenable {
    let database: RealtimeDatabase
    let node: Node
    let event: DataEventType

    /// Disposable listening of value
    public func listening(_ assign: Assign<ListenEvent<RealtimeDataProtocol>>) -> Disposable {
        let token = database.listen(node: node, assign)
        return ListeningDispose({
            self.database.removeObserver(for: self.node, with: token)
        })
    }

    /// Listening with possibility to control active state
    public func listeningItem(_ assign: Assign<ListenEvent<RealtimeDataProtocol>>) -> ListeningItem {
        let token = database.listen(node: node, assign)
        return ListeningItem(
            resume: { self.database.listen(node: self.node, assign) },
            pause: { self.database.removeObserver(for: self.node, with: $0) },
            token: token
        )
    }
}

extension RealtimeDatabase {
    public func data(_ event: DataEventType, node: Node) -> Event {
        return Event(database: self, node: node, event: event)
    }

    fileprivate func listen(node: Node, _ assign: Assign<ListenEvent<RealtimeDataProtocol>>) -> UInt {
        let token = observe(
            .value,
            on: node,
            onUpdate: <-assign.map { .value($0) },
            onCancel: <-assign.map { .error($0) }
        )
        return token
    }
}
