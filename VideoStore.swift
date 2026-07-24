import Foundation
import Combine
import FirebaseFirestore

let BACKEND_URL = "http://192.168.1.120:3001"
struct MuxCreateUploadResponse: Codable {
    let uploadId: String
    let uploadUrl: String
}

struct MuxStatusResponse: Codable {
    let playbackId: String?
    let hlsUrl: String?
    let thumbnailUrl: String?
}

struct VideoItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var description: String
    var uri: String
    var uploader: String
    var category: String
    var uploadProgress: Int = 100
    var durationText: String = "Now Streaming"
    var uploadedAt: String = "Just now"
    var thumbnailUrl: String? = nil
    var playbackId: String? = nil
    var status: String = "ready"

    var isReady: Bool {
        status == "ready" && uri.starts(with: "http")
    }

    var firestoreData: [String: Any] {
        [
            "id": id,
            "title": title,
            "description": description,
            "uri": uri,
            "hlsUrl": uri.starts(with: "http") ? uri : "",
            "uploader": uploader,
            "category": category,
            "uploadProgress": uploadProgress,
            "durationText": durationText,
            "uploadedAt": uploadedAt,
            "thumbnailUrl": thumbnailUrl ?? "",
            "playbackId": playbackId ?? "",
            "status": status,
            "createdAt": Date().timeIntervalSince1970
        ]
    }
}

final class VideoStore: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var errorMessage: String = ""

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init() {
        listenForVideos()
    }

    deinit {
        listener?.remove()
    }

    func listenForVideos() {
        listener?.remove()

        listener = db.collection("videos")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                    }
                    print("Firestore error:", error.localizedDescription)
                    return
                }

                guard let docs = snapshot?.documents else { return }

                DispatchQueue.main.async {
                    self.videos = docs.map { doc in
                        let data = doc.data()
                        let hls = data["hlsUrl"] as? String ?? ""
                        let uri = data["uri"] as? String ?? ""

                        return VideoItem(
                            id: data["id"] as? String ?? doc.documentID,
                            title: data["title"] as? String ?? "Untitled Video",
                            description: data["description"] as? String ?? "",
                            uri: hls.isEmpty ? uri : hls,
                            uploader: data["uploader"] as? String ?? "SUB PREMIUM TV",
                            category: data["category"] as? String ?? "User Upload",
                            uploadProgress: data["uploadProgress"] as? Int ?? 100,
                            durationText: data["durationText"] as? String ?? "Processing...",
                            uploadedAt: data["uploadedAt"] as? String ?? "Just now",
                            thumbnailUrl: data["thumbnailUrl"] as? String,
                            playbackId: data["playbackId"] as? String,
                            status: data["status"] as? String ?? "processing"
                        )
                    }
                }
            }
    }

    func addVideo(_ video: VideoItem) {
        db.collection("videos")
            .document(video.id)
            .setData(video.firestoreData, merge: true)
    }

    func updateVideo(_ video: VideoItem) {
        db.collection("videos")
            .document(video.id)
            .setData(video.firestoreData, merge: true)
    }

    func deleteVideo(_ video: VideoItem) {
        db.collection("videos")
            .document(video.id)
            .delete()
    }

    func refreshMuxVideo(_ video: VideoItem) async {
    guard video.status == "processing" || !video.uri.starts(with: "http") else {
    return
    }

    do {
    let status = try await BackendService.shared.checkMuxUploadStatus(uploadId: video.id)

    guard let hlsUrl = status.hlsUrl, !hlsUrl.isEmpty else {
    return
    }

    let updatedVideo = VideoItem(
    id: video.id,
    title: video.title,
    description: video.description,
    uri: hlsUrl,
    uploader: video.uploader,
    category: video.category,
    uploadProgress: video.uploadProgress,
    durationText: "Now Streaming",
    uploadedAt: video.uploadedAt,
    thumbnailUrl: status.thumbnailUrl,
    playbackId: status.playbackId,
    status: "ready"
    )

    await MainActor.run {
    self.updateVideo(updatedVideo)
    }
    } catch {
    await MainActor.run {
    self.errorMessage = "Could not refresh video processing status."
    }
    }
    }

    func refreshAllProcessingVideos() async {
        for video in videos {
            if video.status == "processing" || video.durationText == "Processing..." {
                await refreshMuxVideo(video)
            }
        }
    }
}

final class BackendService {
    static let shared = BackendService()

    func createMuxUpload() async throws -> MuxCreateUploadResponse {
        guard let url = URL(string: "\(BACKEND_URL)/api/mux/create-upload") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(MuxCreateUploadResponse.self, from: data)
    }

    func uploadVideoToMux(fileURL: URL, uploadUrl: String, progress: @escaping (Double) -> Void) async throws {
    guard let url = URL(string: uploadUrl) else {
    throw URLError(.badURL)
    }

    progress(0.25)

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

    let (_, response) = try await URLSession.shared.upload(
    for: request,
    fromFile: fileURL
    )

    progress(1.0)

    if let http = response as? HTTPURLResponse,
    !(200...299).contains(http.statusCode) {
    throw URLError(.badServerResponse)
    }
    }

    func checkMuxUploadStatus(uploadId: String) async throws -> MuxStatusResponse {
        guard let url = URL(string: "\(BACKEND_URL)/api/mux/upload/\(uploadId)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(MuxStatusResponse.self, from: data)
    }
}
