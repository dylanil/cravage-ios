import XCTest
@testable import CravageCore
@testable import Cravage

/// Tools/screenshots.sh trusts each staged scene to land on the screen it is named for. A protocol
/// change that stalls the staged round would otherwise produce a set of wrong screenshots silently.
///
/// The stage exists only in Debug builds, so these tests do too: a Release test run would not
/// compile them, and CI runs tests in Debug only.
@MainActor
final class ScreenshotStageTests: XCTestCase {

    func testEveryStagedSceneShowsTheScreenItIsNamedFor() async {
        let expected: [ScreenshotStage.Scene: Screen] = [
            .home: .home, .newRoom: .newRoom, .lobby: .lobbyHost, .confirmCode: .confirmCode,
            .enterFigure: .enterFigure, .waiting: .waiting, .result: .result(.agreed),
        ]
        for scene in ScreenshotStage.Scene.allCases {
            let stage = ScreenshotStage(scene: scene)
            await stage.run(hostNickname: "Alice")
            XCTAssertEqual(Screen(stage.coordinator, idle: stage.idle), expected[scene], "\(scene)")
        }
    }

    func testTheStagedLobbyHasSomeoneAtTheDoorAndTheResultIsTheStagedAverage() async {
        let lobby = ScreenshotStage(scene: .lobby)
        await lobby.run(hostNickname: "Alice")
        XCTAssertEqual(lobby.coordinator.engine.pendingJoiners.count, 1)
        XCTAssertEqual(lobby.coordinator.engine.admittedCount, 1)

        let result = ScreenshotStage(scene: .result)
        await result.run(hostNickname: "Alice")
        XCTAssertEqual(result.coordinator.engine.average, "8.83")
    }

    func testRunningASceneAgainLeavesTheRoomAsItWas() async {
        let stage = ScreenshotStage(scene: .lobby)
        await stage.run(hostNickname: "Alice")
        await stage.run(hostNickname: "Alice")
        XCTAssertEqual(stage.coordinator.engine.pendingJoiners.count, 1)
        XCTAssertEqual(stage.coordinator.engine.admittedCount, 1)
    }

    func testOnlyTheFigureSceneStartsWithAFigureTypedIn() {
        for scene in ScreenshotStage.Scene.allCases {
            XCTAssertEqual(ScreenshotStage.draftFigure(for: scene), scene == .enterFigure ? "12" : nil, "\(scene)")
        }
    }
}
