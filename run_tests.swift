#!/usr/bin/env swift
// KoreanTalk component tests — run with: swift run_tests.swift
// Tests: IntentDetector logic, SystemPromptBuilder output, live Gemini API call

import Foundation

// ─── Helpers ─────────────────────────────────────────────────────────────────

var passed = 0
var failed = 0

func test(_ name: String, _ condition: Bool, detail: String = "") {
    if condition {
        print("  ✅ \(name)")
        passed += 1
    } else {
        print("  ❌ \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        failed += 1
    }
}

func section(_ title: String) {
    print("\n── \(title) " + String(repeating: "─", count: max(0, 50 - title.count)))
}

// ─── Inline copy of pure-logic types (no iOS frameworks needed) ───────────────

enum DifficultyLevel: String, CaseIterable {
    case beginner, intermediate, advanced

    var displayName: String { rawValue.capitalized }

    func stepped(up: Bool) -> DifficultyLevel {
        let all = DifficultyLevel.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        if up   { return index < all.count - 1 ? all[index + 1] : self }
        else    { return index > 0             ? all[index - 1] : self }
    }
}

enum UserIntent: Equatable {
    case help, continueConversation, normalInput
    case setDifficulty(DifficultyLevel)
    case adjustSpeed(SpeedAdjustment)
    enum SpeedAdjustment: Equatable { case slower, faster }
}

func detectIntent(_ text: String, difficulty: DifficultyLevel = .beginner) -> UserIntent {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    func matches(_ patterns: [String]) -> Bool { patterns.contains { lower.contains($0) } }

    if matches(["help","도움말","뭐라고","explain","i don't understand"])   { return .help }
    if matches(["continue","계속","go on","resume","keep going"])           { return .continueConversation }
    if matches(["beginner","easy mode","초급"])                             { return .setDifficulty(.beginner) }
    if matches(["intermediate","medium level","중급"])                      { return .setDifficulty(.intermediate) }
    if matches(["advanced","expert","고급","native level"])                 { return .setDifficulty(.advanced) }
    if matches(["harder","more difficult","level up","더 어렵게","too easy"]) { return .setDifficulty(difficulty.stepped(up: true)) }
    if matches(["easier","make it easier","too hard","더 쉽게","simplify"]) { return .setDifficulty(difficulty.stepped(up: false)) }
    if matches(["slower","slow down","too fast","천천히","느리게"])           { return .adjustSpeed(.slower) }
    if matches(["faster","speed up","빨리","빠르게"])                        { return .adjustSpeed(.faster) }
    return .normalInput
}

// ─── TEST 1: IntentDetector ───────────────────────────────────────────────────

section("IntentDetector")

test("'help' → .help",                    detectIntent("help")                    == .help)
test("'도움말' → .help",                   detectIntent("도움말")                   == .help)
test("'I don't understand' → .help",      detectIntent("I don't understand")      == .help)
test("'explain that' → .help",            detectIntent("explain that please")     == .help)
test("'continue' → .continueConversation",detectIntent("continue")                == .continueConversation)
test("'계속' → .continueConversation",     detectIntent("계속 해주세요")             == .continueConversation)
test("'go on' → .continueConversation",   detectIntent("go on please")            == .continueConversation)
test("'beginner' → .setDifficulty",       detectIntent("beginner")                == .setDifficulty(.beginner))
test("'advanced' → .setDifficulty",       detectIntent("advanced please")         == .setDifficulty(.advanced))
test("'intermediate' → .setDifficulty",   detectIntent("intermediate")            == .setDifficulty(.intermediate))
test("'harder' from beginner → intermediate", detectIntent("harder", difficulty: .beginner) == .setDifficulty(.intermediate))
test("'harder' from advanced stays advanced", detectIntent("harder", difficulty: .advanced) == .setDifficulty(.advanced))
test("'easier' from advanced → intermediate", detectIntent("easier", difficulty: .advanced) == .setDifficulty(.intermediate))
test("'easier' from beginner stays beginner", detectIntent("easier", difficulty: .beginner) == .setDifficulty(.beginner))
test("'slower' → .adjustSpeed(.slower)",  detectIntent("slower please")           == .adjustSpeed(.slower))
test("'천천히' → .adjustSpeed(.slower)",   detectIntent("천천히 해주세요")            == .adjustSpeed(.slower))
test("'faster' → .adjustSpeed(.faster)",  detectIntent("go faster")               == .adjustSpeed(.faster))
test("'빨리' → .adjustSpeed(.faster)",     detectIntent("더 빨리")                   == .adjustSpeed(.faster))
test("'안녕하세요' → .normalInput",          detectIntent("안녕하세요")                == .normalInput)
test("Normal Korean → .normalInput",      detectIntent("오늘 날씨가 좋네요")         == .normalInput)
test("Mixed Korean/English → .normalInput", detectIntent("저는 학생이에요") == .normalInput)

// ─── TEST 2: DifficultyLevel stepping ────────────────────────────────────────

section("DifficultyLevel.stepped")

test("beginner.stepped(up: true)  → intermediate", DifficultyLevel.beginner.stepped(up: true)      == .intermediate)
test("intermediate.stepped(up: true)  → advanced", DifficultyLevel.intermediate.stepped(up: true)  == .advanced)
test("advanced.stepped(up: true)  stays advanced", DifficultyLevel.advanced.stepped(up: true)      == .advanced)
test("advanced.stepped(up: false) → intermediate", DifficultyLevel.advanced.stepped(up: false)     == .intermediate)
test("intermediate.stepped(up: false) → beginner", DifficultyLevel.intermediate.stepped(up: false) == .beginner)
test("beginner.stepped(up: false) stays beginner", DifficultyLevel.beginner.stepped(up: false)     == .beginner)

// ─── TEST 3: SystemPromptBuilder output ──────────────────────────────────────

section("SystemPromptBuilder")

func buildPrompt(difficulty: DifficultyLevel) -> String {
    let difficultyBlock: String
    switch difficulty {
    case .beginner:
        difficultyBlock = "Use only basic, everyday vocabulary"
    case .intermediate:
        difficultyBlock = "Use varied vocabulary including common idioms"
    case .advanced:
        difficultyBlock = "Speak as a native Korean would"
    }

    return """
    DIFFICULTY: \(difficulty.rawValue.uppercased())
    Korean only. Short responses. End with question.
    HELP: explain in English, wait for 'continue'.
    \(difficultyBlock)
    """
}

let beginnerPrompt     = buildPrompt(difficulty: .beginner)
let intermediatePrompt = buildPrompt(difficulty: .intermediate)
let advancedPrompt     = buildPrompt(difficulty: .advanced)

test("Beginner prompt contains 'BEGINNER'",         beginnerPrompt.contains("BEGINNER"))
test("Beginner prompt contains vocabulary hint",    beginnerPrompt.contains("basic"))
test("Intermediate prompt contains 'INTERMEDIATE'", intermediatePrompt.contains("INTERMEDIATE"))
test("Advanced prompt contains 'ADVANCED'",         advancedPrompt.contains("ADVANCED"))
test("All prompts contain HELP instructions",
     beginnerPrompt.contains("HELP") && intermediatePrompt.contains("HELP") && advancedPrompt.contains("HELP"))
test("Prompts are distinct from each other",
     beginnerPrompt != intermediatePrompt && intermediatePrompt != advancedPrompt)

// ─── TEST 4: Live Gemini API call ─────────────────────────────────────────────

section("Live Gemini API (real network call)")

let apiKey  = "AIzaSyCSA4m2iB2BC8ibUVGJdD07ddzY7JAoCtc"
let baseURL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
let model   = "gemini-2.0-flash"

print("  Sending test request to Gemini…")

let semaphore = DispatchSemaphore(value: 0)
var apiTestPassed = false
var apiError = ""
var apiResponse = ""

let urlRequest: URLRequest = {
    var req = URLRequest(url: URL(string: baseURL)!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.timeoutInterval = 20

    let body: [String: Any] = [
        "model": model,
        "messages": [["role": "user", "content": "Say exactly: 안녕하세요"]],
        "stream": false,
        "max_tokens": 30
    ]
    req.httpBody = try! JSONSerialization.data(withJSONObject: body)
    return req
}()

URLSession.shared.dataTask(with: urlRequest) { data, response, error in
    defer { semaphore.signal() }

    if let error {
        apiError = "Network error: \(error.localizedDescription)"
        return
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        apiError = "No HTTP response"
        return
    }

    guard httpResponse.statusCode == 200 else {
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        apiError = "HTTP \(httpResponse.statusCode): \(body)"
        return
    }

    guard
        let data,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let choices = json["choices"] as? [[String: Any]],
        let message = choices.first?["message"] as? [String: Any],
        let content = message["content"] as? String
    else {
        apiError = "Unexpected response format: \(data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil")"
        return
    }

    apiResponse = content
    apiTestPassed = !content.isEmpty
}.resume()

semaphore.wait()

test("API key accepted (HTTP 200)",          apiTestPassed, detail: apiError)
test("Response is non-empty",                !apiResponse.isEmpty, detail: apiResponse)
test("Response contains Korean characters",  apiResponse.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 },
     detail: "Got: \(apiResponse)")

if apiTestPassed {
    print("  📨 AI replied: \"\(apiResponse.prefix(120))\"")
}

// ─── Summary ──────────────────────────────────────────────────────────────────

print("\n" + String(repeating: "─", count: 52))
print("Results: \(passed) passed, \(failed) failed")

if failed == 0 {
    print("✅ All tests passed — app logic is good to go")
} else {
    print("❌ \(failed) test(s) failed — check output above")
    exit(1)
}
