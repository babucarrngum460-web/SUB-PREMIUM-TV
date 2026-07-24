import SwiftUI
import AVKit

struct TestPlayerView: View {
    let player = AVPlayer(
        url: URL(string: "https://stream.mux.com/jqj8NJb4QYgCcwFookPk2pQoXPsd00qRSpZzTqdk00UfY.m3u8")!
    )
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.play()
            }
    }
}
