import Foundation

/// Writes the raw signals the thresholds are judged against, so tuning is done from a
/// file and not from a feeling. One CSV per launch in ~/Library/Logs/Reach/.
///
/// Columns: t, kind, a, b, c, d
///   hand : a=pinchRatio  b=confidence  c=raised(0/1)  d=state(0 open,1 pinched,2 right-pinched)
///   pose : a=fingers(thumb,index,middle,ring,little as 0/1)  b=middlePinchRatio  c=mode(point,aim,scroll,hold)
///          d=gap in px between where the hand points and where the cursor is (what the steadying absorbed)
///   audio: a=onset(hi/slowHigh)  b=loud(rms/slowLevel)  c=hiRMS  d=fired(0/1)   (only when onset > 2)
///   tap  : a=onset  b=0  c=0  d=accepted(0/1)
///   key  : a=secondsSinceKey (a tap or pinch was dropped because of recent typing)
///   note : free text in `a`
final class Diagnostics {
    static let shared = Diagnostics()
    private let queue = DispatchQueue(label: "reach.diagnostics", qos: .utility)
    private var handle: FileHandle?
    private let t0 = Date()
    let url: URL

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Reach", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmmss"
        url = dir.appendingPathComponent("signals \(f.string(from: Date())).csv")
        FileManager.default.createFile(atPath: url.path, contents: "t,kind,a,b,c,d\n".data(using: .utf8))
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        // Keep the folder from growing forever: ten launches is plenty of history.
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let old = files.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for u in old.dropLast(10) { try? FileManager.default.removeItem(at: u) }
        }
    }

    func log(_ kind: String, _ a: Any, _ b: Any = 0, _ c: Any = 0, _ d: Any = 0) {
        let t = Date().timeIntervalSince(t0)
        let line = String(format: "%.3f,", t) + "\(kind),\(a),\(b),\(c),\(d)\n"
        queue.async { [handle] in handle?.write(line.data(using: .utf8)!) }
    }
}
