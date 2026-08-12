import Foundation

struct OlcrtcProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var carrier: String
    var transport: String
    var roomID: String
    var clientID: String
    var keyHex: String
    var dnsServer: String
    var vp8FPS: Int
    var vp8Batch: Int
    var authToken: String
    var sourceURI: String

    init(
        id: UUID = UUID(),
        name: String,
        carrier: String,
        transport: String,
        roomID: String,
        clientID: String,
        keyHex: String,
        dnsServer: String = "8.8.8.8:53",
        vp8FPS: Int = 120,
        vp8Batch: Int = 64,
        authToken: String = "",
        sourceURI: String
    ) {
        self.id = id
        self.name = name
        self.carrier = carrier
        self.transport = transport
        self.roomID = roomID
        self.clientID = clientID
        self.keyHex = keyHex
        self.dnsServer = dnsServer
        self.vp8FPS = vp8FPS
        self.vp8Batch = vp8Batch
        self.authToken = authToken
        self.sourceURI = sourceURI
    }
}

struct SubscriptionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    var profiles: [OlcrtcProfile]
    var lastUpdated: Date?
    var refreshIntervalSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        profiles: [OlcrtcProfile] = [],
        lastUpdated: Date? = nil,
        refreshIntervalSeconds: TimeInterval = 900
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.profiles = profiles
        self.lastUpdated = lastUpdated
        self.refreshIntervalSeconds = refreshIntervalSeconds
    }
}

struct PersistedState: Codable, Equatable {
    var manualProfiles: [OlcrtcProfile] = []
    var subscriptions: [SubscriptionRecord] = []
    var socksUser: String?
    var socksPassword: String?
    var socksPort: Int?
}
