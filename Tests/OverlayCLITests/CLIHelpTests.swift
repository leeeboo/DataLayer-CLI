import XCTest
@testable import DataLayerCLICommand

final class CLIHelpTests: XCTestCase {
    func testAllTwelveLanguagesContainEveryOptionAndCompleteDescriptions() {
        XCTAssertEqual(CLIHelpLanguage.allCases.map(\.rawValue),
                       ["en", "zh-CN", "zh-TW", "ja", "ko", "es", "fr", "de", "pt-BR", "ru", "ar", "hi"])
        var texts = Set<String>()
        for language in CLIHelpLanguage.allCases {
            XCTAssertEqual(language.helpLines.count, CLIHelp.syntax.count + 3, language.rawValue)
            XCTAssertTrue(language.helpLines.allSatisfy { !$0.isEmpty })
            let text = CLIHelp.text(language)
            for syntax in CLIHelp.syntax { XCTAssertTrue(text.contains("  " + syntax + "\n"), syntax) }
            for token in [".dlspreset", ".dlsproj", "hevc-alpha", "prores-4444", "h264", "12000", "1000000", "-999...999", "2...16384"] {
                XCTAssertTrue(text.contains(token), "\(language.rawValue): \(token)")
            }
            XCTAssertFalse(text.contains("JSON"))
            texts.insert(text)
        }
        XCTAssertEqual(texts.count, 12)
    }

    func testLocaleAliasesScriptsAndRegions() {
        let cases: [(String, CLIHelpLanguage)] = [
            ("en_US.UTF-8", .en), ("zh", .zhCN), ("zh_CN.UTF-8", .zhCN), ("zh-SG", .zhCN),
            ("zh_TW", .zhTW), ("zh-HK", .zhTW), ("zh-MO", .zhTW),
            ("zh-Hant-CN", .zhTW), ("zh-Hans-TW", .zhCN), (" ZH_hAnT ", .zhTW),
            ("ja_JP.UTF-8", .ja), ("ko-KR", .ko), ("es-MX", .es), ("fr-CA", .fr),
            ("de_DE@euro", .de), ("pt-PT", .ptBR), ("pt_BR.UTF-8", .ptBR), ("ru-RU", .ru),
            ("ar-SA", .ar), ("hi-IN", .hi), ("C", .en), ("C.UTF-8", .en), ("POSIX", .en)
        ]
        for (tag, expected) in cases { XCTAssertEqual(CLIHelpLanguage.matching(tag), expected, tag) }
        for tag in ["", " ", "xx-YY", "invalid", "sv-SE"] { XCTAssertNil(CLIHelpLanguage.matching(tag)) }
    }

    func testSystemLanguagePrecedenceAndEnglishFallback() {
        let env = ["LC_ALL": "ja_JP.UTF-8", "LC_MESSAGES": "fr", "LANGUAGE": "de:es", "LANG": "zh_CN.UTF-8"]
        XCTAssertEqual(CLIHelpLanguage.system(environment: env, preferredLanguages: ["ko"]), .ja)
        var remaining = env
        remaining.removeValue(forKey: "LC_ALL")
        XCTAssertEqual(CLIHelpLanguage.system(environment: remaining, preferredLanguages: ["ko"]), .fr)
        remaining.removeValue(forKey: "LC_MESSAGES")
        XCTAssertEqual(CLIHelpLanguage.system(environment: remaining, preferredLanguages: ["ko"]), .de)
        remaining.removeValue(forKey: "LANGUAGE")
        XCTAssertEqual(CLIHelpLanguage.system(environment: remaining, preferredLanguages: ["ko"]), .zhCN)
        XCTAssertEqual(CLIHelpLanguage.system(environment: [:], preferredLanguages: ["sv-SE", "zh-Hant"]), .zhTW)
        XCTAssertEqual(CLIHelpLanguage.system(environment: ["LC_ALL": "C", "LANGUAGE": "zh"], preferredLanguages: ["ko"]), .en)
        XCTAssertEqual(CLIHelpLanguage.system(environment: ["LC_ALL": "xx", "LANG": "zh"], preferredLanguages: ["ko"]), .en)
        XCTAssertEqual(CLIHelpLanguage.system(environment: ["LANGUAGE": "sv:fr_CA:ja"], preferredLanguages: []), .fr)
        XCTAssertEqual(CLIHelpLanguage.system(environment: ["LANG": "", "LC_ALL": " "], preferredLanguages: ["ar"]), .ar)
        XCTAssertEqual(CLIHelpLanguage.system(environment: [:], preferredLanguages: ["sv-SE"]), .en)
        XCTAssertEqual(CLIHelpLanguage.system(environment: [:], preferredLanguages: []), .en)
        #if os(Windows)
        XCTAssertFalse(CLIHelpLanguage.platformLanguages.isEmpty, "Native Windows UI languages must be readable")
        #endif
    }

    func testHelpAcceptsLanguageBeforeOrAfterEitherFlagAndEqualsSyntax() {
        for language in CLIHelpLanguage.allCases {
            for flag in ["-h", "--help"] {
                for arguments in [["overlay", "--language", language.rawValue, flag],
                                  ["overlay", flag, "--language", language.rawValue],
                                  ["overlay", flag, "--language=" + language.rawValue]] {
                    XCTAssertThrowsError(try CommandLineOptions.parse(arguments: arguments)) { error in
                        guard case let CLIError.helpRequested(selected) = error else { return XCTFail("\(error)") }
                        XCTAssertEqual(selected, language)
                        XCTAssertEqual(String(describing: error), CLIHelp.text(language))
                    }
                }
            }
        }
    }

    func testInvalidOrMissingManualLanguageIsRejectedEvenAfterHelp() {
        for value in ["", "unknown", "sv-SE"] {
            XCTAssertThrowsError(try CommandLineOptions.parse(arguments: ["overlay", "--help", "--language=" + value])) { error in
                guard case CLIError.invalidLanguage(value) = error else { return XCTFail("\(error)") }
            }
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(arguments: ["overlay", "--help", "--language"])) { error in
            guard case CLIError.missingValue("--language") = error else { return XCTFail("\(error)") }
        }
    }

    func testLanguageDoesNotChangeExportOptionsOrConsumeFileValuesAsFlags() throws {
        let args = ["overlay", "--fit", "--help", "--output", "movie.mov", "--codec", "prores-4444"]
        let baseline = try CommandLineOptions.parse(arguments: args)
        for language in CLIHelpLanguage.allCases {
            let options = try CommandLineOptions.parse(arguments: args + ["--language", language.rawValue])
            XCTAssertEqual(options.specifiedArguments, baseline.specifiedArguments)
            XCTAssertEqual(options.fitURL, baseline.fitURL)
            XCTAssertEqual(options.codec, baseline.codec)
            XCTAssertEqual(options.exportMode, baseline.exportMode)
            XCTAssertEqual(options.outputURL, baseline.outputURL)
        }
        let project = try CommandLineOptions.parse(arguments: ["overlay", "--timeline-project", "file.dlsproj", "--output", "movie.mov", "--language", "ja"])
        XCTAssertFalse(project.specifiedArguments.contains("--language"))
    }
}
