import Testing
import Foundation
@testable import Tilawa

struct AnnotationEditorViewModelTests {

    private typealias MI = AnnotationEditorViewModel.MarkerInput

    private func marker(
        pos: Double,
        start: (surah: Int, ayah: Int)? = nil,
        end: (surah: Int, ayah: Int)? = nil
    ) -> MI {
        MI(
            positionSeconds: pos,
            assignedSurah: start?.surah,
            assignedAyah: start?.ayah,
            assignedEndSurah: end?.surah,
            assignedEndAyah: end?.ayah
        )
    }

    @Test func consecutiveStartMarkers_continuousSegments() {
        let markers = [
            marker(pos: 0, start: (1, 1)),
            marker(pos: 5, start: (1, 2)),
            marker(pos: 10, start: (1, 3)),
        ]
        let ranges = AnnotationEditorViewModel.buildSegmentRanges(from: markers, totalDuration: 60)
        #expect(ranges.count == 3)
        #expect(ranges[0].start == 0 && ranges[0].end == 5)
        #expect(ranges[1].start == 5 && ranges[1].end == 10)
        #expect(ranges[2].start == 10 && ranges[2].end == 60)
    }

    @Test func endOnlyMarker_stripsGap() {
        let markers = [
            marker(pos: 0, start: (1, 1)),
            marker(pos: 10, end: (1, 4)),
            marker(pos: 30, start: (112, 1)),
        ]
        let ranges = AnnotationEditorViewModel.buildSegmentRanges(from: markers, totalDuration: 60)
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0 && ranges[0].end == 10)
        #expect(ranges[1].start == 30 && ranges[1].end == 60)
    }

    @Test func bothEndAndStart_sameAyah_treatedAsEndOnly() {
        // The bug case: user edits a start-only marker to add an end ayah
        // for the same surah:ayah. Should close the segment, not reopen.
        let markers = [
            marker(pos: 0, start: (112, 1)),
            marker(pos: 10, start: (112, 4), end: (112, 4)),
            marker(pos: 30, start: (112, 1)),
        ]
        let ranges = AnnotationEditorViewModel.buildSegmentRanges(from: markers, totalDuration: 60)
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0 && ranges[0].end == 10)
        #expect(ranges[1].start == 30 && ranges[1].end == 60)
    }

    @Test func bothEndAndStart_differentAyah_transitionNoGap() {
        // Legitimate transition: ends 1:7, starts 112:1 at same position.
        // Should close and immediately reopen — no gap.
        let markers = [
            marker(pos: 0, start: (1, 1)),
            marker(pos: 10, start: (112, 1), end: (1, 7)),
        ]
        let ranges = AnnotationEditorViewModel.buildSegmentRanges(from: markers, totalDuration: 60)
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0 && ranges[0].end == 10)
        #expect(ranges[1].start == 10 && ranges[1].end == 60)
    }
}
