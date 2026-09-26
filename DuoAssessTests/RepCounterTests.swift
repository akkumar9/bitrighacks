import Testing
import Foundation
@testable import DuoAssess

@Suite("RepCounter")
struct RepCounterTests {
    /// Feed a triangle wave of knee angles: 175 → bottom → 175 per entry in `bottoms`, 21 samples per
    /// cycle so the exact bottom is sampled.
    func run(_ counter: inout RepCounter, bottoms: [Double], valgusAt: Set<Int> = []) -> [Rep] {
        var reps: [Rep] = []
        var t = 0.0
        for (c, bottom) in bottoms.enumerated() {
            for i in 0...20 {
                let f = Double(i) / 20               // 0…1
                let tri = 1 - abs(2 * f - 1)         // 0 → 1 → 0
                let angle = 175 - (175 - bottom) * tri
                if let r = counter.update(kneeAngle: angle, isValgus: valgusAt.contains(c) && tri > 0.8, time: t) { reps.append(r) }
                t += 0.1
            }
        }
        return reps
    }

    @Test func countsFullReps() {
        var c = RepCounter()
        let reps = run(&c, bottoms: [90, 95, 85])
        #expect(reps.count == 3)
        #expect(c.reps.count == 3)
        #expect(reps.map(\.id) == [1, 2, 3])
        #expect(abs(reps[2].minKneeAngle - 85) < 1e-9)
        #expect(reps[0].startTime < reps[0].bottomTime && reps[0].bottomTime < reps[0].endTime)
        #expect(c.phase == .standing)
    }

    @Test func shallowDipsAreNotReps() {
        var c = RepCounter()
        let reps = run(&c, bottoms: [140, 90, 130])
        #expect(reps.count == 1)
        #expect(abs(reps[0].minKneeAngle - 90) < 1e-9)
    }

    @Test func valgusIsRecordedPerRep() {
        var c = RepCounter()
        let reps = run(&c, bottoms: [90, 90], valgusAt: [1])
        #expect(reps.map(\.hadValgus) == [false, true])
    }

    @Test func phasesProgressInOrder() {
        var c = RepCounter()
        var seen: [RepCounter.Phase] = []
        for i in 0...40 {
            let f = Double(i) / 40
            let angle = 175 - 90 * (1 - abs(2 * f - 1))
            c.update(kneeAngle: angle, isValgus: false, time: Double(i) * 0.05)
            if seen.last != c.phase { seen.append(c.phase) }
        }
        #expect(seen == [.standing, .descending, .bottom, .ascending, .standing])
    }

    @Test func currentRepNumberWhileSquatting() {
        var c = RepCounter()
        #expect(c.currentRepNumber == nil)
        c.update(kneeAngle: 140, isValgus: false, time: 0)
        #expect(c.currentRepNumber == 1)
        c.update(kneeAngle: 100, isValgus: false, time: 0.1)
        c.update(kneeAngle: 175, isValgus: false, time: 0.2)
        #expect(c.currentRepNumber == nil)
        #expect(c.reps.count == 1)
        c.update(kneeAngle: 140, isValgus: false, time: 0.3)
        #expect(c.currentRepNumber == 2)
    }
}
