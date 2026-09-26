import Testing
import Foundation
@testable import DuoAssess

@Suite("GestureCounter")
struct GestureCounterTests {
    /// Triangle ramp 0 → top → 0 with `n` samples over /(n-1) so the peak is sampled.
    func ramp(_ c: inout GestureCounter, top: Double, n: Int = 21, t0: Double = 0, leftShare: Double = 0.5) -> [Gesture] {
        var out: [Gesture] = []
        for i in 0..<n {
            let f = Double(i) / Double(n - 1)
            let exc = top * (1 - abs(2 * f - 1))
            let l = exc * 2 * leftShare, r = exc * 2 * (1 - leftShare)
            if let g = c.update(excursion: exc, left: l, right: r, symmetryScore: 100 - 200 * abs(l - r), time: t0 + Double(i) * 0.1) { out.append(g) }
        }
        return out
    }

    @Test func walksThroughAllPhasesAndEmitsOne() {
        var c = GestureCounter()
        var seen: [GestureCounter.Phase] = [c.phase]
        var emitted: [Gesture] = []
        for i in 0..<41 {
            let f = Double(i) / 40
            let exc = 0.12 * (1 - abs(2 * f - 1))
            if let g = c.update(excursion: exc, left: exc, right: exc, symmetryScore: 100, time: Double(i) * 0.1) { emitted.append(g) }
            if seen.last != c.phase { seen.append(c.phase) }
        }
        #expect(seen == [.rest, .onset, .peak, .release, .rest])
        #expect(emitted.count == 1)
        #expect(c.gestures.count == 1)
        let g = emitted[0]
        #expect(abs(g.peakTime - 2.0) < 1e-9)
        #expect(g.startTime < g.peakTime && g.peakTime < g.endTime)
        #expect(g.affectedSide == .none)
    }

    @Test func onsetThatNeverPeaksEmitsNothing() {
        var c = GestureCounter()
        let gs = ramp(&c, top: 0.05)          // above onset 0.04, below peak 0.06
        #expect(gs.isEmpty)
        #expect(c.phase == .rest)
        #expect(c.currentGestureNumber == nil)
    }

    @Test func belowOnsetNeverStarts() {
        var c = GestureCounter()
        #expect(ramp(&c, top: 0.03).isEmpty)
    }

    @Test func countsRepeatedGesturesAndNumbersThem() {
        var c = GestureCounter()
        var all: [Gesture] = []
        for k in 0..<3 { all += ramp(&c, top: 0.10, t0: Double(k) * 5) }
        #expect(all.map(\.id) == [1, 2, 3])
        #expect(all.allSatisfy { $0.endTime - $0.startTime > 0 })
    }

    @Test func affectedSideFromPeakExcursions() {
        var c = GestureCounter()
        let weakRight = ramp(&c, top: 0.10, leftShare: 0.8)     // left moves 0.16, right 0.04 at peak
        #expect(weakRight.first?.affectedSide == .right)
        #expect(abs(weakRight.first!.peakExcursionLeft - 0.16) < 1e-9)
        var c2 = GestureCounter()
        #expect(ramp(&c2, top: 0.10, leftShare: 0.2).first?.affectedSide == .left)
        #expect(weakRight.first!.minSymmetryScore < 100)
    }
}
