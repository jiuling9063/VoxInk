import Testing
@testable import VoxInkUI

struct RecordingPulseTests {
    @Test func waveIsMirroredAndPeaksTravelOutward() {
        let early = (0.2 + 0.4) / (0.48 * 2.2)
        let later = (0.7 + 0.4) / (0.48 * 2.2)
        for index in 0...14 {
            #expect(RecordingPulse.sample(index: index, time: early, level: 0.8).height ==
                    RecordingPulse.sample(index: -index, time: early, level: 0.8).height)
        }
        #expect(RecordingPulse.sample(index: 3, time: early, level: 0.8).height > RecordingPulse.sample(index: 10, time: early, level: 0.8).height)
        #expect(RecordingPulse.sample(index: 10, time: later, level: 0.8).height > RecordingPulse.sample(index: 3, time: later, level: 0.8).height)
    }

    @Test func louderPeaksAreTallerAndBrighterWithoutHidingSilence() {
        let time = 0.4 / (0.48 * 2.2)
        let quiet = RecordingPulse.sample(index: 0, time: time, level: 0)
        let loud = RecordingPulse.sample(index: 0, time: time, level: 1)
        #expect(loud.height > quiet.height)
        #expect(loud.opacity > quiet.opacity)
        #expect(quiet.height > 0 && quiet.opacity >= 0.46)
    }

    @Test func trailingWaveIsVisibleButWeakerThanMainPeak() {
        let time = (0.7 + 0.4) / (0.48 * 2.2)
        let main = RecordingPulse.sample(index: 10, time: time, level: 0.8)
        let tail = RecordingPulse.sample(index: 5, time: time, level: 0.8)
        let baseline = RecordingPulse.sample(index: 0, time: time, level: 0.8)
        #expect(tail.height > baseline.height)
        #expect(tail.height < main.height)
        #expect(tail.opacity < main.opacity)
    }

    @Test func invalidInputsAndReducedMotionStayStable() {
        for level in [Double.nan, .infinity, -1, 2] {
            let sample = RecordingPulse.sample(index: 0, time: .infinity, level: level)
            #expect(sample.height.isFinite && sample.height <= 33.4)
            #expect(sample.opacity >= 0.46 && sample.opacity <= 1)
        }
        for index in -14...14 {
            let first = RecordingPulse.sample(index: index, time: 0, level: 0, reduceMotion: true)
            let next = RecordingPulse.sample(index: index, time: 10, level: 1, reduceMotion: true)
            #expect(first.height == next.height)
            if abs(index) < 14 { #expect(next.opacity > first.opacity) }
        }
    }
}
