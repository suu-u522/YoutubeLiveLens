import Foundation

struct Comment: Identifiable, Codable {
    var id: String { "\(offsetMs)-\(text)" }
    let text: String
    let offsetMs: Int
}

struct CommentBucket: Codable {
    let bucketIndex: Int
    let startMs: Int
    let endMs: Int
    let messages: [Comment]
}
