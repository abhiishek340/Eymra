import Testing
@testable import Eymra

struct PlatformPresetTests {
    @Test func everyPresetIsConsistent() {
        for p in PlatformPreset.all {
            #expect(p.defaultCount >= 1 && p.defaultCount <= p.maxCount)
            #expect(!p.ratios.isEmpty)
        }
        #expect(PlatformPreset.preset(.instagramCarousel).defaultCount == 10)
        #expect(PlatformPreset.preset(.instagramCarousel).maxCount == 20)
        #expect(PlatformPreset.preset(.reels).primaryRatio == .vertical9x16)
        #expect(Set(PlatformPreset.all.map(\.id)) == Set(PlatformPreset.ID.allCases))
    }

    @Test func ratioValues() {
        #expect(AspectRatio.portrait4x5.value == 0.8)
        #expect(AspectRatio.vertical9x16.value < 1)
        #expect(AspectRatio.landscape191x1.value == 1.91)
    }
}
