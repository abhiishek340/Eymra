import Foundation
import Testing
@testable import Eymra

struct SegmentationTests {
    @Test func steadyShootingIsOneScene() {
        let photos = (0..<30).map { Make.photo("p\($0)", at: Double($0) * 30) }
        #expect(Segmentation.segment(photos: photos, features: [:]).count == 1)
    }

    @Test func largeGapCutsAScene() {
        let first = (0..<20).map { Make.photo("a\($0)", at: Double($0) * 20) }
        let second = (0..<20).map { Make.photo("b\($0)", at: 3 * 3600 + Double($0) * 20) }
        let scenes = Segmentation.segment(photos: first + second, features: [:])
        #expect(scenes.count == 2)
        #expect(scenes[0].photoIDs.count == 20)
        #expect(scenes[1].photoIDs.first == "b0")
    }

    @Test func adaptiveGapNeedsThreeMinutesMinimum() {
        // Shots every 2 s, then a 150 s gap: far bigger than neighbours, but under the 3-minute floor.
        let a = (0..<15).map { Make.photo("a\($0)", at: Double($0) * 2) }
        let b = (0..<15).map { Make.photo("b\($0)", at: 28 + 150 + Double($0) * 2) }
        #expect(Segmentation.segment(photos: a + b, features: [:]).count == 1)
        // The same pattern with a 20-minute gap is cut by Rule A.
        let c = (0..<15).map { Make.photo("c\($0)", at: 28 + 1200 + Double($0) * 2) }
        #expect(Segmentation.segment(photos: a + c, features: [:]).count == 2)
    }

    @Test func locationJumpCutsEvenInsideThreeMinutes() {
        let here = GeoPoint(latitude: 46.0, longitude: 7.7, horizontalAccuracy: 10)
        let there = GeoPoint(latitude: 46.01, longitude: 7.7, horizontalAccuracy: 10)   // ≈ 1.1 km north
        let photos = [Make.photo("a", at: 0, location: here), Make.photo("b", at: 30, location: here),
                      Make.photo("c", at: 60, location: there)]
        #expect(Segmentation.segment(photos: photos, features: [:]).count == 2)
    }

    @Test func inaccurateLocationNeverCuts() {
        let here = GeoPoint(latitude: 46.0, longitude: 7.7, horizontalAccuracy: 500)
        let there = GeoPoint(latitude: 46.01, longitude: 7.7, horizontalAccuracy: 500)
        let photos = [Make.photo("a", at: 0, location: here), Make.photo("b", at: 30, location: there)]
        #expect(Segmentation.segment(photos: photos, features: [:]).count == 1)
    }

    @Test func sceneRecordsCentroidAndMeanPrint() {
        let loc = GeoPoint(latitude: 10, longitude: 20, horizontalAccuracy: 5)
        let photos = [Make.photo("a", at: 0, location: loc), Make.photo("b", at: 10, location: loc)]
        let features = ["a": Make.feature("a", print: [1, 0]), "b": Make.feature("b", print: [0, 1])]
        let scene = Segmentation.segment(photos: photos, features: features)[0]
        #expect(scene.centroid?.latitude == 10)
        #expect(scene.meanPrint == [0.5, 0.5])
    }

    @Test func haversineIsAboutRight() {
        let a = GeoPoint(latitude: 0, longitude: 0, horizontalAccuracy: 1)
        let b = GeoPoint(latitude: 0, longitude: 1, horizontalAccuracy: 1)
        #expect(abs(Segmentation.haversine(a, b) - 111_195) < 200)
    }
}
