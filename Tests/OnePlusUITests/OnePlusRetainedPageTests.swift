import AppKit
import Observation
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusRetainedPageTests: XCTestCase {
    func testRetainedToolPageKeepsFullSizeWindowGeometryOnReturn() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let model = RetainedPageModel()
            model.selected = true
            let host = NSHostingView(rootView: OnePlusWindowRoot(canvas: .main) {
                OnePlusSidebarTitle("MacPowerToys")
            } content: {
                OnePlusRetainedPage(isSelected: model.selected, revision: 0) {
                    VStack(spacing: 0) {
                        OnePlusToolPageHeader(title: "Task Manager", subtitle: "Inspect processes and live system activity") {
                            RetainedGeometryProbe(id: "tool-icon")
                        } actions: { EmptyView() }
                        OnePlusTabStrip(tabs: [OnePlusTab(0, "Settings"), OnePlusTab(1, "How to use")], selection: .constant(0))
                        RetainedGeometryProbe(id: "display").frame(height: 40).padding(.horizontal, 24).padding(.top, 16)
                        Spacer(minLength: 0)
                    }
                }
            })
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1240, height: 840),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            defer { window.close() }
            for selected in [true, false, true] {
                model.selected = selected
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                host.layoutSubtreeIfNeeded()
                guard selected else { continue }
                for (id, expectedTop) in [("tool-icon", CGFloat(20)), ("display", 118)] {
                    let probe = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == id })
                    let frame = probe.convert(probe.bounds, to: host)
                    XCTAssertEqual(frame.minY, expectedTop, accuracy: 0.5, "\(appearance): \(id)")
                    XCTAssertEqual(frame.minX, 240, accuracy: 0.5)
                }
                XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foreground)
            }
        }
    }

    func testVisitedPageKeepsStateWithoutHiddenObservationOrSelectionRebuilds() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let model = RetainedPageModel()
        model.visible = false
        let probe = RetainedPageProbe()
        let host = NSHostingView(rootView: AnyView(RetainedPageFixture(model: model, probe: probe)))
        host.frame.size = CGSize(width: 480, height: 300)
        func settle() {
            autoreleasepool {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                host.layoutSubtreeIfNeeded()
            }
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foreground)
        }

        host.rootView = AnyView(RetainedPageFixture(model: model, probe: probe, retains: false))
        model.visible = true
        model.selected = true
        settle()
        let baselineBuilds = probe.builds
        for _ in 0..<20 { model.selectionNoise += 1; settle() }
        XCTAssertEqual(probe.builds - baselineBuilds, 20)
        host.rootView = AnyView(EmptyView())
        settle()
        model.selected = false
        model.visible = false
        probe.builds = 0
        host.rootView = AnyView(RetainedPageFixture(model: model, probe: probe))
        settle()
        XCTAssertEqual(probe.builds, 0, "Unvisited pages must stay lazy")
        model.selected = true
        settle()
        weak var retainedHost: NSView?
        autoreleasepool {
            retainedHost = descendants(host).dropFirst().first { $0 is NSHostingView<AnyView> }
        }
        XCTAssertNotNil(retainedHost)
        let token = try XCTUnwrap(probe.token)
        XCTAssertGreaterThan(probe.builds, 0, "Cold hidden hosts need a complete first frame")
        XCTAssertFalse(probe.visible)
        XCTAssertEqual(probe.runningTasks, 0)
        model.visible = true
        settle()
        XCTAssertEqual(probe.runningTasks, 1)
        let builds = probe.builds
        for _ in 0..<20 { model.selectionNoise += 1; settle() }
        XCTAssertEqual(probe.builds - builds, 0, "Selection must stay outside content equality")
        model.sample = 1
        settle()
        XCTAssertEqual(probe.sample, 1, "Visible observations must still update")

        model.selected = false
        settle()
        XCTAssertFalse(probe.visible, "Deliver hidden visibility before detaching")
        XCTAssertEqual(probe.runningTasks, 0)
        let hiddenBuilds = probe.builds
        for value in 2...21 { model.sample = value; settle() }
        XCTAssertEqual(probe.builds - hiddenBuilds, 0, "Hidden pages must drop live observations")
        model.revision = 1
        settle()
        model.selected = true
        settle()
        XCTAssertEqual(probe.token, token, "Return must preserve page state")
        XCTAssertEqual(probe.sample, 21, "Return must read the latest sample")
        XCTAssertEqual(probe.revision, 1, "Changed content inputs must reach the retained page")
        XCTAssertTrue(probe.visible)
        XCTAssertEqual(probe.runningTasks, 1)
        for _ in 0..<10 {
            model.selected = false; settle()
            model.selected = true; settle()
            XCTAssertEqual(probe.token, token)
        }

        model.visible = false
        settle()
        XCTAssertFalse(probe.visible)
        XCTAssertEqual(probe.runningTasks, 0)
        let coveredBuilds = probe.builds
        model.sample = 22
        settle()
        XCTAssertEqual(probe.builds, coveredBuilds)
        model.visible = true
        settle()
        XCTAssertEqual(probe.sample, 22)
        host.rootView = AnyView(EmptyView())
        settle()
        XCTAssertNil(retainedHost, "Removing the owning graph must release the cached host")
        XCTAssertEqual(probe.runningTasks, 0)
        print("Retained page: selection rebuilds before=20/20 after=0/20; hidden=0/20; state preserved=10/10")
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct RetainedGeometryProbe: NSViewRepresentable {
    let id: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(id)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor @Observable private final class RetainedPageModel {
    var selected = false
    var visible = true
    var selectionNoise = 0
    var revision = 0
    var sample = 0
}

@MainActor private final class RetainedPageProbe {
    var builds = 0
    var token: UUID?
    var sample = -1
    var revision = -1
    var visible = false
    var runningTasks = 0
}

private struct RetainedPageFixture: View {
    let model: RetainedPageModel
    let probe: RetainedPageProbe
    var retains = true

    var body: some View {
        let _ = model.selectionNoise
        let revision = model.revision
        Group {
            if retains {
                OnePlusRetainedPage(isSelected: model.selected, revision: revision) {
                    let _ = { probe.builds += 1 }()
                    RetainedPageLeaf(sample: model.sample, revision: revision, probe: probe)
                }
            } else if model.selected {
                let _ = { probe.builds += 1 }()
                RetainedPageLeaf(sample: model.sample, revision: revision, probe: probe)
            }
        }
        .environment(\.onePlusIsVisible, model.visible)
    }
}

private struct RetainedPageLeaf: View {
    let sample: Int
    let revision: Int
    let probe: RetainedPageProbe
    @Environment(\.onePlusIsVisible) private var visible
    @State private var token = UUID()

    var body: some View {
        let _ = { probe.token = token; probe.sample = sample; probe.revision = revision }()
        Text("Sample \(sample)")
            .onChange(of: visible, initial: true) { _, value in probe.visible = value }
            .task(id: visible) {
                guard visible else { return }
                probe.runningTasks += 1
                defer { probe.runningTasks -= 1 }
                try? await Task.sleep(for: .seconds(60))
            }
    }
}
