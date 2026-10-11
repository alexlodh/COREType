import Foundation

// Recoverable replacement of generated COREType bundles and deliverables.
// Callers are responsible for validating ownership before invoking this helper.
var movedItems: [[String: String]] = []
for path in CommandLine.arguments.dropFirst() {
    guard FileManager.default.fileExists(atPath: path) else { continue }
    var destination: NSURL?
    try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &destination)
    movedItems.append(["original": path, "trash": destination?.path ?? "Trash"])
}
let data = try JSONSerialization.data(withJSONObject: movedItems, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
