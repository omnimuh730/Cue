import Foundation
import Testing
@testable import Cue

struct SkillTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "cue-skills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func parsesFrontMatterAndFallbacks() throws {
        let skill = try #require(SkillCatalog.parse("""
        ---
        name: "Code Review"
        description: Review a diff carefully
        ---

        # Reviewer
        Be thorough.
        """, fallbackName: "ignored", sourcePath: "/x/review.md", scope: .global))
        #expect(skill.name == "code-review")
        #expect(skill.description == "Review a diff carefully")
        #expect(skill.body == "# Reviewer\nBe thorough.")

        let plain = try #require(SkillCatalog.parse("# Summarize\nKeep it short.", fallbackName: "Summarize It", sourcePath: "/x/s.md", scope: .project))
        #expect(plain.name == "summarize-it")
        #expect(plain.description == "Summarize")
        #expect(plain.body.hasPrefix("# Summarize"))

        let unterminated = try #require(SkillCatalog.parse("---\nname: nope\nbody without closing", fallbackName: "raw", sourcePath: "/x/raw.md", scope: .global))
        #expect(unterminated.name == "raw")
        #expect(unterminated.body.hasPrefix("---"))

        #expect(SkillCatalog.parse("   \n", fallbackName: "empty", sourcePath: "/x/e.md", scope: .global) == nil)
    }

    @Test func loadsFilesAndFoldersWithProjectOverride() throws {
        let global = try makeRoot()
        try "Global review.".write(to: global.appending(path: "review.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: global.appending(path: "deploy"), withIntermediateDirectories: true)
        try "---\ndescription: Ship it\n---\nDeploy steps.".write(to: global.appending(path: "deploy/SKILL.md"), atomically: true, encoding: .utf8)
        try "not a skill".write(to: global.appending(path: "notes.txt"), atomically: true, encoding: .utf8)

        let project = try makeRoot()
        let claude = project.appending(path: ".claude/skills/review")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try "Project review.".write(to: claude.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let cue = project.appending(path: ".cue/skills")
        try FileManager.default.createDirectory(at: cue, withIntermediateDirectories: true)
        try "Test plan.".write(to: cue.appending(path: "test-plan.md"), atomically: true, encoding: .utf8)

        let globalOnly = SkillCatalog.load(globalRoot: global)
        #expect(globalOnly.map(\.name) == ["deploy", "review"])
        #expect(globalOnly.first { $0.name == "deploy" }?.description == "Ship it")
        #expect(globalOnly.allSatisfy { $0.scope == .global })

        let merged = SkillCatalog.load(globalRoot: global, projectFolder: project.path)
        #expect(merged.map(\.name) == ["deploy", "review", "test-plan"])
        let review = try #require(merged.first { $0.name == "review" })
        #expect(review.scope == .project)
        #expect(review.body == "Project review.")

        #expect(SkillCatalog.load(globalRoot: global.appending(path: "missing")).isEmpty)
    }

    @Test func invocationQueryAndFiltering() {
        #expect(SkillInvocation.query(in: "/") == "")
        #expect(SkillInvocation.query(in: "/rev") == "rev")
        #expect(SkillInvocation.query(in: "/review now") == nil)
        #expect(SkillInvocation.query(in: "hello /review") == "review")
        #expect(SkillInvocation.query(in: "hello /") == "")
        #expect(SkillInvocation.query(in: "line one\n/sum") == "sum")
        #expect(SkillInvocation.query(in: "2/3") == nil)
        #expect(SkillInvocation.query(in: "see ~/Desktop/notes") == nil)
        #expect(SkillInvocation.query(in: "match /G^3i/(x)") == nil)
        #expect(SkillInvocation.query(in: "") == nil)

        #expect(SkillInvocation.removingQuery(from: "hello /rev") == "hello")
        #expect(SkillInvocation.removingQuery(from: "/rev") == "")
        #expect(SkillInvocation.removingQuery(from: "used /review already") == "used /review already")

        let skills = [
            SkillDefinition(name: "code-review", description: "Review a diff", body: "b", sourcePath: "/a", scope: .global),
            SkillDefinition(name: "release", description: "Cut a release", body: "b", sourcePath: "/b", scope: .global),
            SkillDefinition(name: "summarize", description: "Short summaries", body: "b", sourcePath: "/c", scope: .global)
        ]
        #expect(SkillInvocation.filter(skills, query: "").map(\.name) == ["code-review", "release", "summarize"])
        #expect(SkillInvocation.filter(skills, query: "re").map(\.name) == ["release", "code-review", "summarize"])
        #expect(SkillInvocation.filter(skills, query: "cr").map(\.name) == ["code-review"])
        #expect(SkillInvocation.filter(skills, query: "short").map(\.name) == ["summarize"])
        #expect(SkillInvocation.filter(skills, query: "zzz").isEmpty)

        let attachment = SkillInvocation.attachment(for: skills[0])
        #expect(attachment.kind == .skill)
        #expect(attachment.name == "code-review")
        #expect(attachment.text == "b")
    }
}
