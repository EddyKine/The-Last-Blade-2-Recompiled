import SwiftUI
import AppKit
import Foundation

enum WindowMode: String, CaseIterable, Identifiable {
    case fullscreen
    case windowed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullscreen: return "PANTALLA COMPLETA"
        case .windowed: return "MODO VENTANA"
        }
    }
    var symbol: String {
        switch self {
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .windowed: return "macwindow"
        }
    }
}

struct ResolutionOption: Hashable, Identifiable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }
    static let all: [ResolutionOption] = [
        .init(width: 640, height: 480),
        .init(width: 1280, height: 960)
    ]
}

enum ScanlinePreset: String, CaseIterable, Identifiable {
    case original = "Original"
    case soft = "CRT Suave"
    case medium = "CRT Medio"
    var id: String { rawValue }
    var darkness: Double { self == .soft ? 0.14 : self == .medium ? 0.24 : 0 }
}

final class LauncherViewModel: ObservableObject {
    @AppStorage("tlb2.windowMode") var storedWindowMode: String = WindowMode.windowed.rawValue
    @AppStorage("tlb2.resolution") var storedResolution: String = ResolutionOption.all[0].id

    @AppStorage("tlb2.crtPreset") var storedPreset = "Original"
    @AppStorage("tlb2.crtIntensity") var storedIntensity = 100.0
    @Published var preset: ScanlinePreset = .original
    @Published var intensity = 100.0
    @Published var running = false
    @Published var mode: WindowMode = .windowed
    @Published var resolution: ResolutionOption = ResolutionOption.all[0]
    @Published var message: String?
    @Published var showOptions = false
    @Published var showCredits = false

    init() {
        preset = ScanlinePreset(rawValue: storedPreset) ?? .original
        intensity = storedIntensity
        mode = WindowMode(rawValue: storedWindowMode) ?? .windowed
        resolution = ResolutionOption.all.first(where: { $0.id == storedResolution }) ?? ResolutionOption.all[0]
    }

    func persist() {
        storedPreset = preset.rawValue
        storedIntensity = intensity
        storedWindowMode = mode.rawValue
        storedResolution = resolution.id
    }

    func play() {
        guard !running else { return }
        persist()
        let bundleURL = Bundle.main.bundleURL
        let useCRT = preset != .original && intensity > 0
        let bootURL = bundleURL.appendingPathComponent(useCRT ? "Contents/MacOS/thelastblade2_crt" : "Contents/MacOS/thelastblade2_boot")
        let gameURL = bundleURL.appendingPathComponent("Contents/Resources/Game")
        let configURL = gameURL.appendingPathComponent("thelastblade2.toml")

        guard FileManager.default.fileExists(atPath: bootURL.path) else {
            message = "No se encontró thelastblade2_boot en la app."
            return
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            message = "No se encontró thelastblade2.toml en la carpeta Game."
            return
        }

        let process = Process()
        process.executableURL = bootURL
        process.currentDirectoryURL = gameURL
        var args = ["--config", configURL.path, "--window", "--rtc-seed", "12345", "--scale", String(resolution.width / 640)]
        if mode == .fullscreen { args.append("--fullscreen") }
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        for key in ["TLB2_ALIGN16", "DREAM_NO_TILE_CLIP", "TLB2_NO_BYTE_COMPARE", "TLB2_NO_RECYCLE", "DREAM_NO_VRAM_INVALIDATE", "TLB2_NO_BATCH", "TLB2_LRU_EXPANDED", "TLB2_SCANLINES"] { env.removeValue(forKey: key) }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["TLB2_SCANLINES"] = String(preset.darkness * intensity / 100.0)
        process.environment = env
        let data = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/The Last Blade 2 Recompiled/Logs")
        let log = data.appendingPathComponent("v026-" + UUID().uuidString + ".txt")
        do {
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            try Data().write(to: log)
            let handle = try FileHandle(forWritingTo: log)
            process.standardOutput = handle
            process.standardError = handle
            process.terminationHandler = { p in
                try? handle.close()
                DispatchQueue.main.async {
                    self.running = false
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    if p.terminationStatus != 0 { self.message = "Error de ejecución. Informe: \(log.path)" }
                }
            }
            running = true
            try process.run()
            NSApp.hide(nil)
        } catch {
            running = false
            message = "No se pudo iniciar el juego: \(error.localizedDescription)"
        }
    }

    func controlsInfo() {
        message = "Configura tu mando dentro del juego.\n\nSugerencia:\n• Inicia el juego con JUGAR\n• Presiona F1 o Select para configurar y guardar los mandos\n• Prueba primero en 640 × 480 para la máxima compatibilidad"
    }

    func optionsInfo() {
        showOptions = true
    }

    func creditsInfo() {
        showCredits = true
    }
}

struct GoldOutlineButtonStyle: ButtonStyle {
    var fill: Color
    var border: Color = Color(red: 0.77, green: 0.63, blue: 0.36)
    var text: Color = Color(red: 0.97, green: 0.92, blue: 0.80)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .serif))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.82 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PanelActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(red: 0.97, green: 0.92, blue: 0.80))
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(red: 0.74, green: 0.60, blue: 0.34), lineWidth: 1.6)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    @StateObject private var model = LauncherViewModel()

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let url = Bundle.main.url(forResource: "TLB2_Launcher_Hero", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 650, height: 760, alignment: .top)
                        .background(Color(red: 0.05, green: 0.07, blue: 0.13))
                        .clipped()
                } else {
                    LinearGradient(colors: [.black, .gray], startPoint: .top, endPoint: .bottom)
                }
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.35), Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("FINAL EDITION")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.82))
                    Text("Dreamcast → macOS ARM64")
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text("Motor v0.23 estable · Portable v0.26")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .padding(30)
            }
            .frame(width: 650, height: 760).clipped()

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The Last Blade 2")
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.97, green: 0.92, blue: 0.82))
                    Text("Launcher Edition")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(2.2)
                        .foregroundStyle(Color(red: 0.80, green: 0.66, blue: 0.38))
                }
                .padding(.bottom, 4)

                Button("JUGAR") { model.play() }
                    .buttonStyle(GoldOutlineButtonStyle(fill: Color(red: 0.56, green: 0.14, blue: 0.14)))

                VStack(spacing: 6) {
                    Button {
                        model.mode = .fullscreen
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: WindowMode.fullscreen.symbol)
                                .frame(width: 26)
                            Text(WindowMode.fullscreen.title)
                            Spacer()
                            if model.mode == .fullscreen {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .foregroundStyle(Color(red: 0.97, green: 0.92, blue: 0.80))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.09, green: 0.13, blue: 0.21).opacity(0.95)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.74, green: 0.60, blue: 0.34), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.mode = .windowed
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: WindowMode.windowed.symbol)
                                .frame(width: 26)
                            Text(WindowMode.windowed.title)
                            Spacer()
                            if model.mode == .windowed {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .foregroundStyle(Color(red: 0.97, green: 0.92, blue: 0.80))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.09, green: 0.13, blue: 0.21).opacity(0.95)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.74, green: 0.60, blue: 0.34), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Rectangle().fill(Color(red: 0.74, green: 0.60, blue: 0.34)).frame(height: 1)
                        Text("RESOLUCIÓN")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .tracking(1.5)
                            .foregroundStyle(Color(red: 0.97, green: 0.92, blue: 0.80))
                        Rectangle().fill(Color(red: 0.74, green: 0.60, blue: 0.34)).frame(height: 1)
                    }
                    Picker("Resolución", selection: $model.resolution) {
                        ForEach(ResolutionOption.all, id: \.id) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(red: 0.74, green: 0.60, blue: 0.34), lineWidth: 1.5)
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("SCANLINES / CRT").font(.system(size: 13, weight: .semibold, design: .serif)).tracking(1)
                    Picker("Filtro", selection: $model.preset) {
                        ForEach(ScanlinePreset.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented).labelsHidden()
                    HStack {
                        Text("Intensidad").font(.system(size: 12))
                        Slider(value: $model.intensity, in: 0...150, step: 5).disabled(model.preset == .original)
                        Text("\(Int(model.intensity)) %").font(.system(size: 12).monospacedDigit()).frame(width: 46)
                    }
                }
                .foregroundStyle(Color(red: 0.97, green: 0.92, blue: 0.80))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                PanelActionButton(title: "CONFIGURAR MANDOS", systemImage: "gamecontroller", action: model.controlsInfo)
                PanelActionButton(title: "OPCIONES", systemImage: "gearshape.fill", action: model.optionsInfo)
                PanelActionButton(title: "CRÉDITOS", systemImage: "book.closed", action: model.creditsInfo)
                PanelActionButton(title: "SALIR", systemImage: "power", action: { NSApp.terminate(nil) })

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(Color(red: 0.74, green: 0.60, blue: 0.34).opacity(0.8))
                    Text("Motor v0.23 estable  |  Launcher v0.26")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color(red: 0.95, green: 0.90, blue: 0.82).opacity(0.95))
                    Text("Dreamcast → macOS ARM64")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(width: 390, height: 760)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.10, blue: 0.17), Color(red: 0.05, green: 0.07, blue: 0.13)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color(red: 0.74, green: 0.60, blue: 0.34), lineWidth: 1.2)
            )
        }
        .frame(width: 1040, height: 760)
        .preferredColorScheme(.dark)
        .background(Color.black)
        .onChange(of: model.preset) { _ in model.persist() }
        .onChange(of: model.intensity) { _ in model.persist() }
        .onChange(of: model.mode) { _ in model.persist() }
        .onChange(of: model.resolution) { _ in model.persist() }
        .sheet(isPresented: $model.showOptions) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Opciones")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text("Esta edición portable prioriza compatibilidad y estabilidad. La resolución recomendada es 640 × 480. El modo Original usa el motor v0.23 intacto. CRT utiliza una compilación separada con shader de presentación.")
                    .font(.system(size: 16))
                Text("La resolución 1280 × 960 es experimental. CRT Suave y Medio oscurecen las líneas un 14 % y 24 % al 100 % de intensidad.")
                    .font(.system(size: 15))
                Spacer()
                HStack {
                    Spacer()
                    Button("Cerrar") { model.showOptions = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(minWidth: 520, minHeight: 260)
        }
        .sheet(isPresented: $model.showCredits) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Créditos")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text("The Last Blade 2 Recompiled")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                Text("Motor estable v0.23 · Launcher Edition v0.26")
                Text("Dreamcast → macOS ARM64")
                Text("Recompilación y adaptación: EddyKine. Juego original: SNK. Ilustración del lanzador creada para este proyecto.")
                    .font(.system(size: 15))
                Spacer()
                HStack {
                    Spacer()
                    Button("Cerrar") { model.showCredits = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(minWidth: 540, minHeight: 280)
        }
        .alert("The Last Blade 2 Recompiled", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Aceptar", role: .cancel) { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

@main
struct TLB2LauncherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
