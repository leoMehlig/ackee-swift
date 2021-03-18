import Foundation
import Combine

public struct Record {
    public let id: String
}

public struct Event {
    let id: String
    let key: String

    public init(id: String, key: String) {
        self.id = id
        self.key = key
    }
}

public class Tracker: ObservableObject {
    public let url: URL
    public let domain: String

    public var defaultAttributes: Attributes

    public var isEnabled: Bool = true

    private let encoder: JSONEncoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL, domain: String, defaultAttributes: Attributes = Attributes()) {
        self.url = url
        self.domain = domain
        self.defaultAttributes = defaultAttributes
    }

    var cancallables: Set<AnyCancellable> = []

    public func record<Root>(path: String, to keyPath: ReferenceWritableKeyPath<Root, Record?>, on root: Root) {
        var attributes = self.defaultAttributes
        attributes.siteLocation = path
        self.send(request: CreateRecord(domainId: domain, input: attributes).request)
            .map(\.id)
            .map { Record(id: $0) as Record? }
            .replaceError(with: nil)
            .assign(to: keyPath, on: root)
            .store(in: &cancallables)
    }

    public func update(record: Record?) {
        guard let id = record?.id else {
            return
        }

        self.send(request: UpdateRecord(recordId: id).request)
            .map(\.success)
            .replaceError(with: false)
            .sink(receiveValue: { _ in })
            .store(in: &cancallables)
    }

    public func action(_ event: Event, value: Double = 1) {
        let request = CreateAction(eventId: event.id, input: .init(key: event.key, value: value)).request
        self.send(request: request)
            .map(\.id)
            .replaceError(with: "")
            .sink(receiveValue: { _ in })
            .store(in: &cancallables)
    }

    private func send<Variables: Codable, Response: Decodable>(request: GraphQLRequest<Variables, Response>) -> AnyPublisher<Response, GraphQLError> {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            return Fail(error: GraphQLError.encoding(error)).eraseToAnyPublisher()
        }
        urlRequest.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        return URLSession.shared.dataTaskPublisher(for: urlRequest)
            .map(\.data)
            .decode(type: GraphQLResponse<Response>.self, decoder: decoder)
            .tryMap { response -> Response in
                if let data = response.data {
                    return data
                } else {
                    throw response.errors?.first ?? .unknown
                }
            }
            .mapError {
                switch $0 {
                case let graphQL as GraphQLError:
                    return graphQL
                case let network as URLSession.DataTaskPublisher.Failure:
                    return .network(network)
                default:
                    return .unknown
                }
            }
            .print()
            .eraseToAnyPublisher()
    }

}

struct GraphQLRequest<Variables: Codable, Response: Decodable>: Codable {
    let query: String
    let variables: Variables
}


public struct Attributes: Codable {
    public var siteLocation: String?
    public var siteLanguage: String?
    public var screenWidth: Double?
    public var screenHeight: Double?
    public var deviceName: String?
    public var deviceManufacturer: String = "Apple"
    public var osName: String = "iOS"
    public var osVersion: String?
    public var browserName: String = "Structured iOS"
    public var browserVersion: String?
    public var browserWidth: Double?
    public var browserHeight: Double?

    public init(osVersion: String? = nil,
                browserVersion: String? = nil,
                siteLanguage: String? = nil,
                deviceName: String? = nil,
                screenWidth: Double? = nil,
                screenHeight: Double? = nil) {
        self.osVersion = osVersion
        self.browserVersion = browserVersion
        self.siteLanguage = siteLanguage
        self.deviceName = deviceName
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.browserWidth = screenWidth
        self.browserHeight = screenHeight
    }
}

struct CreateRecord: Codable {
    struct Response: Decodable {
        enum CodingKeys: String, CodingKey {
            case createRecord, payload, id
        }

        let id: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .createRecord)
                .nestedContainer(keyedBy: CodingKeys.self, forKey: .payload)
                .decode(String.self, forKey: .id)
        }
    }

    let domainId: String
    let input: Attributes

    var request: GraphQLRequest<Self, Response> {
        GraphQLRequest(query: "mutation createRecord($domainId:ID!,$input:CreateRecordInput!){createRecord(domainId:$domainId,input:$input){payload{id}}}",
                       variables: self)
    }
}

struct UpdateRecord: Codable {
    struct Response: Decodable {
        enum CodingKeys: String, CodingKey {
            case updateRecord, success
        }

        let success: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.success = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .updateRecord)
                .decode(Bool.self, forKey: .success)
        }
    }

    let recordId: String

    var request: GraphQLRequest<Self, Response> {
        GraphQLRequest(query: "mutation updateRecord($recordId:ID!){updateRecord(id:$recordId){success}}",
                       variables: self)
    }
}

struct CreateAction: Codable {
    struct Response: Decodable {
        enum CodingKeys: String, CodingKey {
            case createAction, payload, id
        }

        let id: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .createAction)
                .nestedContainer(keyedBy: CodingKeys.self, forKey: .payload)
                .decode(String.self, forKey: .id)
        }
    }

    struct Input: Codable {
        let key: String
        let value: Double
    }

    let eventId: String
    let input: Input

    var request: GraphQLRequest<Self, Response> {
        GraphQLRequest(query: "mutation createAction($eventId:ID!,$input:CreateActionInput!){createAction(eventId:$eventId,input:$input){payload{id}}}",
                       variables: self)
    }
}

struct GraphQLResponse<Data: Decodable>: Decodable {
    let data: Data?
    let errors: [GraphQLError]?
}

public enum GraphQLError: Decodable, Swift.Error {
    enum CodingKeys: String, CodingKey {
        case message
    }
    case unknown
    case response(message: String)
    case network(URLSession.DataTaskPublisher.Failure)
    case encoding(Error)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let message = try container.decodeIfPresent(String.self, forKey: .message) {
            self = .response(message: message)
        } else {
            self = .unknown
        }
    }
}
