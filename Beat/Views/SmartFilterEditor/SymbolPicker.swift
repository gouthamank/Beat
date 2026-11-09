import SwiftUI

struct SymbolPicker: View {
    @Binding var symbol: String
    let done: () -> Void

    static let symbols = [
        "line.3.horizontal.decrease.circle", "star", "heart", "flame", "sparkles", "bolt",
        "clock", "calendar", "calendar.badge.plus", "clock.arrow.circlepath", "hourglass", "dice",
        "music.note", "music.note.list", "music.microphone", "guitars", "pianokeys", "headphones",
        "hifispeaker", "radio", "metronome", "waveform", "opticaldisc", "record.circle",
        "moon", "sun.max", "leaf", "cloud.rain", "snowflake", "globe",
        "car", "airplane", "figure.run", "cup.and.saucer", "party.popper", "gift",
        "crown", "trophy", "wand.and.stars", "book", "gamecontroller", "house",
        "folder", "rectangle.grid.1x2", "square.stack", "tag", "building.2", "archivebox",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6), spacing: 6) {
            ForEach(Self.symbols, id: \.self) { name in
                Button {
                    symbol = name
                    done()
                } label: {
                    Image(systemName: name)
                        .font(.system(size: 16))
                        .frame(width: 36, height: 32)
                        .foregroundStyle(name == symbol ? Color.white : Color.primary)
                        .background(name == symbol ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
        .padding(12)
    }
}
