//
//  other.swift
//  Realtime_Tests
//
//  Created by Denis Koryttsev on 11/08/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
import UIKit
@testable import Realtime

// UIKit support

class OtherTests: XCTestCase {
    func testControlListening() {
        var counter = 0
        let control = UIControl()

        let disposable = control.realtime.onEvent(.touchUpInside).listening({ _ in
            counter += 1
        })

        control.sendActions(for: .touchUpInside)

        XCTAssertTrue(counter == 1)

        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .touchDown)

        XCTAssertTrue(counter == 2)

        disposable.dispose()

        control.sendActions(for: .touchUpInside)

        XCTAssertTrue(counter == 2)
    }
}

// MARK: Other

extension OtherTests {
    func testMirror() {
        let object = Object(in: .root)
        let mirror = Mirror(reflecting: object)

        XCTAssert(mirror.children.count > 0)
        mirror.children.forEach { (child) in
            print(child.label as Any, child.value)
        }

        mirror.children.forEach { (child) in
            print(child.label as Any, child.value)
        }

        let id = ObjectIdentifier.init(object)
        print(id)
    }
    func testReflectEnum() {
        enum Test {
            case one(Any), two(Any)
        }
        let one = Test.one(false)
        let oneMirror = Mirror(reflecting: one)
        let testMirror = Mirror(reflecting: Test.self)

        print(oneMirror, testMirror)
    }
    func testReflectClass() {
        let mirror = Mirror(reflecting: Object.self)
        print(mirror.children.map({ $0 }), mirror.superclassMirror as Any)
    }

    func testCodableEnum() {
        struct Err: Error {
            var localizedDescription: String { return "" }
        }
        struct News: Codable {
            let date: TimeInterval
        }
        enum Feed: Codable {
            case common(News)

            enum Key: CodingKey {
                case raw
            }

            init(from decoder: Decoder) throws {
                let rawContainer = try decoder.container(keyedBy: Key.self)
                let container = try decoder.singleValueContainer()
                let rawValue = try rawContainer.decode(Int.self, forKey: .raw)
                switch rawValue {
                case 0:
                    self = .common(try container.decode(News.self))
                default:
                    throw Err()
                }
            }

            func encode(to encoder: Encoder) throws {
                switch self {
                case .common(let news):
                    var container = encoder.singleValueContainer()
                    try container.encode(news)
                    var rawContainer = encoder.container(keyedBy: Key.self)
                    try rawContainer.encode(0, forKey: .raw)
                }
            }
        }

        do {
            let news = News(date: 0.0)
            let feed: Feed = .common(news)

            let data = try JSONEncoder().encode(feed)

            let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! NSDictionary
            let decodedFeed = try JSONDecoder().decode(Feed.self, from: data)

            XCTAssertTrue(["raw": 0, "date": 0.0] as NSDictionary == json)
            switch decodedFeed {
            case .common(let n):
                XCTAssertTrue(n.date == news.date)
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testEnumStringInterpolation() {
        XCTAssertNotEqual("__raw/__mv", "\(InternalKeys.raw)/\(InternalKeys.modelVersion)")
    }

//    func testNodeLimitExceeded() {
//        let node = Node.root.child(with: (0..<32).lazy.map(String.init).joined(separator: "/"))
//        XCTFail("\(node.underestimatedCount) levels")
//    }

    func testVersionerFunc() {
        var old: Versioner = Versioner(version: "")
        for i in stride(from: 1 as UInt32, to: 1000, by: 1) {
            for y in stride(from: 1 as UInt32, to: 1000, by: 1) {
                var versioner = Versioner()
                versioner.enqueue(Version(i, y))
                XCTAssertTrue(old < versioner, "\(old) !< \(versioner)")
                old = versioner
            }
        }
    }

    func testNewVersionerFunc() {
        let vers1 = Version(46, 23)
        let vers2 = Version(24, 43)

        struct Part {
            let level: UInt8
            let version: Version

            var data: Data {
                mutating get {
                    return Data(bytes: &self, count: MemoryLayout<Part>.size)
                }
            }
        }

        var part1 = Part(level: 0, version: vers1)
        var part2 = Part(level: 0, version: vers2)

        let data1 = part1.data
        let data2 = part2.data

        let copyPart1: Part = data1.withUnsafeBytes({ $0.pointee })
        let copyPart2: Part = data2.withUnsafeBytes({ $0.pointee })

        XCTAssertEqual(copyPart1.level, part1.level)
        XCTAssertEqual(copyPart1.version, part1.version)
        XCTAssertEqual(copyPart2.level, part2.level)
        XCTAssertEqual(copyPart2.version, part2.version)
    }

    func testNewVersionerFunc2() {
        let vers1 = Version(46, 23)
        let vers2 = Version(24, 43)
        let versions = [vers1, vers2]

        var levels = versions
        let base64String = Data(bytes: &levels, count: MemoryLayout<Version>.size * levels.count).base64EncodedString()

        levels = Data(base64Encoded: base64String).map({ d in
            let size = d.count / MemoryLayout<Version>.size
            return (0 ..< size).reduce(into: [], { (res, i) in
                let offset = i * MemoryLayout<Version>.size
                res.append(d.subdata(in: (offset..<offset + MemoryLayout<Version>.size)).withUnsafeBytes({ $0.pointee }))
            })
        }) ?? []

        XCTAssertEqual(levels, versions)
    }

    func testMultilevelNodeEvidence() {
        let node1 = Node(key: "cjnk/xocm", parent: .root)
        let node2 = Node(key: "mkjmld", parent: .root)

        XCTAssertTrue(node1._hasMultiLevelNode)
        XCTAssertFalse(node2._hasMultiLevelNode)
    }

    func testDecodingRawValue() {
        let value = RealtimeDatabaseValue(1)
        let data: RealtimeDataProtocol = ObjectNode(node: .root, childs: [.value(ValueNode(node: Node(key: InternalKeys.raw, parent: .root), value: value))])

        do {
            let rawValue = try data.rawValue()
            XCTAssertEqual(rawValue, value)
        } catch let e {
            XCTFail(String(describing: e))
        }
    }

    func testPrefixOperator() {
        let property = Property<String>(
            in: nil,
            options: .required(.realtimeDataValue, db: Cache.root)
        )
        property <== "string"

        XCTAssertEqual(§property, "string")
    }

    func testUnsafeMutablePointerRetainsObject() {
        var i = 0
        let pointer = UnsafeMutablePointer<NSObject>.allocate(capacity: 1)
        pointer.initialize(to: NSObject())
        func getResult() {
            return i = Int(bitPattern: pointer)
        }
        getResult()
        XCTAssertEqual(i, Int(bitPattern: pointer))
        weak var obj = pointer.pointee
        pointer.deinitialize(count: 1).deallocate()
        XCTAssertNil(obj)
    }
}

internal func _makeCollectionDescription<C: Collection>(_ collection: C,
    withTypeName type: String? = nil
    ) -> String {
    var result = ""
    if let type = type {
        result += "\(type)(["
    } else {
        result += "["
    }

    var first = true
    for item in collection {
        if first {
            first = false
        } else {
            result += ", "
        }
        debugPrint(item, terminator: "", to: &result)
    }
    result += type != nil ? "])" : "]"
    return result
}

class ObjectWithOptionalNestedObject: Object {
    var nestedObj: Object?
}

extension OtherTests {
    func testOptionalNestedObject() {
        let objONO = ObjectWithOptionalNestedObject()
        objONO.nestedObj = Object()

        let mirror = Mirror(reflecting: objONO)
        mirror.children.forEach { (child) in
            XCTAssertNotNil(child.value as? _RealtimeValue)
        }
    }
//    func testApplyingOptionalNestedObject() {
//        let objONO = ObjectWithOptionalNestedObject()
//
//        let data = ObjectNode(node: .root, childs: [.value(ValueNode(node: Node(key: "nestedObj", parent: .root), value: [InternalKeys.raw.rawValue: 0]))])
//        try! objONO.apply(data, event: .value)
//
//        XCTAssertNotNil(objONO.nestedObj)
//    }
}

extension OtherTests {
    func testArrayContainersPerformance() {
        class Box<T> {
            var value: T
            init(_ value: T) {
                self.value = value
            }
        }
        struct MutableBlackBox<T> {
            var _value: T
            init(_ value: T) {
                self._value = value
            }

            var value: T {
                get { return _value }
                set { _value = newValue }
            }
        }
        enum CustomOptional<T> {
            case none
            case some(T)
        }
        let size = 10_000_0
        let input = stride(from: 0, to: size, by: 1)
//        var array: [Int] = [] // very quick
        let storage = ValueStorage<[Int]>.unsafe(strong: []) // now quick as array// extremely slow, with growing after each iteration
//        let box = Box<[Int]>([]) // very quick as array
//        var mutableBox = MutableBlackBox<[Int]>([]) // // extremely slow as ValueStorage
//        var optionalArray: Optional<[Int]> = .some([]) // very quick as array
//        var customOptionalArray: CustomOptional<[Int]> = .some([]) // quick but more slowly than Optional with `_?` access, and the same as `switch case` access.
        self.measure {
            input.forEach { (i) in
//                array.append(i)
                storage.mutate { (val) in
                    val.append(i)
                }
//                box.value.append(i)
//                mutableBox.value.append(i)
//                optionalArray?.append(i)
//                switch optionalArray {
//                case .some(var arr): arr.append(i)
//                case .none: optionalArray = .some([])
//                }
//                _ = unsafeBitCast(optionalArray, to: [Int].self)
            }
//            print(array.count)
            print(storage.value.count)
//            print(box.value.count)
//            print(mutableBox.value.count)
//            print(optionalArray?.count)
        }
    }
}
