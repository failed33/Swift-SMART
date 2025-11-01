import Foundation
import XCTest

enum FixtureLoader {
    enum Error: Swift.Error, LocalizedError {
        case invalidContents(URL)

        var errorDescription: String? {
            switch self {
            case .invalidContents(let url):
                return "Fixture at \(url.lastPathComponent) contains invalid data"
            }
        }
    }

    static func data(
        named name: String,
        withExtension fileExtension: String = "json",
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Data {
        let url = try urlForFixture(named: name, withExtension: fileExtension, file: file, line: line)
        do {
            return try Data(contentsOf: url)
        } catch {
            XCTFail("Failed to load fixture \(name).\(fileExtension): \(error)", file: file, line: line)
            throw error
        }
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        named name: String,
        withExtension fileExtension: String = "json",
        decoder: JSONDecoder = JSONDecoder(),
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T {
        let data = try data(named: name, withExtension: fileExtension, file: file, line: line)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            XCTFail("Failed to decode fixture \(name).\(fileExtension): \(error)", file: file, line: line)
            throw Error.invalidContents(try urlForFixture(named: name, withExtension: fileExtension, file: file, line: line))
        }
    }

    static func urlForFixture(
        named name: String,
        withExtension fileExtension: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            throw XCTSkip("Missing fixture \(name).\(fileExtension)", file: file, line: line)
        }
        return url
    }
}

