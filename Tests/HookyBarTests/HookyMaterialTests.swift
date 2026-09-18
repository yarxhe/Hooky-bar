import AppKit
import SwiftUI
import Testing
@testable import HookyBar

@Suite(.serialized) @MainActor
struct HookyMaterialTests {
    @Test func togglingSelectionPreservesControlIdentity() async throws {
        let model = MaterialSelectionModel()
        let probe = MaterialIdentityProbe()
        let host = NSHostingView(rootView: MaterialSelectionFixture(model: model, probe: probe))
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -2200, width: 100, height: 40),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        #expect(probe.identities.count == 1)
        for _ in 0..<6 {
            model.selected.toggle()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        // A decoration change must not recreate controls, state or editors.
        #expect(Set(probe.identities).count == 1)
        #expect(probe.identities.count == 1)
    }

    @Test func reduceTransparencyUsesDarkOpaqueFillWithRoundedCorners() throws {
        let renderer = ImageRenderer(content:
            HookyMaterialSurface(cornerRadius: 12, reduceTransparency: true)
                .environment(\.colorScheme, .light)
                .frame(width: 80, height: 40)
        )
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let center = try #require(bitmap.colorAt(x: 40, y: 20)?.usingColorSpace(.sRGB))
        let corner = try #require(bitmap.colorAt(x: 0, y: 0))
        #expect(center.alphaComponent > 0.98)
        #expect(center.redComponent < 0.25)
        #expect(abs(center.redComponent - center.greenComponent) < 0.01)
        #expect(abs(center.greenComponent - center.blueComponent) < 0.01)
        #expect(corner.alphaComponent < 0.05)
    }

    @Test func decorationDoesNotChangeControlGeometry() throws {
        for enabled in [false, true] {
            let renderer = ImageRenderer(content:
                Color.red.frame(width: 83, height: 35)
                    .hookyMaterial(enabled: enabled, cornerRadius: 9)
            )
            let image = try #require(renderer.cgImage)
            #expect(image.width == 83)
            #expect(image.height == 35)
        }
    }
}

private final class MaterialSelectionModel: ObservableObject { @Published var selected = false }
private final class MaterialIdentityProbe { var identities: [UUID] = [] }
private final class MaterialIdentity: ObservableObject { let id = UUID() }
private struct MaterialControlFixture: View {
    @StateObject private var identity = MaterialIdentity()
    let probe: MaterialIdentityProbe
    var body: some View {
        Text("Control").onAppear { probe.identities.append(identity.id) }
    }
}
private struct MaterialSelectionFixture: View {
    @ObservedObject var model: MaterialSelectionModel
    let probe: MaterialIdentityProbe
    var body: some View {
        MaterialControlFixture(probe: probe)
            .frame(width: 100, height: 40)
            .hookyMaterial(enabled: model.selected, cornerRadius: 9)
    }
}
