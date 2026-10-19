// Scan SCX3405 — a tiny SwiftUI front-end for the bundled sane-backends
// "xerox_mfp" driver. No dependencies beyond the SANE payload installed at
// /Library/Printers/SCX3405/sane. Built with swiftc (see build-app.sh).
import SwiftUI
import AppKit

private let scanimage = "/Library/Printers/SCX3405/sane/bin/scanimage"
private let modes = ["Lineart", "Halftone", "Gray", "Color"]
private let resolutions = [75, 100, 150, 200, 300, 600]

enum Preset: String, CaseIterable, Identifiable {
    case colorPhoto = "Color photo"
    case grayPhoto  = "Black & white photo"
    case text       = "Text / document"

    var id: String { rawValue }
    var mode: String {
        switch self {
        case .colorPhoto: return "Color"
        case .grayPhoto:  return "Gray"
        case .text:       return "Lineart"
        }
    }
    var resolution: Int {
        switch self {
        case .colorPhoto, .grayPhoto: return 600
        case .text: return 300
        }
    }
    var blurb: String {
        switch self {
        case .colorPhoto: return "Photos and images — full 600 dpi colour."
        case .grayPhoto:  return "Photos and images in black & white — 600 dpi."
        case .text:       return "Documents, forms and text — fast, small files."
        }
    }
}

@main
struct ScanApp: App {
    var body: some Scene {
        WindowGroup("Scan — Samsung SCX-3405") { ContentView() }
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var preset: Preset = .colorPhoto
    @State private var showAdvanced = false
    @State private var customMode = "Color"
    @State private var customRes = 300
    @State private var destination = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Scans")
    @State private var scanning = false
    @State private var progress: Double = 0
    @State private var status = "Ready."
    @State private var saved: URL? = nil
    @State private var preview: NSImage? = nil

    private var mode: String { showAdvanced ? customMode : preset.mode }
    private var resolution: Int { showAdvanced ? customRes : preset.resolution }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Samsung SCX-3405").font(.title2).bold()
                    Text("Flatbed scanner").foregroundStyle(.secondary)
                }
            }

            Picker("Document type", selection: $preset) {
                ForEach(Preset.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.radioGroup)
            .disabled(scanning)

            Text(preset.blurb).font(.callout).foregroundStyle(.secondary)

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Mode")
                        Picker("", selection: $customMode) {
                            ForEach(modes, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                    }
                    GridRow {
                        Text("Resolution")
                        Picker("", selection: $customRes) {
                            ForEach(resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
                        }.labelsHidden()
                    }
                }
                .padding(.top, 6)
                .disabled(scanning)
            }

            HStack {
                Text("Save to").foregroundStyle(.secondary)
                Text(destination.path).lineLimit(1).truncationMode(.middle)
                    .font(.callout)
                Spacer()
                Button("Change…") { chooseFolder() }.disabled(scanning)
            }

            Divider()
            resultArea
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(width: 470)
    }

    @ViewBuilder private var resultArea: some View {
        if scanning {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            .frame(height: 200)
        } else if let img = preview, let url = saved {
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 190)
                    .background(Color(nsColor: .textBackgroundColor))
                    .border(Color(nsColor: .separatorColor))
                Text(url.lastPathComponent).font(.callout)
                HStack {
                    Button("Open") { NSWorkspace.shared.open(url) }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Spacer()
                }
            }
        } else {
            Text(status)
                .font(.callout).foregroundStyle(.secondary)
                .frame(height: 200, alignment: .topLeading)
        }
    }

    private var footer: some View {
        HStack {
            Button("Quit") { NSApp.terminate(nil) }
            Spacer()
            Button(scanning ? "Scanning…" : "Scan") { startScan() }
                .keyboardShortcut(.defaultAction)
                .disabled(scanning)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { destination = url }
    }

    private func startScan() {
        guard !scanning else { return }
        scanning = true
        progress = 0
        saved = nil
        preview = nil
        status = "Looking for the scanner…"

        let useMode = mode
        let useRes = resolution
        let folder = destination

        DispatchQueue.global(qos: .userInitiated).async {
            guard let dev = ScannerIO.findDevice() else {
                DispatchQueue.main.async {
                    self.scanning = false
                    self.status = "Scanner not found. Make sure the SCX-3405 is plugged in, "
                        + "turned on, and the lid is closed."
                }
                return
            }
            DispatchQueue.main.async { self.status = "Scanning at \(useRes) dpi…" }

            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Scan \(ScannerIO.stamp()).png")

            let ok = ScannerIO.runScan(device: dev, mode: useMode, resolution: useRes, to: url) { p in
                DispatchQueue.main.async { self.progress = p }
            }

            if ok, let img = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    self.scanning = false
                    self.progress = 1
                    self.saved = url
                    self.preview = img
                    self.status = "Saved to \(url.path)"
                }
            } else {
                DispatchQueue.main.async {
                    self.scanning = false
                    self.status = "Scan failed. Check the scanner is connected and try again."
                }
            }
        }
    }
}

enum ScannerIO {
    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f.string(from: Date())
    }

    /// Returns the first SANE device name, e.g. "xerox_mfp:libusb:000:001".
    static func findDevice() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: scanimage)
        p.arguments = ["-L"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if let r = line.range(of: "device `") {
                let rest = line[r.upperBound...]
                if let end = rest.firstIndex(of: "'") { return String(rest[..<end]) }
            }
        }
        return nil
    }

    /// Runs a single scan straight to `url`. `--jpeg=no` keeps the transfer
    /// lossless (the device's JPEG mode is lossy); the other options are the
    /// verified working set for the xerox_mfp flatbed.
    static func runScan(device: String, mode: String, resolution: Int, to url: URL,
                        progress: @escaping (Double) -> Void) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: url) else { return false }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: scanimage)
        p.arguments = ["-d", device, "--format=png", "--mode", mode,
                       "--resolution", "\(resolution)", "--jpeg=no", "-p"]
        let err = Pipe()
        p.standardOutput = fh
        p.standardError = err

        var buf = ""
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            buf += s
            if let r = buf.range(of: "Progress: ", options: .backwards) {
                let tail = buf[r.upperBound...]
                if let pct = tail.range(of: "%") {
                    let num = tail[..<pct.lowerBound].trimmingCharacters(in: .whitespaces)
                    if let v = Double(num) { progress(min(max(v / 100.0, 0), 1)) }
                }
            }
            if buf.count > 8192 { buf = String(buf.suffix(1024)) }
        }

        do { try p.run() } catch {
            err.fileHandleForReading.readabilityHandler = nil
            try? fh.close()
            return false
        }
        p.waitUntilExit()
        err.fileHandleForReading.readabilityHandler = nil
        try? fh.close()

        if p.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }
}
