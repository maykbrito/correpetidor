import CorrepetidorCore
import SwiftUI

/// Dó2–Dó6; faixa do PC destacada.
struct PianoKeyboard: View {
    @EnvironmentObject var piano: Piano
    static let range = 36...84
    private static func isBlack(_ n: Int) -> Bool { [1, 3, 6, 8, 10].contains(n % 12) }
    private let whites = range.filter { !isBlack($0) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(whites.count)
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.element) { i, n in
                    key(n, black: false).frame(width: w - 1, height: h).offset(x: CGFloat(i) * w)
                }
                ForEach(Self.range.filter(Self.isBlack), id: \.self) { n in
                    let i = whites.firstIndex(of: n - 1) ?? 0
                    key(n, black: true).frame(width: w * 0.6, height: h * 0.6)
                        .offset(x: CGFloat(i + 1) * w - w * 0.3)
                }
            }
        }
        .frame(minHeight: 180)
    }

    private func key(_ n: Int, black: Bool) -> some View {
        let pc = KeyMap.key(for: n, octave: piano.octave)
        let on = piano.lit.contains(n)
        let base: Color = black ? .black : (pc != nil && piano.showKeys ? Color(white: 0.93) : .white)
        return RoundedRectangle(cornerRadius: 4)
            .fill(on ? Color.accentColor : base)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.5)))
            .overlay(alignment: .bottom) {
                VStack(spacing: 2) {
                    if piano.showKeys, let pc { Text(String(pc).uppercased()).bold() }
                    if piano.showNotes { Text(noteName(n)) }
                }
                .font(.system(size: black ? 8 : 10))
                .foregroundStyle(black ? .white : .secondary)
                .padding(.bottom, 6)
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !piano.lit.contains(n) { piano.noteOn(n) } }
                .onEnded { _ in piano.noteOff(n) })
    }
}
