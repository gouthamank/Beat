import Foundation

/// The user's sidebar: folders and pages mixed freely at every level. Pure value type, so
/// every structural edit is unit-testable and `PageStore` only has to persist the result.
struct PageTree: Codable, Hashable, Sendable {
    var nodes: [SidebarNode] = []

    // MARK: Lookup

    func node(_ id: UUID) -> SidebarNode? { Self.find(id, in: nodes) }

    /// The folder holding `id` (nil for the top level) and its index there.
    func location(of id: UUID) -> (parent: UUID?, index: Int)? { Self.locate(id, in: nodes, parent: nil) }

    /// Every page, depth-first, with its folder path ("Deep ▸ DnB ▸ Auxiliary").
    var pages: [(id: UUID, path: String)] {
        var out: [(UUID, String)] = []
        func walk(_ nodes: [SidebarNode], _ prefix: String) {
            for n in nodes {
                let path = prefix.isEmpty ? n.name : "\(prefix) ▸ \(n.name)"
                switch n.content {
                case .page: out.append((n.id, path))
                case .folder(let children): walk(children, path)
                }
            }
        }
        walk(nodes, "")
        return out
    }

    /// Every folder, depth-first, with its nesting depth (for indented menus).
    var folders: [(node: SidebarNode, depth: Int)] {
        var out: [(SidebarNode, Int)] = []
        func walk(_ nodes: [SidebarNode], _ depth: Int) {
            for n in nodes {
                if case .folder(let children) = n.content {
                    out.append((n, depth))
                    walk(children, depth + 1)
                }
            }
        }
        walk(nodes, 0)
        return out
    }

    var firstPageID: UUID? { pages.first?.id }

    /// The folders containing `id`, outermost first. Empty for top-level items and unknown ids.
    func ancestors(of id: UUID) -> [UUID] {
        var out: [UUID] = []
        var current = id
        while let parent = location(of: current)?.parent {
            out.insert(parent, at: 0)
            current = parent
        }
        return out
    }

    /// Whether `id` is `ancestor` itself or somewhere inside it.
    func isWithin(_ id: UUID, _ ancestor: UUID) -> Bool {
        guard let a = node(ancestor) else { return false }
        return a.id == id || (a.children.map { Self.find(id, in: $0) != nil } ?? false)
    }

    func pageCount(in id: UUID) -> Int {
        guard let n = node(id) else { return 0 }
        switch n.content {
        case .page: return 1
        case .folder(let children): return children.reduce(0) { $0 + pageCount(in: $1.id) }
        }
    }

    // MARK: Structure

    /// Inserts into a folder (nil for the top level), at `index` or the end. A page can't take children.
    @discardableResult
    mutating func insert(_ node: SidebarNode, into parent: UUID?, at index: Int? = nil) -> Bool {
        guard let parent else {
            nodes.insert(node, at: (index ?? nodes.count).clamped(to: 0...nodes.count))
            return true
        }
        return Self.modify(parent, in: &nodes) { folder in
            guard case .folder(var children) = folder.content else { return false }
            children.insert(node, at: (index ?? children.count).clamped(to: 0...children.count))
            folder.content = .folder(children)
            return true
        }
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> SidebarNode? { Self.remove(id, from: &nodes) }

    /// Moves `id` into a folder (nil for the top level). `index` refers to the destination as it is
    /// before the move. Refuses a page as the destination, and a folder into itself or its descendants.
    @discardableResult
    mutating func move(_ id: UUID, into parent: UUID?, at index: Int? = nil) -> Bool {
        guard let from = location(of: id) else { return false }
        if let parent {
            guard node(parent)?.isFolder == true, !isWithin(parent, id) else { return false }
        }
        var index = index
        if let i = index, from.parent == parent, from.index < i { index = i - 1 }
        guard let moving = remove(id) else { return false }
        return insert(moving, into: parent, at: index)
    }

    /// Inserts a copy (fresh IDs throughout) right after the original and returns its ID.
    @discardableResult
    mutating func duplicate(_ id: UUID) -> UUID? {
        guard let original = node(id), let at = location(of: id) else { return nil }
        var copy = original.withNewIDs()
        copy.name += " Copy"
        insert(copy, into: at.parent, at: at.index + 1)
        return copy.id
    }

    mutating func update(_ id: UUID, _ body: (inout SidebarNode) -> Void) {
        Self.modify(id, in: &nodes) { body(&$0); return true }
    }

    /// Edits a page's elements. Does nothing if `id` isn't a page.
    mutating func updatePage(_ id: UUID, _ body: (inout Page) -> Void) {
        update(id) { node in
            guard case .page(var page) = node.content else { return }
            body(&page)
            node.content = .page(page)
        }
    }

    /// Edits every element on every page, at any depth.
    mutating func updateElements(_ body: (inout PageElement) -> Void) {
        Self.updateElements(in: &nodes, body)
    }

    // MARK: Recursion

    private static func updateElements(in nodes: inout [SidebarNode], _ body: (inout PageElement) -> Void) {
        for i in nodes.indices {
            switch nodes[i].content {
            case .folder(var children):
                updateElements(in: &children, body)
                nodes[i].content = .folder(children)
            case .page(var page):
                for j in page.elements.indices { body(&page.elements[j]) }
                nodes[i].content = .page(page)
            }
        }
    }

    private static func find(_ id: UUID, in nodes: [SidebarNode]) -> SidebarNode? {
        for n in nodes {
            if n.id == id { return n }
            if let children = n.children, let hit = find(id, in: children) { return hit }
        }
        return nil
    }

    private static func locate(_ id: UUID, in nodes: [SidebarNode], parent: UUID?) -> (parent: UUID?, index: Int)? {
        for (i, n) in nodes.enumerated() {
            if n.id == id { return (parent, i) }
            if let children = n.children, let hit = locate(id, in: children, parent: n.id) { return hit }
        }
        return nil
    }

    @discardableResult
    private static func modify(_ id: UUID, in nodes: inout [SidebarNode], _ body: (inout SidebarNode) -> Bool) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id { return body(&nodes[i]) }
            if case .folder(var children) = nodes[i].content, find(id, in: children) != nil {
                let done = modify(id, in: &children, body)
                nodes[i].content = .folder(children)
                return done
            }
        }
        return false
    }

    private static func remove(_ id: UUID, from nodes: inout [SidebarNode]) -> SidebarNode? {
        if let i = nodes.firstIndex(where: { $0.id == id }) { return nodes.remove(at: i) }
        for i in nodes.indices {
            if case .folder(var children) = nodes[i].content, let hit = remove(id, from: &children) {
                nodes[i].content = .folder(children)
                return hit
            }
        }
        return nil
    }
}
