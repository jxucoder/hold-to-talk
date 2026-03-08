import XCTest
@testable import HoldToTalk

final class WhisperModelInfoTests: XCTestCase {
    func testModelIDFromSupportEntryHandlesOpenAIVariants() {
        XCTAssertEqual(
            WhisperModelInfo.modelID(fromSupportEntry: "openai_whisper-large-v3_turbo_954MB"),
            "large-v3_turbo"
        )
    }

    func testModelIDFromSupportEntryHandlesDistilledVariants() {
        XCTAssertEqual(
            WhisperModelInfo.modelID(fromSupportEntry: "distil-whisper_distil-large-v3_594MB"),
            "distil-large-v3"
        )
        XCTAssertEqual(
            WhisperModelInfo.modelID(fromSupportEntry: "distil-whisper_distil-large-v3_turbo_600MB"),
            "distil-large-v3_turbo"
        )
    }

    func testModelIDFromRepoFolderNameHandlesKnownPrefixes() {
        XCTAssertEqual(
            WhisperModelInfo.modelID(fromRepoFolderName: "openai_whisper-small.en"),
            "small.en"
        )
        XCTAssertEqual(
            WhisperModelInfo.modelID(fromRepoFolderName: "distil-whisper_distil-large-v3"),
            "distil-large-v3"
        )
    }

    func testCatalogIncludesDistilledEnglishOnlyModels() {
        let ids = Set(WhisperModelInfo.all.map(\.id))
        XCTAssertTrue(ids.contains("distil-large-v3"))
        XCTAssertTrue(ids.contains("distil-large-v3_turbo"))

        XCTAssertTrue(WhisperModelInfo.all.first(where: { $0.id == "distil-large-v3" })?.englishOnly == true)
        XCTAssertTrue(WhisperModelInfo.all.first(where: { $0.id == "distil-large-v3_turbo" })?.englishOnly == true)
    }
}
