import Foundation
#if os(Windows)
import WinSDK
#endif

enum CLIHelpLanguage: String, CaseIterable {
    case en, zhCN = "zh-CN", zhTW = "zh-TW", ja, ko, es, fr, de, ptBR = "pt-BR", ru, ar, hi

    static func matching(_ identifier: String) -> Self? {
        let tag = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "_", with: "-")
            .split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        let parts = tag.split(separator: "@").first?.split(separator: "-").map(String.init) ?? []
        guard let first = parts.first else { return nil }
        if first == "c" || first == "posix" { return .en }
        if first == "zh" {
            if parts.contains("hant") { return .zhTW }
            if parts.contains("hans") { return .zhCN }
            return parts.contains(where: ["tw", "hk", "mo"].contains) ? .zhTW : .zhCN
        }
        if first == "pt" { return .ptBR }
        return Self(rawValue: first)
    }

    static func system(environment: [String: String] = ProcessInfo.processInfo.environment,
                       preferredLanguages: [String] = platformLanguages) -> Self {
        for key in ["LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG"] {
            if let value = environment[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.split(separator: ":").compactMap { matching(String($0)) }.first ?? .en
            }
        }
        return preferredLanguages.compactMap(matching).first ?? .en
    }

    static var platformLanguages: [String] {
        #if os(Windows)
        var count: ULONG = 0
        var length: ULONG = 0
        if GetUserPreferredUILanguages(ULONG(MUI_LANGUAGE_NAME), &count, nil, &length), length > 1 {
            var buffer = [WCHAR](repeating: 0, count: Int(length))
            if GetUserPreferredUILanguages(ULONG(MUI_LANGUAGE_NAME), &count, &buffer, &length) {
                return String(decoding: buffer, as: UTF16.self).split(separator: "\0").map(String.init)
            }
        }
        #endif
        return Locale.preferredLanguages
    }
}

enum CLIHelp {
    static let syntax = [
        "--fit PATH", "--timeline-project PATH", "--output PATH",
        "--video PATH", "--export-mode M", "--width PX", "--height PX", "--fps N",
        "--fit-start SEC", "--sync-video SEC", "--sync-fit SEC", "--offset SEC",
        "--activity-offset-ms MS", "--fit-clock-offset-ms MS", "--bitrate KBPS", "--bitrate-bps BPS",
        "--codec NAME", "--distance-unit U", "--time-zone ZONE", "--activity-trim-start SEC",
        "--activity-trim-end SEC", "--layout-preset P", "--skip-fit-crc", "--inspect", "--force",
        "--language CODE", "-h, --help"
    ]

    static func text(_ language: CLIHelpLanguage) -> String {
        let lines = language.helpLines
        precondition(lines.count == syntax.count + 3)
        var output = [lines[0] + ":",
                      "  overlay --fit activity.fit|activity.gpx --output overlay.mov",
                      "  overlay --timeline-project project.dlsproj --output output.mov",
                      "", lines[1] + ":"]
        for index in syntax.indices {
            if index == 3 { output += ["", lines[2] + ":"] }
            output += ["  " + syntax[index], "      " + lines[index + 3]]
        }
        output += ["", "  --language: " + CLIHelpLanguage.allCases.map(\.rawValue).joined(separator: ", ")]
        return output.joined(separator: "\n")
    }

    static func write(_ text: String) -> Bool {
        #if os(Windows)
        let handle = GetStdHandle(STD_OUTPUT_HANDLE)
        var mode: DWORD = 0
        if GetConsoleMode(handle, &mode) {
            // Console code pages cannot represent all twelve languages; redirects stay UTF-8.
            let units = Array((text + "\n").replacingOccurrences(of: "\n", with: "\r\n").utf16)
            return units.withUnsafeBufferPointer { buffer in
                var offset = 0
                while offset < buffer.count {
                    var written: DWORD = 0
                    guard WriteConsoleW(handle, buffer.baseAddress! + offset,
                                        DWORD(min(4096, buffer.count - offset)), &written, nil),
                          written > 0 else { return false }
                    offset += Int(written)
                }
                return true
            }
        }
        #endif
        do {
            try FileHandle.standardOutput.write(contentsOf: Data((text + "\n").utf8))
            return true
        } catch { return false }
    }
}

extension CLIHelpLanguage {
    var helpLines: [String] {
        let text: String
        switch self {
        case .en:
            text = """
            Usage
            Required inputs
            Options
            Standard FIT/GPX activity file. Use either --fit or --timeline-project.
            DataLayer Studio .dlsproj project file.
            Output movie. Individual project clips use name_01.mov, name_02.mov, etc.
            Optional source video. Without video, video mode uses a black canvas.
            overlay: transparent Alpha (default for single-source input); video: opaque composite. Projects inherit saved mode, codec, bitrate, trims and scope; explicit options override saved values.
            Output width: even integer 2...16384. Default: source width, or 1920 without video.
            Output height: even integer 2...16384. Default: source height, or 1080 without video.
            Frame rate, at least 1. Default: source frame rate, or 30 without video.
            Activity elapsed seconds at video time 0; use when video starts mid-activity.
            Video seconds at a sync point. Requires --sync-fit.
            Activity elapsed seconds at the same sync point. Requires --sync-video.
            Legacy offset: video starts SEC seconds before FIT; negative starts mid-activity.
            Shift Activity Time and all samples by -999...999 ms. Positive selects later data.
            Shift only the displayed FIT clock/date by -999...999 ms. Positive displays a later time.
            Average HEVC bitrate in kbps; default 12000. Legacy values above 1000000 are read as bps.
            Legacy explicit bitrate in bps.
            overlay: hevc-alpha (Apple only, default), prores-4444. video: hevc (default), h264.
            Distance labels: km (default) or m.
            Clock/date zone: activity (default), system, or IANA name such as Asia/Shanghai. activity falls back to system; projects keep their saved choice unless overridden.
            Rebase overlay data from this original activity elapsed time in seconds.
            Stop overlay data at this original activity elapsed time in seconds.
            Layout preset name/ID or .dlspreset file. Not used with --timeline-project.
            Skip FIT CRC validation; ignored for GPX.
            Print video/activity metadata without rendering.
            Replace existing output. Input files are never overwritten.
            Help language; default follows system/terminal locale, with English fallback. Example: --language zh-CN --help.
            Show this help. -h and --help are equivalent.
            """
        case .zhCN:
            text = """
            用法
            必需输入
            选项
            标准 FIT/GPX 活动文件。--fit 与 --timeline-project 二选一。
            DataLayer Studio 的 .dlsproj 工程文件。
            输出视频。逐片段导出时使用 name_01.mov、name_02.mov 等名称。
            可选的源视频。不提供视频时，video 模式使用黑色画布。
            overlay：透明 Alpha 浮层（单素材默认）；video：不透明合成。工程沿用已保存的模式、编码、码率、裁切与范围；显式参数覆盖对应设置。
            输出宽度：2...16384 范围内的偶数。默认使用源视频宽度，无视频时为 1920。
            输出高度：2...16384 范围内的偶数。默认使用源视频高度，无视频时为 1080。
            帧率，至少为 1。默认使用源视频帧率，无视频时为 30。
            视频第 0 秒对应的活动已用秒数，用于从活动中途开始录制的视频。
            同步点的视频秒数。须同时提供 --sync-fit。
            同一同步点的活动已用秒数。须同时提供 --sync-video。
            旧版偏移：视频比 FIT 提前 SEC 秒开始；负值表示从活动中途开始。
            将活动时间及所有数据样本偏移 -999...999 毫秒。正值选取更晚的数据。
            仅将显示的 FIT 时钟和日期偏移 -999...999 毫秒。正值显示更晚的时间。
            HEVC 平均码率，单位 kbps，默认 12000。大于 1000000 的旧值按 bps 解释。
            旧版显式码率，单位 bps。
            overlay：hevc-alpha（仅 Apple，默认）、prores-4444。video：hevc（默认）、h264。
            距离标签：km（默认）或 m。
            时钟和日期时区：activity（默认）、system 或 Asia/Shanghai 等 IANA 名称。activity 无可用时区时使用系统时区；工程保留已存设置，除非显式覆盖。
            从原活动的此已用秒数开始重新计时浮层数据。
            在原活动的此已用秒数停止浮层数据。
            布局模板名称、ID 或 .dlspreset 文件。不可与 --timeline-project 合用。
            跳过 FIT CRC 校验；GPX 忽略此选项。
            仅输出视频和活动元数据，不渲染。
            替换已有输出文件。绝不覆盖输入文件。
            帮助语言；默认跟随系统或终端语言，无法匹配时使用英文。例：--language zh-CN --help。
            显示此帮助。-h 与 --help 等效。
            """
        case .zhTW:
            text = """
            用法
            必要輸入
            選項
            標準 FIT/GPX 活動檔案。--fit 與 --timeline-project 擇一。
            DataLayer Studio 的 .dlsproj 專案檔案。
            輸出影片。逐片段匯出時使用 name_01.mov、name_02.mov 等名稱。
            選用的來源影片。未提供影片時，video 模式使用黑色畫布。
            overlay：透明 Alpha 浮層（單一素材預設）；video：不透明合成。專案沿用已儲存的模式、編碼、位元率、裁切與範圍；明確參數覆寫對應設定。
            輸出寬度：2...16384 範圍內的偶數。預設使用來源影片寬度，無影片時為 1920。
            輸出高度：2...16384 範圍內的偶數。預設使用來源影片高度，無影片時為 1080。
            影格率，至少為 1。預設使用來源影片影格率，無影片時為 30。
            影片第 0 秒對應的活動經過秒數，適用於從活動中途開始錄製的影片。
            同步點的影片秒數。須同時提供 --sync-fit。
            同一同步點的活動經過秒數。須同時提供 --sync-video。
            舊版偏移：影片比 FIT 提前 SEC 秒開始；負值表示從活動中途開始。
            將活動時間及所有資料樣本偏移 -999...999 毫秒。正值選取較晚的資料。
            僅將顯示的 FIT 時鐘和日期偏移 -999...999 毫秒。正值顯示較晚的時間。
            HEVC 平均位元率，單位 kbps，預設 12000。大於 1000000 的舊值按 bps 解讀。
            舊版明確位元率，單位 bps。
            overlay：hevc-alpha（僅 Apple，預設）、prores-4444。video：hevc（預設）、h264。
            距離標籤：km（預設）或 m。
            時鐘和日期時區：activity（預設）、system 或 Asia/Shanghai 等 IANA 名稱。activity 無可用時區時使用系統時區；專案保留已存設定，除非明確覆寫。
            從原活動的此經過秒數開始重新計時浮層資料。
            在原活動的此經過秒數停止浮層資料。
            版面配置範本名稱、ID 或 .dlspreset 檔案。不可與 --timeline-project 合用。
            跳過 FIT CRC 驗證；GPX 忽略此選項。
            僅輸出影片和活動中繼資料，不繪製。
            取代現有輸出檔案。絕不覆寫輸入檔案。
            說明語言；預設跟隨系統或終端機語言，無法匹配時使用英文。例：--language zh-TW --help。
            顯示此說明。-h 與 --help 等效。
            """
        case .ja:
            text = """
            使い方
            必須の入力
            オプション
            標準の FIT/GPX アクティビティファイル。--fit または --timeline-project の一方を指定します。
            DataLayer Studio の .dlsproj プロジェクトファイル。
            出力動画。クリップ別の書き出しでは name_01.mov、name_02.mov などを使用します。
            任意の元動画。動画なしの場合、video モードは黒いキャンバスを使用します。
            overlay：透過 Alpha（単一素材の既定値）、video：不透明な合成。プロジェクトの保存済みモード、コーデック、ビットレート、トリミング、範囲を継承し、明示した引数で上書きします。
            出力幅：2...16384 の偶数。既定値は元動画の幅、動画なしでは 1920。
            出力高さ：2...16384 の偶数。既定値は元動画の高さ、動画なしでは 1080。
            フレームレート。最小 1。既定値は元動画の値、動画なしでは 30。
            動画の 0 秒に対応するアクティビティ経過秒数。途中から撮影した動画に使用します。
            同期点の動画秒数。--sync-fit も必要です。
            同じ同期点のアクティビティ経過秒数。--sync-video も必要です。
            旧形式のオフセット：動画が FIT より SEC 秒早く開始。負の値はアクティビティの途中から開始します。
            アクティビティ時間と全サンプルを -999...999 ミリ秒ずらします。正の値は後のデータを選択します。
            表示する FIT の時刻と日付のみを -999...999 ミリ秒ずらします。正の値は後の時刻を表示します。
            HEVC の平均ビットレート（kbps）。既定値 12000。1000000 を超える旧形式の値は bps として扱います。
            旧形式の明示的なビットレート（bps）。
            overlay：hevc-alpha（Apple のみ、既定値）、prores-4444。video：hevc（既定値）、h264。
            距離の単位：km（既定値）または m。
            時刻と日付のタイムゾーン：activity（既定値）、system、または Asia/Shanghai などの IANA 名。activity が取得できない場合はシステム設定を使用。プロジェクトでは明示的に上書きしない限り保存値を維持します。
            元のアクティビティの指定経過秒数からオーバーレイデータを開始し、時間をリセットします。
            元のアクティビティの指定経過秒数でオーバーレイデータを停止します。
            レイアウトの名前、ID、または .dlspreset ファイル。--timeline-project とは併用できません。
            FIT の CRC 検証を省略。GPX では無視します。
            動画とアクティビティのメタデータのみ表示し、描画しません。
            既存の出力を置換します。入力ファイルは上書きしません。
            ヘルプ言語。既定ではシステムまたは端末の言語に従い、未対応の場合は英語。例：--language ja --help。
            このヘルプを表示。-h と --help は同じです。
            """
        case .ko:
            text = """
            사용법
            필수 입력
            옵션
            표준 FIT/GPX 활동 파일. --fit 또는 --timeline-project 중 하나를 사용합니다.
            DataLayer Studio .dlsproj 프로젝트 파일.
            출력 동영상. 클립별 내보내기에는 name_01.mov, name_02.mov 등의 이름을 사용합니다.
            선택적 원본 동영상. 동영상이 없으면 video 모드는 검은 캔버스를 사용합니다.
            overlay: 투명 Alpha(단일 소스 기본값), video: 불투명 합성. 프로젝트에 저장된 모드, 코덱, 비트레이트, 자르기 및 범위를 유지하며 명시한 옵션으로 덮어씁니다.
            출력 너비: 2...16384 범위의 짝수. 기본값은 원본 너비이며 동영상이 없으면 1920입니다.
            출력 높이: 2...16384 범위의 짝수. 기본값은 원본 높이이며 동영상이 없으면 1080입니다.
            프레임 속도, 최솟값 1. 기본값은 원본 값이며 동영상이 없으면 30입니다.
            동영상 0초에 해당하는 활동 경과 시간(초). 활동 도중 촬영을 시작한 경우 사용합니다.
            동기화 지점의 동영상 시간(초). --sync-fit이 필요합니다.
            동일한 동기화 지점의 활동 경과 시간(초). --sync-video가 필요합니다.
            기존 오프셋: 동영상이 FIT보다 SEC초 먼저 시작합니다. 음수는 활동 중간부터 시작합니다.
            활동 시간과 모든 샘플을 -999...999밀리초 이동합니다. 양수는 더 늦은 데이터를 선택합니다.
            표시되는 FIT 시계와 날짜만 -999...999밀리초 이동합니다. 양수는 더 늦은 시각을 표시합니다.
            HEVC 평균 비트레이트(kbps), 기본값 12000. 1000000을 초과하는 기존 값은 bps로 해석합니다.
            bps 단위의 기존 명시적 비트레이트.
            overlay: hevc-alpha(Apple 전용, 기본값), prores-4444. video: hevc(기본값), h264.
            거리 표시 단위: km(기본값) 또는 m.
            시계와 날짜의 시간대: activity(기본값), system 또는 Asia/Shanghai 같은 IANA 이름. activity가 없으면 시스템 시간대를 사용하며, 프로젝트는 명시적으로 변경하지 않으면 저장된 값을 유지합니다.
            원래 활동의 지정된 경과 시간(초)부터 오버레이 데이터를 시작하고 시간을 재설정합니다.
            원래 활동의 지정된 경과 시간(초)에서 오버레이 데이터를 멈춥니다.
            레이아웃 이름, ID 또는 .dlspreset 파일. --timeline-project와 함께 사용할 수 없습니다.
            FIT CRC 검증을 건너뜁니다. GPX에서는 무시됩니다.
            동영상 및 활동 메타데이터만 출력하고 렌더링하지 않습니다.
            기존 출력을 교체합니다. 입력 파일은 덮어쓰지 않습니다.
            도움말 언어. 기본값은 시스템 또는 터미널 언어를 따르며 미지원 시 영어를 사용합니다. 예: --language ko --help.
            이 도움말을 표시합니다. -h와 --help는 같습니다.
            """
        case .es:
            text = """
            Uso
            Entradas obligatorias
            Opciones
            Archivo de actividad FIT/GPX estándar. Use --fit o --timeline-project, no ambos.
            Archivo de proyecto .dlsproj de DataLayer Studio.
            Vídeo de salida. Los clips individuales usan name_01.mov, name_02.mov, etc.
            Vídeo de origen opcional. Sin vídeo, el modo video usa un lienzo negro.
            overlay: Alpha transparente (predeterminado con una sola fuente); video: composición opaca. Los proyectos conservan modo, códec, tasa, recortes y alcance guardados; las opciones explícitas sustituyen esos valores.
            Anchura de salida: entero par de 2...16384. Por defecto, la del origen o 1920 sin vídeo.
            Altura de salida: entero par de 2...16384. Por defecto, la del origen o 1080 sin vídeo.
            Fotogramas por segundo, mínimo 1. Por defecto, los del origen o 30 sin vídeo.
            Segundos transcurridos de actividad en el instante 0 del vídeo; para grabaciones iniciadas a mitad de la actividad.
            Segundo del vídeo en un punto de sincronización. Requiere --sync-fit.
            Segundos de actividad en el mismo punto de sincronización. Requiere --sync-video.
            Desfase antiguo: el vídeo empieza SEC segundos antes del FIT; un valor negativo empieza durante la actividad.
            Desplaza el tiempo de actividad y todas las muestras entre -999...999 ms. Un valor positivo elige datos posteriores.
            Desplaza solo el reloj y la fecha FIT mostrados entre -999...999 ms. Un valor positivo muestra una hora posterior.
            Tasa media HEVC en kbps; predeterminada 12000. Los valores antiguos superiores a 1000000 se interpretan como bps.
            Tasa explícita antigua en bps.
            overlay: hevc-alpha (solo Apple, predeterminado), prores-4444. video: hevc (predeterminado), h264.
            Unidad de distancia: km (predeterminada) o m.
            Zona del reloj/fecha: activity (predeterminada), system o nombre IANA como Asia/Shanghai. activity usa la del sistema si no está disponible; los proyectos conservan su valor salvo que se indique otro.
            Inicia y reinicia los datos de la capa en estos segundos transcurridos de la actividad original.
            Detiene los datos de la capa en estos segundos transcurridos de la actividad original.
            Nombre/ID de diseño o archivo .dlspreset. No se combina con --timeline-project.
            Omite la validación CRC de FIT; se ignora para GPX.
            Imprime metadatos de vídeo/actividad sin renderizar.
            Sustituye la salida existente. Nunca sobrescribe archivos de entrada.
            Idioma de ayuda; sigue el sistema o terminal por defecto y usa inglés si no hay coincidencia. Ejemplo: --language es --help.
            Muestra esta ayuda. -h y --help son equivalentes.
            """
        case .fr:
            text = """
            Utilisation
            Entrées requises
            Options
            Fichier d’activité FIT/GPX standard. Utilisez soit --fit, soit --timeline-project.
            Fichier de projet .dlsproj de DataLayer Studio.
            Vidéo de sortie. Les clips individuels utilisent name_01.mov, name_02.mov, etc.
            Vidéo source facultative. Sans vidéo, le mode video utilise un fond noir.
            overlay : Alpha transparent (par défaut avec une seule source) ; video : composition opaque. Les projets conservent mode, codec, débit, coupes et portée enregistrés ; les options explicites remplacent ces valeurs.
            Largeur de sortie : entier pair de 2...16384. Par défaut, largeur source ou 1920 sans vidéo.
            Hauteur de sortie : entier pair de 2...16384. Par défaut, hauteur source ou 1080 sans vidéo.
            Images par seconde, minimum 1. Par défaut, valeur source ou 30 sans vidéo.
            Secondes écoulées de l’activité au temps 0 de la vidéo ; pour un enregistrement commencé en cours d’activité.
            Seconde vidéo au point de synchronisation. Nécessite --sync-fit.
            Secondes d’activité au même point de synchronisation. Nécessite --sync-video.
            Ancien décalage : la vidéo commence SEC secondes avant le FIT ; une valeur négative commence en cours d’activité.
            Décale le temps d’activité et tous les échantillons de -999...999 ms. Une valeur positive sélectionne des données ultérieures.
            Décale uniquement l’horloge et la date FIT affichées de -999...999 ms. Une valeur positive affiche une heure ultérieure.
            Débit HEVC moyen en kbps ; valeur par défaut 12000. Les anciennes valeurs supérieures à 1000000 sont lues en bps.
            Ancien débit explicite en bps.
            overlay : hevc-alpha (Apple uniquement, par défaut), prores-4444. video : hevc (par défaut), h264.
            Unité de distance : km (par défaut) ou m.
            Fuseau de l’horloge/date : activity (par défaut), system ou nom IANA tel que Asia/Shanghai. activity utilise le système à défaut ; les projets conservent leur choix sauf remplacement explicite.
            Démarre et remet à zéro les données de la couche à ce temps écoulé de l’activité d’origine, en secondes.
            Arrête les données de la couche à ce temps écoulé de l’activité d’origine, en secondes.
            Nom/ID de mise en page ou fichier .dlspreset. Incompatible avec --timeline-project.
            Ignore la validation CRC FIT ; sans effet pour GPX.
            Affiche les métadonnées vidéo/activité sans rendu.
            Remplace la sortie existante. Ne remplace jamais les fichiers d’entrée.
            Langue de l’aide ; suit le système ou terminal par défaut, avec repli sur l’anglais. Exemple : --language fr --help.
            Affiche cette aide. -h et --help sont équivalents.
            """
        case .de:
            text = """
            Verwendung
            Erforderliche Eingaben
            Optionen
            Standard-FIT/GPX-Aktivitätsdatei. Entweder --fit oder --timeline-project verwenden.
            DataLayer Studio-Projektdatei im Format .dlsproj.
            Ausgabevideo. Einzelne Projektclips heißen name_01.mov, name_02.mov usw.
            Optionales Quellvideo. Ohne Video verwendet der Modus video eine schwarze Zeichenfläche.
            overlay: transparentes Alpha (Standard bei einer Quelle); video: undurchsichtige Komposition. Projekte übernehmen gespeicherten Modus, Codec, Bitrate, Zuschnitt und Bereich; explizite Optionen überschreiben diese Werte.
            Ausgabebreite: gerade Ganzzahl von 2...16384. Standard: Quellbreite oder 1920 ohne Video.
            Ausgabehöhe: gerade Ganzzahl von 2...16384. Standard: Quellhöhe oder 1080 ohne Video.
            Bildrate, mindestens 1. Standard: Quellbildrate oder 30 ohne Video.
            Verstrichene Aktivitätssekunden bei Videozeit 0; für Aufnahmen ab der Mitte einer Aktivität.
            Videosekunden am Synchronisationspunkt. Erfordert --sync-fit.
            Aktivitätssekunden am selben Synchronisationspunkt. Erfordert --sync-video.
            Alter Versatz: Das Video beginnt SEC Sekunden vor FIT; negative Werte beginnen während der Aktivität.
            Verschiebt Aktivitätszeit und alle Messwerte um -999...999 ms. Positive Werte wählen spätere Daten.
            Verschiebt nur die angezeigte FIT-Uhrzeit und das Datum um -999...999 ms. Positive Werte zeigen eine spätere Zeit.
            Mittlere HEVC-Bitrate in kbps; Standard 12000. Alte Werte über 1000000 werden als bps gelesen.
            Alte explizite Bitrate in bps.
            overlay: hevc-alpha (nur Apple, Standard), prores-4444. video: hevc (Standard), h264.
            Entfernungseinheit: km (Standard) oder m.
            Zeitzone für Uhr/Datum: activity (Standard), system oder IANA-Name wie Asia/Shanghai. activity nutzt ersatzweise das System; Projekte behalten ihren Wert ohne explizite Überschreibung.
            Startet die Einblendungsdaten bei dieser verstrichenen Sekunde der ursprünglichen Aktivität mit zurückgesetzter Zeit.
            Beendet die Einblendungsdaten bei dieser verstrichenen Sekunde der ursprünglichen Aktivität.
            Layoutname/ID oder .dlspreset-Datei. Nicht mit --timeline-project kombinierbar.
            Überspringt die FIT-CRC-Prüfung; für GPX ohne Wirkung.
            Gibt Video-/Aktivitätsmetadaten ohne Rendering aus.
            Ersetzt vorhandene Ausgaben. Eingabedateien werden niemals überschrieben.
            Hilfesprache; standardmäßig System-/Terminalsprache, sonst Englisch. Beispiel: --language de --help.
            Zeigt diese Hilfe. -h und --help sind gleichwertig.
            """
        case .ptBR:
            text = """
            Uso
            Entradas obrigatórias
            Opções
            Arquivo de atividade FIT/GPX padrão. Use --fit ou --timeline-project, não ambos.
            Arquivo de projeto .dlsproj do DataLayer Studio.
            Vídeo de saída. Clipes individuais usam name_01.mov, name_02.mov etc.
            Vídeo de origem opcional. Sem vídeo, o modo video usa uma tela preta.
            overlay: Alpha transparente (padrão com uma única fonte); video: composição opaca. Projetos mantêm modo, codec, taxa, cortes e escopo salvos; opções explícitas substituem esses valores.
            Largura de saída: inteiro par de 2...16384. Padrão: largura original ou 1920 sem vídeo.
            Altura de saída: inteiro par de 2...16384. Padrão: altura original ou 1080 sem vídeo.
            Taxa de quadros, mínimo 1. Padrão: taxa original ou 30 sem vídeo.
            Segundos decorridos da atividade no tempo 0 do vídeo; para gravações iniciadas durante a atividade.
            Segundo do vídeo no ponto de sincronização. Requer --sync-fit.
            Segundos da atividade no mesmo ponto de sincronização. Requer --sync-video.
            Deslocamento antigo: o vídeo começa SEC segundos antes do FIT; valores negativos começam durante a atividade.
            Desloca o tempo da atividade e todas as amostras em -999...999 ms. Valores positivos selecionam dados posteriores.
            Desloca apenas o relógio e a data FIT exibidos em -999...999 ms. Valores positivos mostram um horário posterior.
            Taxa média HEVC em kbps; padrão 12000. Valores antigos acima de 1000000 são lidos como bps.
            Taxa explícita antiga em bps.
            overlay: hevc-alpha (somente Apple, padrão), prores-4444. video: hevc (padrão), h264.
            Unidade de distância: km (padrão) ou m.
            Fuso do relógio/data: activity (padrão), system ou nome IANA como Asia/Shanghai. activity usa o sistema se indisponível; projetos mantêm a escolha salva, salvo substituição explícita.
            Inicia e reinicia os dados da camada nestes segundos decorridos da atividade original.
            Encerra os dados da camada nestes segundos decorridos da atividade original.
            Nome/ID do layout ou arquivo .dlspreset. Incompatível com --timeline-project.
            Ignora a validação CRC FIT; sem efeito para GPX.
            Exibe metadados de vídeo/atividade sem renderizar.
            Substitui a saída existente. Nunca sobrescreve arquivos de entrada.
            Idioma da ajuda; segue o sistema ou terminal por padrão, com inglês como alternativa. Exemplo: --language pt-BR --help.
            Exibe esta ajuda. -h e --help são equivalentes.
            """
        case .ru:
            text = """
            Использование
            Обязательные входные данные
            Параметры
            Стандартный файл активности FIT/GPX. Используйте либо --fit, либо --timeline-project.
            Файл проекта DataLayer Studio в формате .dlsproj.
            Выходное видео. Отдельные клипы проекта получают имена name_01.mov, name_02.mov и т. д.
            Необязательное исходное видео. Без него режим video использует чёрный фон.
            overlay: прозрачный Alpha (по умолчанию для одного источника); video: непрозрачная композиция. Проекты сохраняют режим, кодек, битрейт, обрезку и диапазон; явные параметры заменяют сохранённые значения.
            Ширина: чётное целое число от 2...16384. По умолчанию ширина исходника или 1920 без видео.
            Высота: чётное целое число от 2...16384. По умолчанию высота исходника или 1080 без видео.
            Частота кадров, минимум 1. По умолчанию частота исходника или 30 без видео.
            Прошедшие секунды активности в момент 0 видео; для записи, начатой во время активности.
            Секунда видео в точке синхронизации. Требуется --sync-fit.
            Секунды активности в той же точке синхронизации. Требуется --sync-video.
            Старое смещение: видео начинается на SEC секунд раньше FIT; отрицательное значение означает начало посреди активности.
            Сдвигает время активности и все отсчёты на -999...999 мс. Положительное значение выбирает более поздние данные.
            Сдвигает только отображаемые часы и дату FIT на -999...999 мс. Положительное значение показывает более позднее время.
            Средний битрейт HEVC в kbps; по умолчанию 12000. Старые значения выше 1000000 читаются как bps.
            Старый явный битрейт в bps.
            overlay: hevc-alpha (только Apple, по умолчанию), prores-4444. video: hevc (по умолчанию), h264.
            Единица расстояния: km (по умолчанию) или m.
            Часовой пояс часов/даты: activity (по умолчанию), system или имя IANA, например Asia/Shanghai. Если activity недоступен, используется системный; проекты сохраняют выбор без явного переопределения.
            Начинает данные слоя с указанной прошедшей секунды исходной активности, сбрасывая отсчёт времени.
            Останавливает данные слоя на указанной прошедшей секунде исходной активности.
            Имя/ID макета или файл .dlspreset. Несовместимо с --timeline-project.
            Пропускает проверку CRC FIT; игнорируется для GPX.
            Выводит метаданные видео/активности без рендеринга.
            Заменяет существующий результат. Входные файлы никогда не перезаписываются.
            Язык справки; по умолчанию язык системы или терминала, иначе английский. Пример: --language ru --help.
            Показывает эту справку. -h и --help равнозначны.
            """
        case .ar:
            text = """
            الاستخدام
            المدخلات المطلوبة
            الخيارات
            ملف نشاط FIT/GPX قياسي. استخدم إما --fit أو --timeline-project.
            ملف مشروع DataLayer Studio بامتداد .dlsproj.
            فيديو الإخراج. تستخدم مقاطع المشروع المنفردة الأسماء name_01.mov وname_02.mov وهكذا.
            فيديو مصدر اختياري. عند عدم وجود فيديو، يستخدم وضع video خلفية سوداء.
            overlay: طبقة Alpha شفافة (الافتراضي لمصدر واحد)؛ video: تركيب غير شفاف. تحتفظ المشاريع بالوضع والترميز ومعدل البت والقص والنطاق المحفوظة؛ وتتجاوز الخيارات الصريحة القيم المقابلة.
            عرض الإخراج: عدد زوجي بين 2...16384. الافتراضي عرض المصدر أو 1920 دون فيديو.
            ارتفاع الإخراج: عدد زوجي بين 2...16384. الافتراضي ارتفاع المصدر أو 1080 دون فيديو.
            معدل الإطارات، بحد أدنى 1. الافتراضي معدل المصدر أو 30 دون فيديو.
            ثواني النشاط المنقضية عند الثانية 0 من الفيديو؛ للتسجيل الذي يبدأ أثناء النشاط.
            ثانية الفيديو عند نقطة المزامنة. يتطلب --sync-fit.
            ثواني النشاط عند نقطة المزامنة نفسها. يتطلب --sync-video.
            الإزاحة القديمة: يبدأ الفيديو قبل FIT بمقدار SEC ثانية؛ وتعني القيمة السالبة البدء أثناء النشاط.
            يزيح وقت النشاط وكل العينات بمقدار -999...999 مللي ثانية. تختار القيمة الموجبة بيانات لاحقة.
            يزيح ساعة FIT وتاريخها المعروضين فقط بمقدار -999...999 مللي ثانية. تعرض القيمة الموجبة وقتًا لاحقًا.
            متوسط معدل بت HEVC بوحدة kbps؛ الافتراضي 12000. تُقرأ القيم القديمة الأكبر من 1000000 بوحدة bps.
            معدل البت الصريح القديم بوحدة bps.
            overlay: hevc-alpha (على Apple فقط، الافتراضي)، prores-4444. video: hevc (الافتراضي)، h264.
            وحدة المسافة: km (الافتراضية) أو m.
            منطقة الساعة والتاريخ: activity (الافتراضية) أو system أو اسم IANA مثل Asia/Shanghai. يستخدم activity منطقة النظام عند تعذر تحديدها؛ وتحتفظ المشاريع بخيارها ما لم يُحدد بديل صراحةً.
            يبدأ بيانات الطبقة من هذه الثانية المنقضية في النشاط الأصلي ويعيد عدّ الوقت.
            يوقف بيانات الطبقة عند هذه الثانية المنقضية في النشاط الأصلي.
            اسم/معرّف التخطيط أو ملف .dlspreset. لا يُستخدم مع --timeline-project.
            يتجاوز التحقق من CRC لملف FIT؛ ويُتجاهل مع GPX.
            يعرض بيانات الفيديو والنشاط الوصفية دون تصيير.
            يستبدل الإخراج الموجود. لا يستبدل ملفات الإدخال مطلقًا.
            لغة المساعدة؛ تتبع لغة النظام أو الطرفية افتراضيًا، وتستخدم الإنجليزية عند عدم التطابق. مثال: --language ar --help.
            يعرض هذه المساعدة. الخياران -h و--help متكافئان.
            """
        case .hi:
            text = """
            उपयोग
            आवश्यक इनपुट
            विकल्प
            मानक FIT/GPX गतिविधि फ़ाइल। --fit या --timeline-project में से एक का उपयोग करें।
            DataLayer Studio की .dlsproj प्रोजेक्ट फ़ाइल।
            आउटपुट वीडियो। अलग-अलग क्लिप के लिए name_01.mov, name_02.mov आदि नाम उपयोग होते हैं।
            वैकल्पिक स्रोत वीडियो। वीडियो न होने पर video मोड काला कैनवास उपयोग करता है।
            overlay: पारदर्शी Alpha (एक स्रोत का डिफ़ॉल्ट); video: अपारदर्शी संयोजन। प्रोजेक्ट में सहेजे गए मोड, कोडेक, बिटरेट, ट्रिम और दायरे लागू रहते हैं; स्पष्ट विकल्प संबंधित मान बदलते हैं।
            आउटपुट चौड़ाई: 2...16384 के बीच सम पूर्णांक। डिफ़ॉल्ट स्रोत चौड़ाई है, वीडियो न होने पर 1920।
            आउटपुट ऊँचाई: 2...16384 के बीच सम पूर्णांक। डिफ़ॉल्ट स्रोत ऊँचाई है, वीडियो न होने पर 1080।
            फ़्रेम दर, कम से कम 1। डिफ़ॉल्ट स्रोत दर है, वीडियो न होने पर 30।
            वीडियो के समय 0 पर गतिविधि के बीते सेकंड; गतिविधि के बीच में शुरू की गई रिकॉर्डिंग के लिए।
            सिंक बिंदु पर वीडियो का समय, सेकंड में। --sync-fit आवश्यक है।
            उसी सिंक बिंदु पर गतिविधि के बीते सेकंड। --sync-video आवश्यक है।
            पुराना ऑफ़सेट: वीडियो FIT से SEC सेकंड पहले शुरू होता है; ऋणात्मक मान गतिविधि के बीच से शुरू होता है।
            गतिविधि समय और सभी नमूनों को -999...999 मिलीसेकंड खिसकाता है। धनात्मक मान बाद का डेटा चुनता है।
            केवल दिखाई गई FIT घड़ी और तारीख को -999...999 मिलीसेकंड खिसकाता है। धनात्मक मान बाद का समय दिखाता है।
            औसत HEVC बिटरेट, kbps में; डिफ़ॉल्ट 12000। 1000000 से अधिक पुराने मान bps माने जाते हैं।
            पुरानी स्पष्ट बिटरेट, bps में।
            overlay: hevc-alpha (केवल Apple, डिफ़ॉल्ट), prores-4444। video: hevc (डिफ़ॉल्ट), h264।
            दूरी की इकाई: km (डिफ़ॉल्ट) या m।
            घड़ी/तारीख का समय क्षेत्र: activity (डिफ़ॉल्ट), system या Asia/Shanghai जैसा IANA नाम। activity उपलब्ध न होने पर सिस्टम का समय क्षेत्र उपयोग होता है; स्पष्ट बदलाव के बिना प्रोजेक्ट का सहेजा विकल्प बना रहता है।
            मूल गतिविधि के इन बीते सेकंड से परत का डेटा शुरू करता है और समय की गणना फिर से शुरू करता है।
            मूल गतिविधि के इन बीते सेकंड पर परत का डेटा रोकता है।
            लेआउट का नाम/ID या .dlspreset फ़ाइल। --timeline-project के साथ उपयोग नहीं होता।
            FIT CRC जाँच छोड़ता है; GPX में अनदेखा होता है।
            बिना रेंडर किए वीडियो/गतिविधि का मेटाडेटा दिखाता है।
            मौजूदा आउटपुट बदलता है। इनपुट फ़ाइलें कभी नहीं बदलता।
            सहायता की भाषा; डिफ़ॉल्ट सिस्टम या टर्मिनल की भाषा है, मेल न मिलने पर अंग्रेज़ी। उदाहरण: --language hi --help।
            यह सहायता दिखाता है। -h और --help समान हैं।
            """
        }
        return text.components(separatedBy: "\n")
    }
}
