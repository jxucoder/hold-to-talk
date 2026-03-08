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

    func testModelLinksPointToExpectedSources() throws {
        let openAIModel = try XCTUnwrap(WhisperModelInfo.all.first(where: { $0.id == "large-v3_turbo" }))
        XCTAssertEqual(openAIModel.repoFolderName, "openai_whisper-large-v3_turbo")
        XCTAssertEqual(openAIModel.downloadURL.absoluteString, "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3_turbo")
        XCTAssertEqual(openAIModel.familyDisplayName, "OpenAI Whisper")
        XCTAssertEqual(openAIModel.familyURL.absoluteString, "https://github.com/openai/whisper")

        let distilledModel = try XCTUnwrap(WhisperModelInfo.all.first(where: { $0.id == "distil-large-v3" }))
        XCTAssertEqual(distilledModel.repoFolderName, "distil-whisper_distil-large-v3")
        XCTAssertEqual(distilledModel.downloadURL.absoluteString, "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/distil-whisper_distil-large-v3")
        XCTAssertEqual(distilledModel.familyDisplayName, "Distil-Whisper")
        XCTAssertEqual(distilledModel.familyURL.absoluteString, "https://huggingface.co/distil-whisper/distil-large-v3")
    }
}
