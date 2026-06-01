// © 2026  Cristian Felipe Patiño Rojas. Created on 1/6/26.
import Testing

struct CLI {
    let flags: [String: () -> Void]
    func run(_ flag: String) {
        flags[flag]?()
    }
}

@Suite struct CLITests {
    
    @Test func run_executes_action_for_flag() {
        var called = false
        let sut = CLI(flags: ["f": { called = true }])
        sut.run("f")
        #expect(called)
    }
}
