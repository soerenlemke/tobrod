package dom

import "core:fmt"
import "core:strings"

// Indented text form of the tree, one node per line, for debugging and tests:
//   <body>
//     <a href="/x">
//       "Hi"
tree_to_string :: proc(node: ^Node, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	write_node(&b, node, 0)
	return strings.to_string(b)
}

@(private)
write_node :: proc(b: ^strings.Builder, node: ^Node, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}

	switch node.kind {
	case .Document:
		strings.write_string(b, "#document")
	case .Element:
		fmt.sbprintf(b, "<%s", node.tag)
		for attr in node.attributes {
			fmt.sbprintf(b, " %s=%q", attr.name, attr.value)
		}
		strings.write_string(b, ">")
	case .Text:
		fmt.sbprintf(b, "%q", node.text)
	case .Comment:
		fmt.sbprintf(b, "<!--%s-->", node.text)
	}
	strings.write_string(b, "\n")

	for child in node.children {
		write_node(b, child, depth + 1)
	}
}
