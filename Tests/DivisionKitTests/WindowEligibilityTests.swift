import Testing
@testable import DivisionKit

@Test func pictureInPictureTitlesAreDetected() {
    #expect(WindowEligibility.isPictureInPictureTitle("Picture in Picture"))
    #expect(WindowEligibility.isPictureInPictureTitle("Picture-in-Picture"))
    #expect(WindowEligibility.isPictureInPictureTitle("picture-in-picture"))
    #expect(WindowEligibility.isPictureInPictureTitle("  Picture in Picture  "))
    #expect(WindowEligibility.isPictureInPictureTitle("ピクチャー イン ピクチャー"))
    #expect(WindowEligibility.isPictureInPictureTitle("ピクチャーインピクチャー"))
}

@Test func ordinaryWindowTitlesAreNotPictureInPicture() {
    #expect(!WindowEligibility.isPictureInPictureTitle(""))
    #expect(!WindowEligibility.isPictureInPictureTitle("YouTube"))
    #expect(!WindowEligibility.isPictureInPictureTitle("Picture in Picture API - Google Chrome"))
    #expect(!WindowEligibility.isPictureInPictureTitle("Wikipedia - Picture-in-Picture - Google Chrome"))
}

@Test func onlyNormalLayerIsTileable() {
    #expect(WindowEligibility.isNormalWindowLayer(0))
    #expect(!WindowEligibility.isNormalWindowLayer(3))
    #expect(!WindowEligibility.isNormalWindowLayer(-1))
}

@Test func shouldTileCombinesTitleAndLayer() {
    #expect(WindowEligibility.shouldTile(title: "Inbox", layer: 0))
    #expect(WindowEligibility.shouldTile(title: "Inbox", layer: nil))
    #expect(!WindowEligibility.shouldTile(title: "Picture in Picture", layer: 0))
    #expect(!WindowEligibility.shouldTile(title: "Inbox", layer: 3))
}
