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

    // MARK: - Merge adjacent markers

    @Test func mergeAdjacentMarkers_endOnlyAndStartOnlyAtSamePosition() {
        // After dead-space removal, end-only and start-only land at same position → merge
        let markers = [
            marker(pos: 0, start: (1, 1)),
            marker(pos: 10, end: (1, 4)),
            marker(pos: 10, start: (112, 1)),
        ]
        let result = AnnotationEditorViewModel.mergeAdjacentMarkerInputs(markers, totalDuration: 60)
        #expect(result.count == 2)
        #expect(result[0].assignedSurah == 1 && result[0].assignedAyah == 1)
        #expect(result[1].assignedEndSurah == 1 && result[1].assignedEndAyah == 4)
        #expect(result[1].assignedSurah == 112 && result[1].assignedAyah == 1)
    }

    @Test func mergeAdjacentMarkers_edgeEndOnlyAtStart() {
        let markers = [
            marker(pos: 0, end: (1, 7)),
            marker(pos: 5, start: (2, 1)),
        ]
        let result = AnnotationEditorViewModel.mergeAdjacentMarkerInputs(markers, totalDuration: 60)
        #expect(result.count == 1)
        #expect(result[0].assignedSurah == 2 && result[0].assignedAyah == 1)
    }

    @Test func mergeAdjacentMarkers_edgeStartOnlyAtEnd() {
        let markers = [
            marker(pos: 0, start: (1, 1)),
            marker(pos: 10, end: (1, 7)),
            marker(pos: 60, start: (2, 1)),
        ]
        let result = AnnotationEditorViewModel.mergeAdjacentMarkerInputs(markers, totalDuration: 60)
        #expect(result.count == 2)
        #expect(result[0].assignedSurah == 1)
        #expect(result[1].assignedEndSurah == 1 && result[1].assignedEndAyah == 7)
        #expect(result[1].assignedSurah == nil)
    }

    @Test func mergeAdjacentMarkers_noMergeNeeded() {
        let markers = [
            marker(pos: 0, start: (1, 1)),
            marker(pos: 10, start: (1, 2), end: (1, 1)),
            marker(pos: 20, start: (1, 3), end: (1, 2)),
        ]
        let result = AnnotationEditorViewModel.mergeAdjacentMarkerInputs(markers, totalDuration: 60)
        #expect(result.count == 3)
    }
}
