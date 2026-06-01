// © 2026  Cristian Felipe Patiño Rojas. Created on 1/6/26.
import Testing

struct CLI {
    let flags: [String: () -> Void]
    let parser: () -> String
    func run(_ flag: String) {
        flags[flag]?()
    }
    
    func run() {
        let flag = parser()
        flags[flag]?()
    }
}

/*
 
 cli design
CLI.input.run()
 */

@Suite struct CLITests {
    
    @Test func run_executes_action_for_flag() {
        var called = false
        let sut = CLI(flags: ["f": { called = true }], parser: { "any flay" })
        sut.run("f")
        #expect(called)
    }
    
    @Test func run_executes_action() {
        var called = false
        let sut = CLI(
            flags: [anyFlag(): { called = true }],
            parser: { anyFlag() }
        )
        
        sut.run()
        #expect(called)
    }
    
    func anyFlag() -> String {"any flag"}
    func anyAction() -> () -> Void {{}}
}
