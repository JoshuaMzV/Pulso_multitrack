import SwiftUI
import UniformTypeIdentifiers

/// Modelo temporal para mapear cada pista durante el asistente de subida
struct StemMappingEntry: Identifiable, Codable {
    let id: String
    var originalFilename: String
    var label: String
    var category: String
    var bus: Int // 0: Master, 1: Auriculares/Click

    var categoryColor: Color {
        switch category.lowercased() {
        case "click": return Color(hexString: "#9297A0")
        case "guide": return Color(hexString: "#F0A028")
        case "drums": return Color(hexString: "#FF4B33")
        case "bass": return Color(hexString: "#3DDC84")
        case "keys", "piano": return Color(hexString: "#4DA6FF")
        case "pad": return Color(hexString: "#B388FF")
        case "guitars": return Color(hexString: "#FFBE55")
        case "vocals": return Color(hexString: "#EC4899")
        default: return Color(hexString: "#C3C7CC")
        }
    }
}

/// Helper nativo para inspeccionar archivos de audio dentro de un ZIP sin dependencias externas
struct NativeZipInspector {
    static func extractAudioFilenames(from data: Data) -> [String] {
        var names: [String] = []
        let audioExts = ["wav", "mp3", "m4a", "flac", "aac", "aif", "aiff"]
        let bytes = [UInt8](data)
        let total = bytes.count
        var i = 0

        // 1. Escanear cabeceras centrales (0x02014B50) y locales (0x04034B50)
        while i < total - 30 {
            let isLocal = (bytes[i] == 0x50 && bytes[i+1] == 0x4B && bytes[i+2] == 0x03 && bytes[i+3] == 0x04)
            let isCentral = (bytes[i] == 0x50 && bytes[i+1] == 0x4B && bytes[i+2] == 0x01 && bytes[i+3] == 0x02)

            if isCentral && i < total - 46 {
                let nameLen = Int(bytes[i+28]) | (Int(bytes[i+29]) << 8)
                let extraLen = Int(bytes[i+30]) | (Int(bytes[i+31]) << 8)
                let commentLen = Int(bytes[i+32]) | (Int(bytes[i+33]) << 8)
                let nameStart = i + 46
                if nameStart + nameLen <= total {
                    if let filename = String(bytes: bytes[nameStart..<nameStart+nameLen], encoding: .utf8) ?? String(bytes: bytes[nameStart..<nameStart+nameLen], encoding: .ascii) {
                        let base = (filename as NSString).lastPathComponent
                        let ext = (base as NSString).pathExtension.lowercased()
                        if !base.hasPrefix(".") && !base.hasPrefix("__MACOSX") && audioExts.contains(ext) && !names.contains(base) {
                            names.append(base)
                        }
                    }
                }
                i += 46 + nameLen + extraLen + commentLen
            } else if isLocal && i < total - 30 {
                let nameLen = Int(bytes[i+26]) | (Int(bytes[i+27]) << 8)
                let extraLen = Int(bytes[i+28]) | (Int(bytes[i+29]) << 8)
                let nameStart = i + 30
                if nameStart + nameLen <= total {
                    if let filename = String(bytes: bytes[nameStart..<nameStart+nameLen], encoding: .utf8) ?? String(bytes: bytes[nameStart..<nameStart+nameLen], encoding: .ascii) {
                        let base = (filename as NSString).lastPathComponent
                        let ext = (base as NSString).pathExtension.lowercased()
                        if !base.hasPrefix(".") && !base.hasPrefix("__MACOSX") && audioExts.contains(ext) && !names.contains(base) {
                            names.append(base)
                        }
                    }
                }
                i += 30 + nameLen + extraLen
            } else {
                i += 1
            }
        }
        return names
    }

    static func autoClassify(filename: String) -> (category: String, label: String, bus: Int) {
        let nameLower = filename.lowercased()
        let cleanBase = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if nameLower.contains("click") || nameLower.contains("metronome") {
            return ("click", "CLICK", 1)
        } else if nameLower.contains("guide") || nameLower.contains("guia") || nameLower.contains("cue") {
            return ("guide", "GUÍA", 1)
        } else if nameLower.contains("drum") || nameLower.contains("bateria") || nameLower.contains("perc") || nameLower.contains("kick") || nameLower.contains("snare") {
            return ("drums", "DRUMS", 0)
        } else if nameLower.contains("bass") || nameLower.contains("bajo") {
            return ("bass", "BASS", 0)
        } else if nameLower.contains("piano") || nameLower.contains("key") || nameLower.contains("organ") || nameLower.contains("synth") {
            return ("keys", "KEYS", 0)
        } else if nameLower.contains("pad") || nameLower.contains("atmos") || nameLower.contains("string") {
            return ("pad", "PAD", 0)
        } else if nameLower.contains("guitar") || nameLower.contains("gtr") || nameLower.contains("ac ") || nameLower.contains("eg ") {
            return ("guitars", "GUITARS", 0)
        } else if nameLower.contains("vocal") || nameLower.contains("vox") || nameLower.contains("choir") || nameLower.contains("coro") {
            return ("vocals", "VOCALS", 0)
        } else {
            let label = String(cleanBase.prefix(10)).uppercased()
            return ("other", label.isEmpty ? "TRACK" : label, 0)
        }
    }
}

/// Modal con asistente de 3 pasos para subir canciones al servidor
struct UploadSongModalView: View {
    @ObservedObject var vm: ShowViewModel

    @State private var currentStep: Int = 1

    // Paso 1: Metadatos
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var bpm: Double = 120.0
    @State private var key: String = "C"
    @State private var selectedCoverData: Data? = nil
    @State private var coverFileName: String? = nil

    // Paso 2: Archivo ZIP
    @State private var zipFileURL: URL? = nil
    @State private var zipFileName: String = ""
    @State private var zipFileSizeMB: Double = 0.0
    @State private var zipData: Data? = nil
    @State private var isSelectingZip: Bool = false
    @State private var isProcessingZip: Bool = false

    // Paso 3: Mapeo de Stems
    @State private var stemsMapping: [StemMappingEntry] = []

    // Estado de Subida
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var errorMessage: String? = nil
    @State private var uploadSuccessful: Bool = false

    let availableKeys = ["C", "C#", "Db", "D", "Eb", "E", "F", "F#", "Gb", "G", "Ab", "A", "Bb", "B",
                         "Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "Abm", "Am", "Bbm", "Bm"]

    let availableCategories = [
        ("click", "Click (Gris)", Color(hexString: "#9297A0")),
        ("guide", "Guía (Naranja)", Color(hexString: "#F0A028")),
        ("drums", "Batería (Rojo)", Color(hexString: "#FF4B33")),
        ("bass", "Bajo (Verde)", Color(hexString: "#3DDC84")),
        ("keys", "Teclados (Azul)", Color(hexString: "#4DA6FF")),
        ("pad", "Pads (Morado)", Color(hexString: "#B388FF")),
        ("guitars", "Guitarras (Amarillo)", Color(hexString: "#FFBE55")),
        ("vocals", "Voces (Rosa)", Color(hexString: "#EC4899")),
        ("other", "Otro (Gris Claro)", Color(hexString: "#C3C7CC"))
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isUploading {
                        vm.showingUploadSongWizard = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 18))
                        .foregroundColor(PulsoTheme.amber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SUBIR NUEVA CANCIÓN AL SERVIDOR")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)
                        Text("Servidor: stems.tld-list.lat • Proceso idéntico a versión Web")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                    }

                    Spacer()

                    if !isUploading {
                        Button(action: { vm.showingUploadSongWizard = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(PulsoTheme.mut)
                                .frame(width: 32, height: 32)
                                .background(PulsoTheme.raise)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(16)
                .background(PulsoTheme.panel2)

                // Stepper Visual
                HStack(spacing: 0) {
                    stepIndicator(number: 1, title: "1. DETALLES", active: currentStep == 1, done: currentStep > 1)
                    Rectangle().fill(currentStep > 1 ? PulsoTheme.amber : PulsoTheme.border).frame(height: 2)
                    stepIndicator(number: 2, title: "2. ARCHIVO ZIP", active: currentStep == 2, done: currentStep > 2)
                    Rectangle().fill(currentStep > 2 ? PulsoTheme.amber : PulsoTheme.border).frame(height: 2)
                    stepIndicator(number: 3, title: "3. MAPEO STEMS", active: currentStep == 3, done: uploadSuccessful)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(PulsoTheme.panel)

                Divider().background(PulsoTheme.border)

                // Contenido dinámico según el paso
                ScrollView {
                    VStack(spacing: 20) {
                        if let error = errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(PulsoTheme.red)
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(PulsoTheme.red)
                                Spacer()
                            }
                            .padding(12)
                            .background(PulsoTheme.red.opacity(0.12))
                            .cornerRadius(8)
                        }

                        if uploadSuccessful {
                            uploadSuccessView
                        } else if isUploading {
                            uploadingProgressView
                        } else {
                            switch currentStep {
                            case 1:
                                step1DetailsView
                            case 2:
                                step2ZipFileView
                            case 3:
                                step3MappingView
                            default:
                                EmptyView()
                            }
                        }
                    }
                    .padding(20)
                }

                Divider().background(PulsoTheme.border)

                // Footer con botones de navegación
                if !isUploading && !uploadSuccessful {
                    footerButtonsView
                }
            }
            .frame(maxWidth: 680, maxHeight: 600)
            .background(PulsoTheme.bg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .padding(20)
        }
        .fileImporter(
            isPresented: $isSelectingZip,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            handleZipSelection(result)
        }
    }

    // MARK: - Subviews: Stepper

    private func stepIndicator(number: Int, title: String, active: Bool, done: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? PulsoTheme.amber : (active ? PulsoTheme.amber : PulsoTheme.raise))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(active ? .black : PulsoTheme.ink2)
                }
            }
            Text(title)
                .font(.system(size: 11, weight: active ? .bold : .medium, design: .monospaced))
                .foregroundColor(active ? PulsoTheme.amber : (done ? PulsoTheme.ink : PulsoTheme.dim))
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Step 1: Detalles

    private var step1DetailsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TÍTULO DE LA CANCIÓN *")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.mut)

                TextField("Ej: Danzare / Cuerdas de Amor", text: $title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(PulsoTheme.panel2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ARTISTA / INTÉRPRETE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.mut)

                TextField("Ej: Gateway Worship / Marcos Witt", text: $artist)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(PulsoTheme.panel2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BPM (TEMPO)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    HStack {
                        Button(action: { if bpm > 40 { bpm -= 1 } }) {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(PulsoTheme.ink)
                                .frame(width: 32, height: 36)
                                .background(PulsoTheme.raise)
                                .cornerRadius(4)
                        }

                        Text("\(Int(bpm))")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.amber)
                            .frame(maxWidth: .infinity)

                        Button(action: { if bpm < 260 { bpm += 1 } }) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(PulsoTheme.ink)
                                .frame(width: 32, height: 36)
                                .background(PulsoTheme.raise)
                                .cornerRadius(4)
                        }
                    }
                    .padding(4)
                    .background(PulsoTheme.panel2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TONALIDAD (KEY)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    Picker("Key", selection: $key) {
                        ForEach(availableKeys, id: \.self) { k in
                            Text(k).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, maxHeight: 44)
                    .background(PulsoTheme.panel2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Step 2: Archivo ZIP

    private var step2ZipFileView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: zipData != nil ? "doc.zipper.fill" : "arrow.up.doc.fill")
                    .font(.system(size: 40))
                    .foregroundColor(zipData != nil ? PulsoTheme.green : PulsoTheme.amber)

                if let data = zipData {
                    VStack(spacing: 4) {
                        Text(zipFileName)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)
                        Text(String(format: "%.1f MB • Archivo ZIP preparado", zipFileSizeMB))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                    }

                    Button(action: { isSelectingZip = true }) {
                        Text("Cambiar archivo .ZIP")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.amber)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("Selecciona el archivo .ZIP con los stems")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(PulsoTheme.ink)
                        Text("Formatos admitidos en el ZIP: .wav, .mp3, .flac, .m4a")
                            .font(.system(size: 11))
                            .foregroundColor(PulsoTheme.dim)
                    }

                    Button(action: { isSelectingZip = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                            Text("EXPLORAR ARCHIVOS EN IPAD...")
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(PulsoTheme.amber)
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(PulsoTheme.panel2)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(zipData != nil ? PulsoTheme.green.opacity(0.6) : PulsoTheme.border)
            )

            if isProcessingZip {
                HStack(spacing: 8) {
                    ProgressView().tint(PulsoTheme.amber)
                    Text("Inspeccionando pistas dentro del archivo ZIP...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)
                }
            }
        }
    }

    // MARK: - Step 3: Mapeo de Stems

    private var step3MappingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAPEO DE PISTAS (MEZCLADOR)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.ink)
                    Text("Asigna etiquetas, colores de fader y buses de salida.")
                        .font(.system(size: 10))
                        .foregroundColor(PulsoTheme.mut)
                }

                Spacer()

                Text("\(stemsMapping.count) STEMS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PulsoTheme.amber.opacity(0.15))
                    .cornerRadius(4)

                Button(action: addNewManualStem) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("PISTA")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PulsoTheme.raise)
                    .cornerRadius(4)
                }
            }

            VStack(spacing: 8) {
                ForEach(stemsMapping.indices, id: \.self) { idx in
                    stemMappingRow(idx: idx)
                }
            }
        }
    }

    private func stemMappingRow(idx: Int) -> some View {
        let stem = stemsMapping[idx]

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(stem.categoryColor).frame(width: 8, height: 8)
                Text("ARCHIVO: \(stem.originalFilename)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink2)
                    .lineLimit(1)
                Spacer()
                Button(action: { stemsMapping.remove(at: idx) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(PulsoTheme.dim)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETIQUETA (FADER)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    TextField("LABEL", text: $stemsMapping[idx].label)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(PulsoTheme.blackBox)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PulsoTheme.border, lineWidth: 1))
                }
                .frame(width: 140)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CATEGORÍA")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    Picker("Categoría", selection: $stemsMapping[idx].category) {
                        ForEach(availableCategories, id: \.0) { cat in
                            Text(cat.1).tag(cat.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, maxHeight: 32)
                    .background(PulsoTheme.blackBox)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(PulsoTheme.border, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BUS")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    Button(action: {
                        stemsMapping[idx].bus = stemsMapping[idx].bus == 0 ? 1 : 0
                    }) {
                        Text(stemsMapping[idx].bus == 0 ? "MASTER" : "CLICK/AURIC.")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(stemsMapping[idx].bus == 0 ? PulsoTheme.ink : PulsoTheme.amber)
                            .frame(width: 100, height: 32)
                            .background(stemsMapping[idx].bus == 0 ? PulsoTheme.raise : PulsoTheme.amber.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(10)
        .background(PulsoTheme.panel2)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.line, lineWidth: 1))
    }

    // MARK: - Footer Buttons

    private var footerButtonsView: some View {
        HStack {
            if currentStep > 1 {
                Button(action: { currentStep -= 1 }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("VOLVER")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.raise)
                    .cornerRadius(6)
                }
            }

            Spacer()

            if currentStep == 1 {
                Button(action: {
                    if title.trimmingCharacters(in: .whitespaces).isEmpty {
                        errorMessage = "Ingresa un título para la canción."
                    } else {
                        errorMessage = nil
                        currentStep = 2
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("SIGUIENTE: ARCHIVO ZIP")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.amber)
                    .cornerRadius(6)
                }
            } else if currentStep == 2 {
                Button(action: {
                    if zipData == nil {
                        errorMessage = "Debes seleccionar un archivo .ZIP de stems."
                    } else {
                        errorMessage = nil
                        inspectZipAndGoToStep3()
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("CONTINUAR AL MAPEO")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(zipData != nil ? PulsoTheme.amber : PulsoTheme.border)
                    .cornerRadius(6)
                }
                .disabled(zipData == nil)
            } else if currentStep == 3 {
                Button(action: startUploadToServer) {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.fill")
                        Text("SUBIR AL SERVIDOR")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.amber)
                    .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .background(PulsoTheme.panel2)
    }

    // MARK: - Views: Progreso y Éxito

    private var uploadingProgressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: uploadProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: PulsoTheme.amber))
                .scaleEffect(x: 1, y: 3, anchor: .center)
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                Text(statusMessage)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                Text(String(format: "Progreso: %.0f%% • Subiendo stems a stems.tld-list.lat", uploadProgress * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PulsoTheme.mut)
            }
        }
        .padding(30)
    }

    private var uploadSuccessView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(PulsoTheme.green)

            Text("¡CANCIÓN SUBIDA AL SERVIDOR!")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(PulsoTheme.ink)

            Text("La canción '\(title)' fue procesada y añadida al catálogo del servidor.")
                .font(.system(size: 12))
                .foregroundColor(PulsoTheme.ink2)
                .multilineTextAlignment(.center)

            Button(action: {
                vm.showingUploadSongWizard = false
                Task { await vm.loadCloudCatalog() }
            }) {
                Text("CERRAR Y VER CATÁLOGO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.green)
                    .cornerRadius(6)
            }
        }
        .padding(20)
    }

    // MARK: - Logica de Selección e Inspección

    private func handleZipSelection(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else { return }
            guard selectedURL.startAccessingSecurityScopedResource() else {
                errorMessage = "No se pudo acceder al archivo seleccionado."
                return
            }
            defer { selectedURL.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: selectedURL)
            self.zipData = data
            self.zipFileURL = selectedURL
            self.zipFileName = selectedURL.lastPathComponent
            self.zipFileSizeMB = Double(data.count) / (1024.0 * 1024.0)

            if title.isEmpty {
                title = selectedURL.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }
        } catch {
            errorMessage = "Error leyendo archivo ZIP: \(error.localizedDescription)"
        }
    }

    private func inspectZipAndGoToStep3() {
        guard let data = zipData else { return }
        isProcessingZip = true

        DispatchQueue.global(qos: .userInitiated).async {
            let audioFiles = NativeZipInspector.extractAudioFilenames(from: data)
            DispatchQueue.main.async {
                self.isProcessingZip = false
                if !audioFiles.isEmpty {
                    self.stemsMapping = audioFiles.enumerated().map { (idx, fname) in
                        let classification = NativeZipInspector.autoClassify(filename: fname)
                        return StemMappingEntry(
                            id: "stem_\(idx)",
                            originalFilename: fname,
                            label: classification.label,
                            category: classification.category,
                            bus: classification.bus
                        )
                    }
                } else {
                    // Fallback con stems comunes si el ZIP tiene nombres crípticos
                    self.stemsMapping = [
                        StemMappingEntry(id: "click", originalFilename: "click.wav", label: "CLICK", category: "click", bus: 1),
                        StemMappingEntry(id: "guide", originalFilename: "guide.wav", label: "GUÍA", category: "guide", bus: 1),
                        StemMappingEntry(id: "drums", originalFilename: "drums.wav", label: "DRUMS", category: "drums", bus: 0),
                        StemMappingEntry(id: "bass", originalFilename: "bass.wav", label: "BASS", category: "bass", bus: 0),
                        StemMappingEntry(id: "keys", originalFilename: "keys.wav", label: "KEYS", category: "keys", bus: 0)
                    ]
                }
                self.currentStep = 3
            }
        }
    }

    private func addNewManualStem() {
        let count = stemsMapping.count + 1
        stemsMapping.append(StemMappingEntry(
            id: "stem_\(count)",
            originalFilename: "pista_\(count).wav",
            label: "PISTA \(count)",
            category: "other",
            bus: 0
        ))
    }

    private func startUploadToServer() {
        guard let zData = zipData else { return }
        isUploading = true
        uploadProgress = 0.1
        statusMessage = "Conectando con el servidor..."
        errorMessage = nil

        Task {
            do {
                // Serializar mapeo a JSON
                let mappingDicts: [[String: Any]] = stemsMapping.map { stem in
                    return [
                        "id": stem.label.lowercased().replacingOccurrences(of: " ", with: "_"),
                        "original": stem.originalFilename,
                        "label": stem.label,
                        "category": stem.category,
                        "bus": stem.bus
                    ]
                }
                var mappingJsonString: String? = nil
                if let jsonData = try? JSONSerialization.data(withJSONObject: mappingDicts),
                   let str = String(data: jsonData, encoding: .utf8) {
                    mappingJsonString = str
                }

                uploadProgress = 0.4
                statusMessage = "Enviando archivo .ZIP (\(String(format: "%.1f", zipFileSizeMB)) MB)..."

                _ = try await BackendAPIService.shared.uploadSong(
                    title: title,
                    artist: artist.isEmpty ? "Desconocido" : artist,
                    bpm: bpm,
                    key: key,
                    zipData: zData,
                    zipFilename: zipFileName.isEmpty ? "multitrack.zip" : zipFileName,
                    coverData: selectedCoverData,
                    stemsMappingJson: mappingJsonString
                )

                uploadProgress = 1.0
                statusMessage = "¡Procesamiento completado en el servidor!"
                uploadSuccessful = true
                isUploading = false
            } catch {
                isUploading = false
                errorMessage = "Fallo en la subida: \(error.localizedDescription)"
            }
        }
    }
}
