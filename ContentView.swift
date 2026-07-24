import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import AVKit
import PhotosUI
import UniformTypeIdentifiers

struct UserAccount: Codable, Equatable {
    var username: String
    var nickname: String
    var email: String
    var password: String
}

enum AppPage {
    case home, search, upload, alerts, profile, player
}

enum ProfilePage {
    case main, help, rules, report, about
}

func canUpload(_ user: UserAccount) -> Bool {
    let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return email == "subpremium760@gmail.com" || email == "babucarrngum13@gmail.com"
}

func isStrongPassword(_ password: String) -> Bool {
    let upper = password.rangeOfCharacter(from: .uppercaseLetters) != nil
    let lower = password.rangeOfCharacter(from: .lowercaseLetters) != nil
    let digit = password.rangeOfCharacter(from: .decimalDigits) != nil
    let symbol = password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
    return password.count >= 8 && upper && lower && digit && symbol
}

final class AppStore: ObservableObject {
    
    private let db = Firestore.firestore()
    
    @Published var user: UserAccount?
    @Published var videos: [VideoItem] = []
    @Published var showIntro: Bool = false
    
    private let userKey = "sub_premium_auth_user"
    private let loggedInKey = "sub_premium_is_logged_in"
    private let videosKey = "sub_premium_videos"
    
    init() {
        loadUser()
        loadVideos()
    }
    
    func saveUser(_ newUser: UserAccount) {
        user = newUser
        UserDefaults.standard.set(true, forKey: loggedInKey)
        if let data = try? JSONEncoder().encode(newUser) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }
    
    func loadUser() {
        let isLoggedIn = UserDefaults.standard.bool(forKey: loggedInKey)
        guard isLoggedIn else {
            user = nil
            return
        }
        if let data = UserDefaults.standard.data(forKey: userKey),
           let saved = try? JSONDecoder().decode(UserAccount.self, from: data) {
            user = saved
        }
    }
    
    func savedUserOnly() -> UserAccount? {
        if let data = UserDefaults.standard.data(forKey: userKey),
           let saved = try? JSONDecoder().decode(UserAccount.self, from: data) {
            return saved
        }
        return nil
    }
    
    func logout() {
        UserDefaults.standard.set(false, forKey: loggedInKey)
        user = nil
    }
    
    func saveVideos() {
        if let data = try? JSONEncoder().encode(videos) {
            UserDefaults.standard.set(data, forKey: videosKey)
        }
    }
    
    func loadVideos() {
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                
                guard let documents = snapshot?.documents else {
                    print(error?.localizedDescription ?? "")
                    return
                }
                
                self.videos = documents.compactMap { doc in
                    
                    let data = doc.data()
                    
                    return VideoItem(
                        id: doc.documentID,
                        title: data["title"] as? String ?? "",
                        description: data["description"] as? String ?? "",
                        uri: data["hlsUrl"] as? String ?? "",
                        uploader: data["uploader"] as? String ?? "",
                        category: data["category"] as? String ?? "",
                        uploadProgress: 100,
                        durationText: data["duration"] as? String ?? "",
                        uploadedAt: data["uploadedAt"] as? String ?? "",
                        thumbnailUrl: data["thumbnailUrl"] as? String,
                        playbackId: data["playbackId"] as? String,
                        status: data["status"] as? String ?? "ready"
                    )
                }
            }
    }
    
    func addVideo(_ video: VideoItem) {
        
        videos.insert(video, at: 0)
        
        db.collection("videos").document(video.id).setData([
            "title": video.title,
            "description": video.description,
            "hlsUrl": video.uri,
            "uploader": video.uploader,
            "category": video.category,
            "duration": video.durationText,
            "uploadedAt": video.uploadedAt,
            "thumbnailUrl": video.thumbnailUrl ?? "",
            "playbackId": video.playbackId ?? "",
            "status": video.status,
            "createdAt": Timestamp()
        ])
    }
    
    func deleteVideo(_ video: VideoItem) {
        
        videos.removeAll { $0.id == video.id }
        
        db.collection("videos").document(video.id).delete()
    }
    
    func updateVideo(_ video: VideoItem) {
        
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else {
            return
        }
        
        videos[index] = video
        
        db.collection("videos").document(video.id).updateData([
            "title": video.title,
            "description": video.description,
            "hlsUrl": video.uri,
            "uploader": video.uploader,
            "category": video.category,
            "duration": video.durationText,
            "uploadedAt": video.uploadedAt,
            "thumbnailUrl": video.thumbnailUrl ?? "",
            "playbackId": video.playbackId ?? "",
            "status": video.status
        ])
    }
    
    func login(
        email: String,
        password: String,
        completion: @escaping (String?) -> Void
    ) {
        
        let cleanEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        Auth.auth().signIn(withEmail: cleanEmail, password: password) { result, error in
            
            DispatchQueue.main.async {
                
                if let error = error {
                    
                    print("🔥 FIREBASE LOGIN ERROR:")
                    print(error.localizedDescription)
                    
                    let nsError = error as NSError
                    print("Code: \(nsError.code)")
                    print("UserInfo: \(nsError.userInfo)")
                    
                    completion(error.localizedDescription)
                    return
                }
                
                guard let firebaseUser = result?.user else {
                    completion("Unable to sign in.")
                    return
                }
                
                let user = UserAccount(
                    username: firebaseUser.displayName ?? "User",
                    nickname: firebaseUser.displayName ?? "User",
                    email: firebaseUser.email ?? "",
                    password: ""
                )
                
                self.saveUser(user)
                self.showIntro = true
                completion(nil)
            }
        }
    }
    
    func createAccount(
        username: String,
        nickname: String,
        email: String,
        password: String,
        completion: @escaping (String?) -> Void
    ) {
        
        let cleanEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        guard isStrongPassword(password) else {
            completion("Password must contain uppercase, lowercase, number and symbol.")
            return
        }
        
        Auth.auth().createUser(withEmail: cleanEmail, password: password) { result, error in
            
            DispatchQueue.main.async {
                
                if let error = error as NSError? {
                    
                    switch AuthErrorCode(rawValue: error.code) {
                        
                    case .emailAlreadyInUse:
                        completion("This email already has an account. Please sign in.")
                        return
                        
                    case .invalidEmail:
                        completion("Invalid email address.")
                        return
                        
                    case .weakPassword:
                        completion("Password is too weak.")
                        return
                        
                    default:
                        completion(error.localizedDescription)
                        return
                    }
                }
                
                guard let firebaseUser = result?.user else {
                    completion("Unable to create account.")
                    return
                }
                
                let change = firebaseUser.createProfileChangeRequest()
                change.displayName = nickname
                
                change.commitChanges { _ in
                    
                    firebaseUser.sendEmailVerification()
                    
                    let user = UserAccount(
                        username: username,
                        nickname: nickname,
                        email: cleanEmail,
                        password: ""
                    )
                    
                    self.saveUser(user)
                    self.showIntro = true
                    
                    completion(nil)
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if store.user == nil {
                LoginScreen()
                    .environmentObject(store)
            } else if store.showIntro {
                IntroScreen {
                    store.showIntro = false
                }
            } else {
                MainAppScreen()
                    .environmentObject(store)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct LoginScreen: View {

@EnvironmentObject var store: AppStore

@State private var isSignUp = false

@State private var username = ""
@State private var nickname = ""
@State private var email = ""
@State private var password = ""

@State private var showPassword = false
@State private var message = ""
@State private var isLoading = false

var body: some View {

ScrollView {

VStack(spacing: 22) {

Spacer(minLength: 50)

Image(systemName: "play.fill")
.font(.system(size: 70, weight: .bold))
.foregroundColor(.white)

HStack(spacing: 3) {

Text("SUB")
.foregroundColor(.white)

Text("PREMIUM")
.foregroundColor(.red)

}
.font(.largeTitle.bold())

Text(isSignUp ? "Create your account" : "Welcome back")
.foregroundColor(.gray)

if isSignUp {

TextField("Username", text: $username)
.textInputAutocapitalization(.never)
.autocorrectionDisabled()
.textFieldStyle(.roundedBorder)

TextField("Nickname", text: $nickname)
.autocorrectionDisabled()
.textFieldStyle(.roundedBorder)

}

TextField("Email Address", text: $email)
.keyboardType(.emailAddress)
.textInputAutocapitalization(.never)
.autocorrectionDisabled()
.textFieldStyle(.roundedBorder)

HStack {

if showPassword {

TextField("Password", text: $password)

} else {

SecureField("Password", text: $password)

}

Button(showPassword ? "Hide" : "Show") {
showPassword.toggle()
}
.foregroundColor(.red)

}
.padding()
.background(Color.white)
.cornerRadius(12)
.foregroundColor(.black)

if !message.isEmpty {

Text(message)
.foregroundColor(.yellow)
.multilineTextAlignment(.center)
}

if isLoading {

ProgressView()
.tint(.white)

}

Button {

guard !email.isEmpty else {

message = "Enter your email."

return
}

guard !password.isEmpty else {

message = "Enter your password."

return
}

isLoading = true
message = ""

if isSignUp {

store.createAccount(
username: username,
nickname: nickname,
email: email,
password: password
) { error in

isLoading = false

if let error = error {

if error.localizedCaseInsensitiveContains("already") {

message = "This account already exists. Please Sign In."

isSignUp = false

} else {

message = error

}

} else {

message = ""

}

}

} else {

store.login(
email: email,
password: password
) { error in

isLoading = false

if let error = error {

if error.localizedCaseInsensitiveContains("not found") ||
error.localizedCaseInsensitiveContains("no user") ||
error.localizedCaseInsensitiveContains("user") {

message = "Account not found. Create one below."

isSignUp = true

} else if error.localizedCaseInsensitiveContains("password") {

message = "Incorrect password."

} else {

message = error

}

} else {

message = ""

}

}

}

} label: {

Text(isSignUp ? "Create Account" : "Sign In")
.font(.headline.bold())
.frame(maxWidth: .infinity)
.padding()
.background(Color.red)
.foregroundColor(.white)
.cornerRadius(15)

}
.disabled(isLoading)

Button {

guard !email.isEmpty else {

message = "Enter your email first."

return
}

Auth.auth().sendPasswordReset(withEmail: email) { error in

if let error = error {

message = error.localizedDescription

} else {

message = "Password reset email sent."

}

}

} label: {

Text("Forgot Password?")
.foregroundColor(.yellow)

}

Divider()
.background(Color.gray)

if isSignUp {

HStack {

Text("Already have an account?")
.foregroundColor(.gray)

Button("Sign In") {

message = ""
isSignUp = false

}
.foregroundColor(.red)
.bold()

}

} else {

HStack {

Text("Don't have an account?")
.foregroundColor(.gray)

Button("Create Account") {

message = ""
isSignUp = true

}
.foregroundColor(.red)
.bold()

}

}

Text("Everyone can create an account and watch videos.\nOnly administrators can upload videos.")
.font(.caption)
.foregroundColor(.gray)
.multilineTextAlignment(.center)
.padding(.top)

Spacer(minLength: 40)

}
.padding()

}
.background(Color.black.ignoresSafeArea())

}

}

struct IntroScreen: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("▷")
                .font(.system(size: 88, weight: .bold))
                .foregroundColor(.yellow)

            Text("SUB PREMIUM")
                .font(.largeTitle.bold())
                .foregroundColor(.yellow)

            Text("OTT Platform")
                .font(.title2.bold())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "070707"))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                onDone()
            }
        }
    }
}

struct MainAppScreen: View {
    @EnvironmentObject var store: AppStore

    @State private var page: AppPage = .home
    @State private var selectedVideo: VideoItem?
    @State private var searchText = ""
    @State private var notificationsRead = false

    var unreadCount: Int {
        notificationsRead ? 0 : store.videos.count
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                searchText: searchText,
                notificationCount: unreadCount,
                onSearch: { page = .search },
                onAlerts: {
                    notificationsRead = true
                    page = .alerts
                }
            )

            Group {
                switch page {
                case .home:
                    HomeScreen { video in
                        selectedVideo = video
                        page = .player
                    }

                case .search:
                    SearchScreen(searchText: $searchText, onBack: { page = .home }) { video in
                        selectedVideo = video
                        page = .player
                    }

                case .upload:
                    if let user = store.user, canUpload(user) {
                        UploadScreen()
                    } else {
                        HomeScreen { video in
                            selectedVideo = video
                            page = .player
                        }
                    }

                case .alerts:
                    NotificationsScreen { video in
                        selectedVideo = video
                        page = .player
                    }

                case .profile:
                    ProfileScreen()

                case .player:
                    if let selectedVideo {
                        VideoPlayerPage(
                            video: selectedVideo,
                            onBack: { page = .home },
                            onSelect: { video in self.selectedVideo = video },
                            onDelete: { video in
                                store.deleteVideo(video)
                                self.selectedVideo = nil
                                page = .home
                            },
                            onUpdate: { video in
                                store.updateVideo(video)
                                self.selectedVideo = video
                            }
                        )
                    } else {
                        HomeScreen { video in
                            selectedVideo = video
                            page = .player
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomNav(page: $page)
        }
        .background(Color(hex: "070707"))
    }
}

struct TopBar: View {
    var searchText: String
    var notificationCount: Int
    var onSearch: () -> Void
    var onAlerts: () -> Void

    @State private var showSubTV = true

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)

                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .font(.caption.bold())
            }

            if showSubTV {
                Text("SUB TV")
                    .font(.title3.bold())
                    .foregroundColor(.white)
            } else {
                HStack(spacing: 4) {
                    Text("SUB").foregroundColor(.white).bold()
                    Text("PREMIUM").foregroundColor(.yellow).bold()
                }
            }

            Spacer()

            Button(action: onSearch) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(searchText.isEmpty ? "Search" : String(searchText.prefix(12)))
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(hex: "0E0E14"))
                .cornerRadius(20)
            }
            .foregroundColor(.white)

            Button(action: onAlerts) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)

                    if notificationCount > 0 {
                        Text("\(notificationCount)")
                            .font(.caption2.bold())
                            .padding(5)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: "070707"))
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { _ in
                withAnimation { showSubTV.toggle() }
            }
        }
    }
}

struct BottomNav: View {
    @EnvironmentObject var store: AppStore
    @Binding var page: AppPage

    var body: some View {
        HStack {
            navButton(.home, "Home", "house.fill")

            if let user = store.user, canUpload(user) {
                Button {
                    page = .upload
                } label: {
                    VStack {
                        Text("+")
                            .font(.title.bold())
                            .frame(width: 50, height: 44)
                            .background(page == .upload ? Color.red : Color.gray)
                            .foregroundColor(.black)
                            .cornerRadius(14)
                        Text("Upload").font(.caption)
                    }
                }
                .foregroundColor(.white)
            }

            navButton(.alerts, "Alerts", "bell.fill")
            navButton(.profile, "Profile", "person.circle.fill")
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(hex: "17172A"))
    }

    func navButton(_ target: AppPage, _ title: String, _ icon: String) -> some View {
        Button {
            page = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(page == target ? .yellow : .white)
        }
    }
}

struct HomeScreen: View {
    @EnvironmentObject var store: AppStore
    var onVideoClick: (VideoItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome, SUB PREMIUM")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Button("Refresh Content") {
                    Task {
                        await refreshProcessingVideos()
                    }
                }
                .buttonStyle(.borderedProminent)

                if store.videos.isEmpty {
                    Text("No videos uploaded yet.")
                        .foregroundColor(.gray)
                        .padding(.top, 30)
                } else {
                    HeroSlider(videos: store.videos, onVideoClick: onVideoClick)

                    Text("Featured Videos")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(store.videos.prefix(3)) { video in
                                VideoCard(video: video)
                                    .frame(width: 300)
                                    .onTapGesture { onVideoClick(video) }
                            }
                        }
                    }

                    Text("Latest Videos")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    ForEach(store.videos) { video in
                        VideoCard(video: video)
                            .onTapGesture { onVideoClick(video) }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(hex: "070707"))
    }

    func refreshProcessingVideos() async {
        for video in store.videos where video.status == "processing" {
            do {
                let status = try await BackendService.shared.checkMuxUploadStatus(uploadId: video.id)
                if let hlsUrl = status.hlsUrl, let playbackId = status.playbackId {
                    var updated = video
                    updated.uri = hlsUrl
                    updated.playbackId = playbackId
                    updated.thumbnailUrl = status.thumbnailUrl
                    updated.status = "ready"
                    updated.durationText = "Now Streaming"
                    await MainActor.run {
                        store.updateVideo(updated)
                    }
                }
            } catch {}
        }
    }
}

struct HeroSlider: View {
    var videos: [VideoItem]
    var onVideoClick: (VideoItem) -> Void

    var body: some View {
        TabView {
            ForEach(videos.prefix(5)) { video in
                ZStack(alignment: .bottomLeading) {
                    VideoThumbnail(video: video)
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("FEATURED")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red)
                            .cornerRadius(6)

                        Text(video.title.uppercased())
                            .font(.title.bold())
                            .foregroundColor(.white)

                        Text("◷ \(video.durationText)")
                            .foregroundColor(.gray)

                        Button {
                            onVideoClick(video)
                        } label: {
                            Label("Watch Now", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(24)
                        }
                    }
                    .padding(18)
                }
                .cornerRadius(20)
                .padding(.horizontal, 2)
            }
        }
        .frame(height: 230)
        .tabViewStyle(.page)
    }
}

struct VideoCard: View {
    var video: VideoItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VideoThumbnail(video: video)

            VStack {
                HStack {
                    Spacer()
                    Text("◷ \(video.durationText)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(16)
                }
                Spacer()
                Text(video.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black.opacity(0.60))
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.black)
        .cornerRadius(20)
    }
}

struct VideoThumbnail: View {
    var video: VideoItem

    var body: some View {
        ZStack {
            if let thumbnailUrl = video.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }

            Circle()
                .fill(Color.red.opacity(0.9))
                .frame(width: 62, height: 62)

            Image(systemName: "play.fill")
                .font(.title)
                .foregroundColor(.white)
        }
        .clipped()
    }

    var placeholder: some View {
        ZStack {
            Color.black
            Text("SUB TV")
                .font(.headline.bold())
                .foregroundColor(.yellow)
        }
    }
}

struct VideoPlayerPage: View {
    @EnvironmentObject var store: AppStore

    var video: VideoItem
    var onBack: () -> Void
    var onSelect: (VideoItem) -> Void
    var onDelete: (VideoItem) -> Void
    var onUpdate: (VideoItem) -> Void

    @State private var expandedDescription = false
    @State private var liked = false
    @State private var disliked = false
    @State private var saved = false
    @State private var countdown: Int?
    @State private var showEdit = false
    @State private var showReport = false
    @State private var editTitle = ""
    @State private var editDescription = ""

    var suggested: [VideoItem] {
        store.videos.filter { $0.id != video.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("← Back", action: onBack)
                        .buttonStyle(.borderedProminent)

                    Spacer()

                    Menu {
                        Button("Edit video") {
                            editTitle = video.title
                            editDescription = video.description
                            showEdit = true
                        }

                        ShareLink(item: "\(video.title)\n\(video.uri)") {
                            Text("Share video")
                        }

                        Button("Report video") {
                            showReport = true
                        }

                        Button(role: .destructive) {
                            onDelete(video)
                        } label: {
                            Text("Delete video")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }

                VideoPlayerBox(video: video, countdown: countdown) {
                    startNextCountdown()
                }

                Text(video.title)
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text(expandedDescription ? video.description : String(video.description.prefix(100)))
                    .foregroundColor(.gray)

                if video.description.count > 100 {
                    Button(expandedDescription ? "View less" : "View more...") {
                        expandedDescription.toggle()
                    }
                    .foregroundColor(.yellow)
                }

                Text("\(video.uploader) • \(video.category) • \(video.durationText)")
                    .foregroundColor(.gray)

                HStack {
                    ActionButton(title: liked ? "Liked" : "Like", system: "hand.thumbsup", active: liked) {
                        liked.toggle()
                        if liked { disliked = false }
                    }

                    ActionButton(title: disliked ? "Disliked" : "Dislike", system: "hand.thumbsdown", active: disliked) {
                        disliked.toggle()
                        if disliked { liked = false }
                    }

                    ActionButton(title: "Download", system: "arrow.down.to.line", active: false) {}

                    ShareLink(item: "\(video.title)\n\(video.uri)") {
                        VStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share").font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                    }

                    ActionButton(title: saved ? "Saved" : "Save", system: "bookmark", active: saved) {
                        saved.toggle()
                    }
                }
                .padding()
                .background(Color(hex: "151515"))
                .cornerRadius(20)

                Text("Suggested Videos")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.top, 12)

                if suggested.isEmpty {
                    Text("No more videos yet.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(suggested) { item in
                        VideoCard(video: item)
                            .onTapGesture { onSelect(item) }
                    }
                }
            }
            .padding(14)
        }
        .background(Color(hex: "070707"))
        .alert("Report Video", isPresented: $showReport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thanks. This video report has been received for review.")
        }
        .sheet(isPresented: $showEdit) {
            NavigationView {
                VStack(spacing: 14) {
                    TextField("Title", text: $editTitle)
                        .textFieldStyle(.roundedBorder)

                    TextField("Description", text: $editDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...8)

                    Button("Save") {
                        var updated = video
                        updated.title = editTitle.isEmpty ? video.title : editTitle
                        updated.description = editDescription.isEmpty ? video.description : editDescription
                        onUpdate(updated)
                        showEdit = false
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
                .navigationTitle("Edit Video")
                .toolbar {
                    Button("Cancel") { showEdit = false }
                }
            }
        }
    }

    func startNextCountdown() {
        countdown = 5
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard let current = countdown else {
                timer.invalidate()
                return
            }

            if current <= 1 {
                timer.invalidate()
                countdown = nil
                if let currentIndex = store.videos.firstIndex(where: { $0.id == video.id }) {
                    let next = store.videos.indices.contains(currentIndex + 1) ? store.videos[currentIndex + 1] : store.videos.first
                    if let next, next.id != video.id {
                        onSelect(next)
                    }
                }
            } else {
                countdown = current - 1
            }
        }
    }
}

struct VideoPlayerBox: View {
    var video: VideoItem
    var countdown: Int?
    var onEnded: () -> Void

    @State private var player = AVPlayer()

    var body: some View {
        ZStack {
            if video.uri.starts(with: "http"), let url = URL(string: video.uri) {
                VideoPlayer(player: player)
                    .onAppear {
                        player.replaceCurrentItem(with: AVPlayerItem(url: url))
                        player.play()
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: nil,
                            queue: .main
                        ) { _ in
                            onEnded()
                        }
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                ZStack {
                    Color.black
                    Text("Video is still processing...")
                        .foregroundColor(.yellow)
                        .bold()
                }
            }

            if let countdown {
                Color.black.opacity(0.65)
                Text("Next video in \(countdown)")
                    .font(.title.bold())
                    .foregroundColor(.white)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.black)
        .cornerRadius(18)
    }
}

struct ActionButton: View {
    var title: String
    var system: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: system)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(active ? .red : .white)
        }
    }
}

struct UploadScreen: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var title = ""
    @State private var description = ""
    @State private var category = ""
    @State private var progress = 0
    @State private var isUploading = false
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Upload Video")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Label("Select Video From Phone", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        await loadSelectedVideo(newItem)
                    }
                }

                if let selectedVideoURL {
                    Text("Video Preview")
                        .foregroundColor(.yellow)
                        .bold()

                    VideoPlayer(player: AVPlayer(url: selectedVideoURL))
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(14)

                    TextField("Video title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    TextField("Description", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    TextField("Category", text: $category)
                        .textFieldStyle(.roundedBorder)

                    if isUploading {
                        ProgressView(value: Double(progress), total: 100)
                        Text("\(progress)%")
                            .foregroundColor(.yellow)
                    }

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.yellow)
                    }

                    Button {
                        Task {
                            await uploadVideo(fileURL: selectedVideoURL)
                        }
                    } label: {
                        Text(isUploading ? "Uploading..." : "Upload Video")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isUploading ? Color.gray : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(isUploading)
                }
            }
            .padding(20)
        }
        .background(Color(hex: "070707"))
    }

    func loadSelectedVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("subpremium_\(Date().timeIntervalSince1970).mp4")
                try data.write(to: temp)
                await MainActor.run {
                    selectedVideoURL = temp
                    progress = 0
                    message = ""
                }
            }
        } catch {
            await MainActor.run {
                message = "Failed to load selected video."
            }
        }
    }

    func uploadVideo(fileURL: URL) async {
        guard let user = store.user else { return }

        await MainActor.run {
            isUploading = true
            progress = 5
            message = "Creating Mux upload..."
        }

        do {
            let mux = try await BackendService.shared.createMuxUpload()

            await MainActor.run {
                progress = 25
                message = "Mux ID: \(mux.uploadId)"
            }

            try await BackendService.shared.uploadVideoToMux(fileURL: fileURL, uploadUrl: mux.uploadUrl) { value in
                Task { @MainActor in
                    progress = Int(value * 100)
                }
            }

            let newVideo = VideoItem(
                id: mux.uploadId,
                title: title.isEmpty ? "Untitled Video" : title,
                description: description.isEmpty ? "No description added." : description,
                uri: "",
                uploader: user.nickname,
                category: category.isEmpty ? "User Upload" : category,
                uploadProgress: 100,
                durationText: "Processing...",
                uploadedAt: "Just now",
                thumbnailUrl: nil,
                playbackId: nil,
                status: "processing"
            )

            await MainActor.run {
                store.addVideo(newVideo)
                progress = 100
                message = "Upload complete. Processing video..."
                isUploading = false
                selectedVideoURL = nil
                selectedItem = nil
                title = ""
                description = ""
                category = ""
            }
        } catch {
            await MainActor.run {
                message = "Failed: backend or Mux upload did not finish."
                progress = 0
                isUploading = false
            }
        }
    }
}

struct SearchScreen: View {
    @EnvironmentObject var store: AppStore

    @Binding var searchText: String
    var onBack: () -> Void
    var onVideoClick: (VideoItem) -> Void

    @State private var filter = "All"

    var results: [VideoItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.videos.filter { video in
            query.isEmpty ||
            video.title.localizedCaseInsensitiveContains(query) ||
            video.description.localizedCaseInsensitiveContains(query) ||
            video.category.localizedCaseInsensitiveContains(query) ||
            video.uploader.localizedCaseInsensitiveContains(query)
        }
        .filter { video in
            switch filter {
            case "Go Viral":
                return video.title.localizedCaseInsensitiveContains("viral") || video.category.localizedCaseInsensitiveContains("viral")
            case "Episode":
                return video.title.localizedCaseInsensitiveContains("episode") || video.category.localizedCaseInsensitiveContains("episode")
            default:
                return true
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("← World Search", action: onBack)
                    .foregroundColor(.red)
                    .bold()

                TextField("Search title, episode, playlist...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["All", "Trending", "FYP", "Go Viral", "Episode"], id: \.self) { item in
                            Button(item) {
                                filter = item
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(filter == item ? Color.red : Color(hex: "171717"))
                            .foregroundColor(.white)
                            .cornerRadius(24)
                        }
                    }
                }

                Text(searchText.isEmpty ? "All Videos" : "Results for \"\(searchText)\"")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                if results.isEmpty {
                    Text("No video found.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(results) { video in
                        VideoCard(video: video)
                            .onTapGesture { onVideoClick(video) }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(hex: "070707"))
    }
}

struct NotificationsScreen: View {
    @EnvironmentObject var store: AppStore
    var onVideoClick: (VideoItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Notifications")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("\(store.videos.count) upload update\(store.videos.count == 1 ? "" : "s")")
                    .foregroundColor(.gray)

                if store.videos.isEmpty {
                    Text("No notifications yet.")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    ForEach(store.videos) { video in
                        NotificationCard(video: video)
                            .onTapGesture { onVideoClick(video) }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(hex: "070707"))
    }
}

struct NotificationCard: View {
    var video: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            VideoThumbnail(video: video)
                .frame(width: 116, height: 66)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text("New video uploaded")
                    .foregroundColor(.yellow)
                    .bold()
                Text(video.title)
                    .foregroundColor(.white)
                    .bold()
                    .lineLimit(2)
                Text("\(video.uploader) • \(video.uploadedAt)")
                    .foregroundColor(.gray)
                    .font(.caption)
                Text("Tap to watch")
                    .foregroundColor(.gray)
                    .font(.caption)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(hex: "151515"))
        .cornerRadius(22)
    }
}

struct ProfileScreen: View {
    @EnvironmentObject var store: AppStore

    @State private var page: ProfilePage = .main
    @State private var notificationsOn = true
    @State private var editTitle = ""
    @State private var editValue = ""
    @State private var showEdit = false

    var body: some View {
        Group {
            switch page {
            case .main:
                ProfileMainPage(
                    notificationsOn: $notificationsOn,
                    onEdit: { title, value in
                        editTitle = title
                        editValue = value
                        showEdit = true
                    },
                    onHelp: { page = .help },
                    onRules: { page = .rules },
                    onReport: { page = .report },
                    onAbout: { page = .about }
                )

            case .help:
                SimpleSubPage(title: "Help Center", subtitle: "Get support for your account and videos.", onBack: { page = .main }) {
                    InfoCard(title: "Upload Help", subtitle: "Fix video upload, thumbnail, and playback issues.")
                    InfoCard(title: "Account Help", subtitle: "Recover account, password, username, and email.")
                    InfoCard(title: "Safety & Report", subtitle: "Report videos, users, or unsafe content.")
                    InfoCard(title: "Contact Support", subtitle: "Support email: subpremium760@gmail.com")
                }

            case .rules:
                SimpleSubPage(title: "Rules & Guidelines", subtitle: "Community rules for SUB PREMIUM TV.", onBack: { page = .main }) {
                    InfoCard(title: "No harmful content", subtitle: "Do not upload dangerous, hateful, or abusive videos.")
                    InfoCard(title: "Copyright", subtitle: "Only upload videos you own or have permission to share.")
                    InfoCard(title: "Respect users", subtitle: "No harassment, impersonation, spam, or fake activity.")
                    InfoCard(title: "Upload quality", subtitle: "Use real titles, descriptions, categories, and thumbnails.")
                }

            case .report:
                ReportIssuePage(onBack: { page = .main })

            case .about:
                SimpleSubPage(title: "About SUB PREMIUM TV", subtitle: "Free online OTT entertainment platform.", onBack: { page = .main }) {
                    InfoCard(title: "App Name", subtitle: "SUB PREMIUM TV")
                    InfoCard(title: "Version", subtitle: "1.0")
                    InfoCard(title: "Platform", subtitle: "Upload, watch, save, like, and manage OTT videos.")
                    InfoCard(title: "Storage", subtitle: "Videos and account data are saved locally for now.")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationView {
                VStack {
                    if editTitle == "Password" {
                        SecureField(editTitle, text: $editValue)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(editTitle, text: $editValue)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button("Save") {
                        guard var user = store.user else { return }

                        switch editTitle {
                        case "Username": user.username = editValue
                        case "Nickname": user.nickname = editValue
                        case "Email Address": user.email = editValue
                        case "Password": user.password = editValue
                        default: break
                        }

                        store.saveUser(user)
                        showEdit = false
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
                .navigationTitle("Edit \(editTitle)")
                .toolbar {
                    Button("Cancel") { showEdit = false }
                }
            }
        }
    }
}

struct ProfileMainPage: View {
    @EnvironmentObject var store: AppStore

    @Binding var notificationsOn: Bool

    var onEdit: (String, String) -> Void
    var onHelp: () -> Void
    var onRules: () -> Void
    var onReport: () -> Void
    var onAbout: () -> Void

    var body: some View {
        guard let user = store.user else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.8))
                                .frame(width: 158, height: 158)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 138, height: 138)

                            Circle()
                                .fill(Color.black)
                                .frame(width: 122, height: 122)

                            VStack {
                                Text("SUB")
                                    .foregroundColor(.white)
                                    .font(.title.bold())
                                Text("TV")
                                    .foregroundColor(.yellow)
                                    .font(.title2.bold())
                            }
                        }

                        Text(user.nickname)
                            .font(.title.bold())
                            .foregroundColor(.white)

                        Text("•  \(user.email)")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color(hex: "202027"))
                            .cornerRadius(24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(
                        LinearGradient(colors: [Color(hex: "19192E"), Color(hex: "09090E"), Color(hex: "070707")], startPoint: .top, endPoint: .bottom)
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Account Information")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        ProfileEditRow(label: "Username", value: user.username) {
                            onEdit("Username", user.username)
                        }

                        ProfileEditRow(label: "Nickname", value: user.nickname) {
                            onEdit("Nickname", user.nickname)
                        }

                        ProfileEditRow(label: "Email Address", value: user.email) {
                            onEdit("Email Address", user.email)
                        }

                        ProfileEditRow(label: "Password", value: "••••••••") {
                            onEdit("Password", user.password)
                        }

                        Text("Support")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        ProfileSupportCard(title: "Help Center", subtitle: "Upload, account, playback help", action: onHelp)
                        ProfileSupportCard(title: "Rules & Guidelines", subtitle: "Community and upload rules", action: onRules)
                        ProfileSupportCard(title: "Report Issue", subtitle: "Send concerns to support", action: onReport)
                        ProfileSupportCard(title: "About SUB PREMIUM TV", subtitle: "Version and platform info", action: onAbout)

                        Toggle(isOn: $notificationsOn) {
                            VStack(alignment: .leading) {
                                Text("Notifications").foregroundColor(.white).bold()
                                Text(notificationsOn ? "Push notifications on" : "Push notifications off")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                        .padding()
                        .background(Color(hex: "1B1B20"))
                        .cornerRadius(20)

                        Button {
                            store.logout()
                        } label: {
                            Text("Log Out")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                    }
                    .padding(20)
                }
            }
            .background(Color(hex: "070707"))
        )
    }
}

struct ProfileEditRow: View {
    var label: String
    var value: String
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .foregroundColor(.gray)
                    .bold()
                Spacer()
                Button("✎", action: onEdit)
                    .foregroundColor(.red)
            }

            Text(value)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(hex: "171717"))
                .cornerRadius(16)
        }
    }
}

struct ProfileSupportCard: View {
    var title: String
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Circle()
                    .fill(Color(hex: "442328"))
                    .frame(width: 54, height: 54)
                    .overlay(Text("!").foregroundColor(.red).bold())

                VStack(alignment: .leading) {
                    Text(title).foregroundColor(.white).bold()
                    Text(subtitle).foregroundColor(.gray).font(.caption)
                }

                Spacer()
                Text("›").font(.title).foregroundColor(.gray)
            }
            .padding()
            .background(Color(hex: "1B1B20"))
            .cornerRadius(24)
        }
    }
}

struct SimpleSubPage<Content: View>: View {
    var title: String
    var subtitle: String
    var onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("‹", action: onBack)
                    .font(.largeTitle)
                    .foregroundColor(.red)

                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text(subtitle)
                    .foregroundColor(.gray)

                content
            }
            .padding(20)
        }
        .background(Color(hex: "070707"))
    }
}

struct InfoCard: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: "442328"))
                .frame(width: 54, height: 54)
                .overlay(Text("i").foregroundColor(.red).bold())

            VStack(alignment: .leading) {
                Text(title).foregroundColor(.white).bold()
                Text(subtitle).foregroundColor(.gray)
            }

            Spacer()
        }
        .padding()
        .background(Color(hex: "1B1B20"))
        .cornerRadius(24)
    }
}

struct ReportIssuePage: View {
    @State private var issueTitle = ""
    @State private var issueBody = ""
    var onBack: () -> Void

    var body: some View {
        SimpleSubPage(title: "Report Issue", subtitle: "Send problems, video reports, account issues, or feedback.", onBack: onBack) {
            TextField("Issue title", text: $issueTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Explain the issue or concern...", text: $issueBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...10)

            Link(destination: mailURL()) {
                Text("Send Email to Support")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }

            Text("Support email: subpremium760@gmail.com")
                .foregroundColor(.gray)
        }
    }

    func mailURL() -> URL {
        let subject = issueTitle.isEmpty ? "SUB PREMIUM TV Report" : issueTitle
        let body = "Issue: \(issueTitle)\n\nDetails:\n\(issueBody)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:subpremium760@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)")!
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}
