import Combine
import Testing
@testable import HookyBar

@MainActor
struct InterfaceModelTests {
    @Test func repeatedInsideEventsDoNotRepublishStableShellState() {
        let model = InterfaceModel()
        model.setExpanded(true)
        var shellPublications = 0
        let token = model.$collapseSurfaceVisible.dropFirst().sink { _ in
            shellPublications += 1
        }
        for _ in 0..<100 { model.pointerInside(true) }
        #expect(shellPublications == 0)
        withExtendedLifetime(token) {}
    }
}
