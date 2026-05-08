import Foundation
import ZuTunCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let parsed = TodoMarkdownParser.parse(
    """
    # Todo

    Notes stay here.
    - [ ] (P1) Finish the little app
    - [x] (P3) Make coffee
    - [ ] Untagged task
    """
)

check(parsed.todos.count == 3, "expected three todos")
check(parsed.openTodos.map(\.title) == ["Finish the little app", "Untagged task"], "expected prioritized open sort")
check(parsed.completedTodos.first?.title == "Make coffee", "expected completed todo")
check(parsed.todos.first?.priority == .p1, "expected P1 parse")
check(parsed.todos.last?.priority == nil, "expected missing priority parse")

var updated = parsed
let first = updated.todos[0]
updated.updateTodo(id: first.id) {
    $0.isCompleted = true
    $0.priority = .p2
}

check(
    updated.renderedMarkdown() ==
        """
        # Todo

        Notes stay here.
        - [x] (P2) Finish the little app
        - [x] (P3) Make coffee
        - [ ] Untagged task
        """
        + "\n",
    "expected canonical render after update"
)

var appended = TodoMarkdownParser.parse(
    """
    # Todo

    - [x] (P3) Old done
    """
)
appended.appendTodo(title: "New work", priority: .p2)

check(
    appended.renderedMarkdown() ==
        """
        # Todo

        - [ ] (P2) New work
        - [x] (P3) Old done
        """
        + "\n",
    "expected new todos before completed items"
)

print("ZuTunParserCheck passed")
