import AppKit
import SwiftUI

/// Places the actual app views in a synthetic desktop, following qeq's documentation scene.
/// Wallpaper, window chrome, and the system menu bar are illustrated; no desktop is captured.
@MainActor struct DesktopScreenshot: View {
    static let size = CGSize(width: 1800, height: 1125)
    let app: AppState
    private let windowOrigin = CGPoint(x: 80, y: 155)
    private let panelOrigin = CGPoint(x: 1420, y: 33)
    private let statusIconX: CGFloat = 1510

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            mainWindow.offset(x: windowOrigin.x, y: windowOrigin.y)
            menuBar
            menuPanel.offset(x: panelOrigin.x, y: panelOrigin.y)
        }.frame(width: Self.size.width, height: Self.size.height).clipped()
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x111B42), Color(hex: 0x344B78), Color(hex: 0x826680)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Ellipse().fill(LinearGradient(colors: [Color(hex: 0x9B82BC), Color(hex: 0x344978)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 2574, height: 1260).rotationEffect(.degrees(-27)).offset(x: -558, y: 342).shadow(color: .black.opacity(0.3), radius: 126, x: 54, y: 18)
            Ellipse().fill(LinearGradient(colors: [Color(hex: 0x5798C1), Color(hex: 0x1B4775), Color(hex: 0x0A203F)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 2412, height: 936).rotationEffect(.degrees(-32)).offset(x: -648, y: 612).shadow(
                color: Color(hex: 0x121F47).opacity(0.55), radius: 81, x: 0, y: -36)
            Ellipse().fill(LinearGradient(colors: [Color(hex: 0x42789E), Color(hex: 0x0A1A3B)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 2520, height: 810).rotationEffect(.degrees(-30)).offset(x: -324, y: 1044)
        }.frame(width: Self.size.width, height: Self.size.height).clipped()
    }

    private var mainWindow: some View {
        // Match the live macOS 26 NavigationSplitView: an inset, rounded sidebar
        // with controls inside it, and detail content extending behind the toolbar.
        // WindowServer supplies that shape in the app but not in cacheDisplay.
        HStack(spacing: 0) {
            DeviceSidebarView(deviceStore: app.deviceStore).safeAreaInset(edge: .top, spacing: 0) { sidebarWindowControls }.frame(width: 260).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).padding(8)
            if let selected = app.deviceStore.selectedDevice, let state = app.deviceStore.state { DeviceDetailView(deviceStore: app.deviceStore, editorStore: app.editorStore, selected: selected, state: state).padding(.top, 44) }
        }.frame(width: 1250, height: 880).background(LinearGradient(colors: [Color(hex: 0x0E1218), Color(hex: 0x121D15)], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)).overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
        ).shadow(color: .black.opacity(0.48), radius: 30, x: 0, y: 18)
    }

    private var sidebarWindowControls: some View {
        HStack(spacing: 8) {
            ForEach([UInt32(0xFF5F57), 0xFEBC2E, 0x28C840], id: \.self) { color in Circle().fill(Color(hex: color)).overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5)).frame(width: 14, height: 14) }
            Spacer()
            Image(systemName: "sidebar.left").font(.system(size: 17)).foregroundStyle(.white.opacity(0.45))
        }.padding(.horizontal, 12).frame(height: 44)
    }

    private var menuBar: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black.opacity(0.15)).overlay(.white.opacity(0.07)).frame(height: 30)
            HStack(spacing: 22) {
                Image(systemName: "apple.logo").font(.system(size: 16))
                Text("OpenSnek").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Text("View")
                Text("Window")
                Text("Help")
            }.font(.system(size: 13)).frame(height: 30).padding(.leading, 20)
            RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.22)).frame(width: 34, height: 26).position(x: statusIconX, y: 15)
            if let icon = OpenSnekBranding.menuIcon { Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit().frame(width: 22, height: 22).position(x: statusIconX, y: 15) }
            Image(systemName: "wifi").position(x: 1554, y: 15)
            Image(systemName: "switch.2").position(x: 1594, y: 15)
            Image(systemName: "battery.100percent").position(x: 1634, y: 15)
            Text("Thu 9:41 AM").font(.system(size: 13, weight: .medium)).position(x: 1723, y: 15)
        }.font(.system(size: 14)).foregroundStyle(.white.opacity(0.95)).frame(width: Self.size.width, height: 30)
    }

    private var menuPanel: some View {
        ServiceMenuBarView(deviceStore: app.deviceStore, editorStore: app.editorStore, runtimeStore: app.runtimeStore).fixedSize(horizontal: false, vertical: true).padding(.top, 10).background(
            LinearGradient(colors: [Color(hex: 0x26313F), Color(hex: 0x192330)], startPoint: .topLeading, endPoint: .bottomTrailing)
        ).clipShape(PopoverOutline(arrowX: statusIconX - panelOrigin.x)).overlay(PopoverOutline(arrowX: statusIconX - panelOrigin.x).stroke(.white.opacity(0.25), lineWidth: 0.5)).shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 12)
    }

    /// Reproduces the menu bar popover's arrow and rounded outline for offscreen rendering.
    private struct PopoverOutline: Shape {
        let arrowX: CGFloat

        func path(in rect: CGRect) -> Path {
            Path { path in
                let radius: CGFloat = 12
                let top = rect.minY + 10
                path.move(to: CGPoint(x: rect.minX + radius, y: top))
                path.addLine(to: CGPoint(x: arrowX - 10, y: top))
                path.addLine(to: CGPoint(x: arrowX, y: rect.minY))
                path.addLine(to: CGPoint(x: arrowX + 10, y: top))
                path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + radius), control: CGPoint(x: rect.maxX, y: top))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
                path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
                path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
                path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: top), control: CGPoint(x: rect.minX, y: top))
                path.closeSubpath()
            }
        }
    }
}
