from __future__ import annotations

from dataclasses import dataclass, field
import json
import pathlib
import re
from typing import Any

MODULE_PREFIXES = (
    "Swift.",
    "Foundation.",
    "SwiftUICore.",
    "SwiftUI.",
    "_Concurrency.",
)

SYNTHESIZED_PATTERNS = [
    re.compile(r"^func encode\(to "),
    re.compile(r"^func hash\(into "),
    re.compile(r"^static func == "),
    re.compile(r"^static func != "),
    re.compile(r"^init\(from decoder: "),
    re.compile(r"^init\?\(rawValue: "),
    re.compile(r"^typealias AllCases = "),
    re.compile(r"^typealias RawValue = "),
    re.compile(r"^static var allCases: "),
    re.compile(r"^var hashValue: "),
    re.compile(r"^var rawValue: "),
]

CONTAINER_KIND_IDS = {"swift.struct", "swift.enum", "swift.protocol", "swift.class"}
TYPE_KIND_IDS = CONTAINER_KIND_IDS | {"swift.typealias"}

AVAILABILITY_DOMAIN_ORDER = {
    "macOS": 0,
    "iOS": 1,
    "tvOS": 2,
    "watchOS": 3,
    "visionOS": 4,
    "Mac Catalyst": 5,
}


@dataclass
class Symbol:
    precise_id: str
    kind_id: str
    access_level: str
    path_components: list[str]
    declaration: str
    availability: str | None
    has_location: bool
    swift_extension: dict[str, Any] | None

    @property
    def full_path(self) -> str:
        return ".".join(self.path_components)

    @property
    def short_name(self) -> str:
        return self.path_components[-1]

    @property
    def parent_path(self) -> str | None:
        if len(self.path_components) <= 1:
            return None
        return ".".join(self.path_components[:-1])


@dataclass
class TypeNode:
    path: str
    name: str
    access_level: str
    kind_id: str
    declaration: str
    availability: str | None
    conformances: list[str] = field(default_factory=list)
    raw_type: str | None = None
    child_types: list["TypeNode"] = field(default_factory=list)
    cases: list[str] = field(default_factory=list)
    members: list[str] = field(default_factory=list)


@dataclass
class ExtensionGroup:
    header: str
    availability: str | None
    types: list[TypeNode] = field(default_factory=list)
    members: list[str] = field(default_factory=list)


@dataclass
class ModuleOutline:
    module: str
    typealiases: list[str] = field(default_factory=list)
    globals: list[str] = field(default_factory=list)
    types: list[TypeNode] = field(default_factory=list)
    extensions: list[ExtensionGroup] = field(default_factory=list)


def collapse_ws(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def normalize_text(text: str, module: str) -> str:
    text = text.replace(f"{module}.", "")
    for prefix in MODULE_PREFIXES:
        text = text.replace(prefix, "")
    text = text.replace("@_Concurrency.MainActor", "@MainActor")
    text = text.replace("@preconcurrency ", "")
    text = collapse_ws(text)
    text = re.sub(r"\s+:\s+", ": ", text)
    text = re.sub(r"\s+,\s+", ", ", text)
    text = text.replace("( ", "(")
    text = text.replace(" )", ")")
    return text


def fragments_text(symbol: dict[str, Any], module: str) -> str:
    fragments = symbol.get("declarationFragments") or []
    if fragments:
        return normalize_text("".join(fragment.get("spelling", "") for fragment in fragments), module)
    names = symbol.get("names") or {}
    title = names.get("title") or ""
    return normalize_text(title, module)


def format_availability(entries: list[dict[str, Any]] | None) -> str | None:
    if not entries:
        return None
    parts: list[str] = []
    for entry in sorted(entries, key=lambda item: AVAILABILITY_DOMAIN_ORDER.get(item.get("domain", ""), 999)):
        domain = entry.get("domain")
        introduced = entry.get("introduced") or {}
        major = introduced.get("major")
        minor = introduced.get("minor", 0)
        patch = introduced.get("patch")
        if major is None or not domain:
            continue
        version = f"{major}.{minor}"
        if patch not in (None, 0):
            version += f".{patch}"
        parts.append(f"{domain} {version}")
    if not parts:
        return None
    return "@available(" + ", ".join(parts) + ", *)"


def insert_access_keyword(declaration: str, access_level: str) -> str:
    if declaration.startswith(("public ", "open ", "case ", "extension ")):
        return declaration
    if access_level not in {"public", "open"}:
        return declaration
    if declaration.startswith("@"):
        first_space = declaration.find(" ")
        if first_space == -1:
            return declaration
        return declaration[: first_space + 1] + access_level + " " + declaration[first_space + 1 :]
    return f"{access_level} {declaration}"


def member_sort_key(declaration: str) -> tuple[int, str]:
    stripped = declaration.removeprefix("public ").removeprefix("open ")
    if stripped.startswith(("static let ", "class let ")):
        return (2, declaration.casefold())
    if stripped.startswith(("let ", "var ", "static var ", "class var ")):
        return (1, declaration.casefold())
    if stripped.startswith("init"):
        return (3, declaration.casefold())
    if stripped.startswith("func ") or stripped.startswith("@MainActor public func") or stripped.startswith("@MainActor func"):
        return (4, declaration.casefold())
    if stripped.startswith("subscript"):
        return (5, declaration.casefold())
    return (6, declaration.casefold())


def type_sort_key(node: TypeNode) -> tuple[str, str]:
    kind_rank = {
        "swift.protocol": 0,
        "swift.struct": 1,
        "swift.enum": 2,
        "swift.class": 3,
    }.get(node.kind_id, 9)
    return (node.name.casefold(), str(kind_rank))


def top_level_sort_key(declaration: str) -> tuple[str, str]:
    name = declaration
    for prefix in ("public typealias ", "public let ", "public var ", "@MainActor public var ", "public func ", "@MainActor public func "):
        if declaration.startswith(prefix):
            name = declaration[len(prefix) :]
            break
    return (name.casefold(), declaration.casefold())


def parse_raw_type(declaration: str) -> str | None:
    match = re.search(r"init\?\(rawValue: ([^)]+)\)", declaration)
    return match.group(1).strip() if match else None


def is_probably_synthesized(symbol: Symbol) -> bool:
    core = symbol.declaration
    core = core.removeprefix("public ").removeprefix("open ")
    core = core.removeprefix("@MainActor ")
    return any(pattern.match(core) for pattern in SYNTHESIZED_PATTERNS)


def normalize_conformance_name(target: str, precise_to_path: dict[str, str], module: str) -> str:
    if target in precise_to_path:
        return normalize_text(precise_to_path[target], module)
    return normalize_text(target, module)


def finalize_conformances(kind_id: str, conformances: list[str], raw_type: str | None) -> list[str]:
    all_names = set(conformances)
    filtered: list[str] = []
    seen_filtered: set[str] = set()
    for item in conformances:
        if item in {"SendableMetatype", "Decodable", "Encodable", "Equatable", "Hashable", "RawRepresentable"}:
            continue
        if item not in seen_filtered:
            seen_filtered.add(item)
            filtered.append(item)

    ordered: list[str] = []
    seen: set[str] = set()

    def add(item: str) -> None:
        if item and item not in seen:
            ordered.append(item)
            seen.add(item)

    if raw_type:
        add(raw_type)

    builtin_names = {"Sendable", "Hashable", "Codable", "Decodable", "Encodable", "CaseIterable"}
    custom_protocols = [item for item in filtered if item not in builtin_names]
    for item in sorted(custom_protocols, key=str.casefold):
        add(item)

    if "Sendable" in all_names:
        add("Sendable")

    keep_hashable = kind_id != "swift.enum" or not raw_type
    if keep_hashable and "Hashable" in all_names:
        add("Hashable")

    if "Decodable" in all_names and "Encodable" in all_names:
        add("Codable")
    elif "Decodable" in all_names:
        add("Decodable")
    elif "Encodable" in all_names:
        add("Encodable")

    if "CaseIterable" in all_names:
        add("CaseIterable")

    return ordered


def append_conformances(base_declaration: str, conformances: list[str]) -> str:
    if not conformances:
        return base_declaration
    if ":" in base_declaration:
        return base_declaration + ", " + ", ".join(conformances)
    return base_declaration + ": " + ", ".join(conformances)


def render_extension_header(symbol: Symbol, module: str) -> str:
    base = f"extension {normalize_text(symbol.path_components[0], module)}"
    constraints = (symbol.swift_extension or {}).get("constraints") or []
    rendered_constraints: list[str] = []
    for constraint in constraints:
        kind = constraint.get("kind")
        lhs = normalize_text(constraint.get("lhs", ""), module)
        rhs = normalize_text(constraint.get("rhs", ""), module)
        if kind == "sameType" and lhs and rhs:
            rendered_constraints.append(f"{lhs} == {rhs}")
        elif kind == "conformance" and lhs and rhs:
            rendered_constraints.append(f"{lhs}: {rhs}")
    if rendered_constraints:
        base += " where " + ", ".join(sorted(rendered_constraints, key=str.casefold))
    return base + " {"


def load_symbols(symbol_graph_dir: pathlib.Path, module: str) -> tuple[list[Symbol], dict[str, list[str]], dict[str, str], dict[str, str]]:
    symbols: list[Symbol] = []
    conformance_targets: dict[str, list[str]] = {}
    precise_to_path: dict[str, str] = {}
    raw_types: dict[str, str] = {}

    for path in sorted(symbol_graph_dir.glob(f"{module}*.json")):
        payload = json.loads(path.read_text())
        raw_symbols = payload.get("symbols", [])
        if isinstance(raw_symbols, dict):
            raw_symbols = list(raw_symbols.values())
        for raw_symbol in raw_symbols:
            access_level = raw_symbol.get("accessLevel") or "public"
            precise_id = (raw_symbol.get("identifier") or {}).get("precise", "")
            path_components = list(raw_symbol.get("pathComponents") or [])
            declaration = fragments_text(raw_symbol, module)
            symbol = Symbol(
                precise_id=precise_id,
                kind_id=((raw_symbol.get("kind") or {}).get("identifier")) or "symbol",
                access_level=access_level,
                path_components=path_components,
                declaration=declaration,
                availability=format_availability(raw_symbol.get("availability")),
                has_location=bool((raw_symbol.get("location") or {}).get("uri")),
                swift_extension=raw_symbol.get("swiftExtension"),
            )
            symbols.append(symbol)
            if precise_id and path_components:
                precise_to_path[precise_id] = ".".join(path_components)
            if symbol.kind_id == "swift.init":
                parent = symbol.parent_path
                raw_type = parse_raw_type(symbol.declaration)
                if parent and raw_type:
                    raw_types[parent] = raw_type

        for rel in payload.get("relationships", []):
            if rel.get("kind") != "conformsTo":
                continue
            source = rel.get("source")
            target = rel.get("targetFallback") or rel.get("target")
            if source and target:
                conformance_targets.setdefault(source, []).append(str(target))

    return symbols, conformance_targets, precise_to_path, raw_types


def build_outline(symbol_graph_dir: pathlib.Path, module: str) -> ModuleOutline:
    symbols, conformance_targets, precise_to_path, raw_types = load_symbols(symbol_graph_dir, module)
    module_outline = ModuleOutline(module=module)
    type_nodes: dict[str, TypeNode] = {}
    extension_groups: dict[tuple[str, str | None], ExtensionGroup] = {}
    extension_type_groups: dict[str, tuple[str, str | None]] = {}

    kept_symbols: list[Symbol] = []
    for symbol in symbols:
        if symbol.access_level not in {"public", "open"}:
            continue
        if is_probably_synthesized(symbol) and not symbol.has_location:
            continue
        kept_symbols.append(symbol)

    for symbol in kept_symbols:
        if symbol.kind_id in CONTAINER_KIND_IDS:
            conformance_names = [
                normalize_conformance_name(target, precise_to_path, module)
                for target in conformance_targets.get(symbol.precise_id, [])
            ]
            node = TypeNode(
                path=symbol.full_path,
                name=symbol.short_name,
                access_level=symbol.access_level,
                kind_id=symbol.kind_id,
                declaration=symbol.declaration,
                availability=symbol.availability,
                conformances=finalize_conformances(symbol.kind_id, conformance_names, raw_types.get(symbol.full_path)),
                raw_type=raw_types.get(symbol.full_path),
            )
            type_nodes[symbol.full_path] = node
            if symbol.swift_extension:
                extension_type_groups[symbol.full_path] = (render_extension_header(symbol, module), symbol.availability)

    for node in type_nodes.values():
        parent = ".".join(node.path.split(".")[:-1]) if "." in node.path else None
        if parent and parent in type_nodes:
            type_nodes[parent].child_types.append(node)
        elif node.path in extension_type_groups:
            header, availability = extension_type_groups[node.path]
            extension_groups.setdefault((header, availability), ExtensionGroup(header=header, availability=availability)).types.append(node)
        else:
            module_outline.types.append(node)

    for symbol in kept_symbols:
        if symbol.kind_id in CONTAINER_KIND_IDS:
            continue

        if symbol.swift_extension:
            header = render_extension_header(symbol, module)
            key = (header, symbol.availability)
            group = extension_groups.setdefault(key, ExtensionGroup(header=header, availability=symbol.availability))
            group.members.append(insert_access_keyword(symbol.declaration, symbol.access_level))
            continue

        if symbol.kind_id == "swift.typealias" and symbol.parent_path is None:
            module_outline.typealiases.append(insert_access_keyword(symbol.declaration, symbol.access_level))
            continue

        if symbol.kind_id == "swift.enum.case" and symbol.parent_path in type_nodes:
            type_nodes[symbol.parent_path].cases.append(symbol.declaration)
            continue

        if symbol.parent_path in type_nodes:
            parent_node = type_nodes[symbol.parent_path]
            parent_is_protocol = parent_node.kind_id == "swift.protocol"
            if symbol.kind_id == "swift.typealias":
                rendered = insert_access_keyword(symbol.declaration, symbol.access_level)
            elif parent_is_protocol:
                rendered = symbol.declaration
            else:
                rendered = insert_access_keyword(symbol.declaration, symbol.access_level)
            parent_node.members.append(rendered)
            continue

        rendered = insert_access_keyword(symbol.declaration, symbol.access_level)
        if symbol.kind_id in {"swift.var", "swift.func", "swift.init", "swift.property", "swift.method", "swift.subscript"}:
            module_outline.globals.append(rendered)
        elif symbol.kind_id == "swift.typealias":
            module_outline.typealiases.append(rendered)
        else:
            module_outline.globals.append(rendered)

    module_outline.typealiases.sort(key=top_level_sort_key)
    module_outline.globals.sort(key=top_level_sort_key)
    module_outline.extensions = sorted(extension_groups.values(), key=lambda group: (group.header.casefold(), (group.availability or "").casefold()))
    for group in module_outline.extensions:
        group.members.sort(key=member_sort_key)

    return module_outline


def render_type(node: TypeNode, indent: int = 0) -> list[str]:
    lines: list[str] = []
    prefix = " " * indent
    base_declaration = insert_access_keyword(node.declaration, node.access_level)
    header = append_conformances(base_declaration, node.conformances) + " {"
    if node.availability:
        lines.append(prefix + node.availability)
    lines.append(prefix + header)

    children: list[str] = []
    for child in sorted(node.child_types, key=type_sort_key):
        if children:
            children.append("")
        children.extend(render_type(child, indent + 2))

    if node.cases:
        if children:
            children.append("")
        children.extend([" " * (indent + 2) + case for case in sorted(node.cases, key=str.casefold)])

    if node.members:
        if children:
            children.append("")
        children.extend([" " * (indent + 2) + member for member in sorted(node.members, key=member_sort_key)])

    lines.extend(children)
    lines.append(prefix + "}")
    return lines


def render_outline(outline: ModuleOutline) -> str:
    lines = [f"// {outline.module} public API outline", ""]

    sections: list[list[str]] = []
    if outline.typealiases:
        sections.append(outline.typealiases)
    if outline.globals:
        sections.append(outline.globals)
    if outline.types:
        sections.append([line for node in sorted(outline.types, key=type_sort_key) for line in (render_type(node) + [""])][:-1])
    for group in outline.extensions:
        section: list[str] = []
        if group.availability:
            section.append(group.availability)
        section.append(group.header)
        children: list[str] = []
        for type_node in sorted(group.types, key=type_sort_key):
            if children:
                children.append("")
            children.extend(render_type(type_node, indent=2))
        if group.members:
            if children:
                children.append("")
            children.extend(["  " + member for member in group.members])
        section.extend(children)
        section.append("}")
        sections.append(section)

    for index, section in enumerate(sections):
        if index:
            lines.append("")
        lines.extend(section)

    lines.append("")
    return "\n".join(lines)


def render_from_symbol_graph_directory(symbol_graph_dir: pathlib.Path, module: str) -> str:
    outline = build_outline(symbol_graph_dir, module)
    return render_outline(outline)
