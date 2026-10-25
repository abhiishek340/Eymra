import Foundation
import Testing
@testable import Eymra

struct JudgeParsingTests {
    private let answer = """
    {"photos":[
      {"image":2,"category":"VIEW","sharpness":"excellent","exposure":"good","composition":"good","subject":"good",
       "moment":"fair","post_worthiness":"excellent","flags":[],"reason":"Huge sky over the lake"},
      {"image":1,"category":"me","sharpness":"good","exposure":"good","composition":"fair","subject":"good",
       "moment":"good","post_worthiness":"good","flags":["eyes_closed","blurry"],"reason":"Eyes shut"},
      {"image":9,"category":"me","sharpness":"good","exposure":"good","composition":"fair","subject":"good",
       "moment":"good","post_worthiness":"good","flags":[],"reason":"Out of range"}
    ]}
    """

    @Test func mapsImagesBackToPhotosAndScores() throws {
        let scores = try JudgeSchema.parseScores(Data(answer.utf8), sent: ["p1", "p2"])
        #expect(scores.count == 2)
        let view = try #require(scores.first { $0.photoID == "p2" })
        #expect(view.category == .view)                       // case-insensitive
        #expect(abs(view.score - (1 + 0.75 + 0.75 + 0.75 + 0.5 + 1) / 6) < 0.001)
        let me = try #require(scores.first { $0.photoID == "p1" })
        #expect(abs(me.score - max(0, (0.75 * 5 + 0.5) / 6 - 0.25 - 0.15)) < 0.001)
    }

    @Test func levelsAndClamping() {
        #expect(JudgeSchema.level("bad") == 0)
        #expect(JudgeSchema.level("Excellent") == 1)
        #expect(JudgeSchema.level("weird") == 0.5)
        let awful = JudgeSchema.ScoreEntry(image: 1, category: "other", sharpness: "bad", exposure: "bad", composition: "bad",
                                           subject: "bad", moment: "bad", post_worthiness: "bad",
                                           flags: ["blurry", "photobomb", "cut_off"], reason: "")
        #expect(JudgeSchema.score(awful) == 0)
    }

    @Test func bestOfParsing() throws {
        let json = Data(#"{"winner":2,"runner_up":null,"reason":"Better smile"}"#.utf8)
        let best = try JudgeSchema.parseBestOf(json, sent: ["a", "b", "c"])
        #expect(best.winnerID == "b")
        #expect(best.runnerUpID == nil)
        #expect(throws: JudgeError.self) { try JudgeSchema.parseBestOf(Data(#"{"winner":7,"runner_up":1,"reason":""}"#.utf8), sent: ["a"]) }
    }

    @Test func extractsTheFirstTextBlock() throws {
        let response = #"{"content":[{"type":"text","text":"{\"winner\":1,\"runner_up\":null,\"reason\":\"x\"}"}],"stop_reason":"end_turn"}"#
        let json = try ClaudeJudge.extractText(Data(response.utf8))
        #expect(try JudgeSchema.parseBestOf(json, sent: ["only"]).winnerID == "only")
        let refusal = #"{"content":[],"stop_reason":"refusal"}"#
        #expect(throws: JudgeError.self) { try ClaudeJudge.extractText(Data(refusal.utf8)) }
        #expect(ClaudeJudge.errorMessage(Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)) == "invalid x-api-key")
    }

    @Test func requestBodyShape() throws {
        let judge = ClaudeJudge(model: "claude-haiku-5-5", apiKey: "k")
        let body = judge.requestBody(images: [JudgeImage(photoID: "a", jpeg: Data([1, 2])), JudgeImage(photoID: "b", jpeg: Data([3]))],
                                     instruction: "Go", schema: JudgeSchema.scoreSchema, maxTokens: 100)
        let data = try JSONSerialization.data(withJSONObject: body)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(#""cache_control":{"type":"ephemeral"}"#))
        #expect(text.contains(#""media_type":"image\/jpeg""#))
        #expect(text.contains("Image 2:"))
        #expect(text.contains(#""type":"json_schema""#))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.count == 5)                            // 2 × (label + image) + instruction
        #expect(content.last?["text"] as? String == "Go")
    }

    @Test func missingKeyFailsWithoutNetwork() async {
        let judge = ClaudeJudge(model: "m", apiKey: "")
        await #expect(throws: JudgeError.missingKey) { try await judge.score([]) }
    }

    @Test func shortlistCapsRunnerUpsFirst() {
        var clusters: [Cluster] = []
        var scores: [String: PhotoScore] = [:]
        for i in 0..<50 {
            clusters.append(Cluster(id: "c\(i)", sceneID: "s", memberIDs: ["w\(i)", "r\(i)a", "r\(i)b", "r\(i)c"], winnerID: "w\(i)",
                                    runnerUpIDs: ["r\(i)a", "r\(i)b", "r\(i)c"]))
            scores["w\(i)"] = PhotoScore(photoID: "w\(i)", technical: 0, aesthetic: 0, composition: 0, people: nil,
                                         quality: Float(i) / 50, cropFit: [:], category: .view, exclusion: nil)
        }
        let list = JudgeStage.shortlist(clusters: clusters, scores: scores)
        #expect(list.count == Tuning.judgeMaxImages)
        #expect(list.filter { $0.hasPrefix("w") }.count == 50)
        #expect(list.first == "w49")
        #expect(!list.contains("r0c"))
    }
}
