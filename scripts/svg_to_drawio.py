#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


SVG_NS = "{http://www.w3.org/2000/svg}"
CSS_RULE_RE = re.compile(r"\.(?P<name>[A-Za-z0-9_-]+)\s*\{(?P<body>.*?)\}", re.S)
CSS_DECL_RE = re.compile(r"([A-Za-z-]+)\s*:\s*([^;]+);?")
TRANSFORM_RE = re.compile(r"translate\(\s*([^) ,]+)(?:[ ,]+([^) ,]+))?\s*\)")
PATH_TOKEN_RE = re.compile(r"[MLCz]|-?\d+(?:\.\d+)?")
FONT_RE = re.compile(r"(?P<weight>\d+)\s+(?P<size>\d+(?:\.\d+)?)px(?:\s+(?P<family>.+))?")


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class FlatNode:
    element: ET.Element
    dx: float
    dy: float
    shadow: bool


def local_name(tag: str) -> str:
    return tag.split("}", 1)[-1]


def fmt(value: float) -> str:
    rounded = round(value, 3)
    if abs(rounded - round(rounded)) < 1e-9:
        return str(int(round(rounded)))
    return f"{rounded:.3f}".rstrip("0").rstrip(".")


def parse_css(style_text: str) -> dict[str, dict[str, str]]:
    rules: dict[str, dict[str, str]] = {}
    for match in CSS_RULE_RE.finditer(style_text):
        body = match.group("body")
        declarations: dict[str, str] = {}
        for key, value in CSS_DECL_RE.findall(body):
            declarations[key.strip()] = value.strip()
        rules[match.group("name")] = declarations
    return rules


def parse_transform(transform: str | None) -> tuple[float, float]:
    if not transform:
        return 0.0, 0.0
    total_x = 0.0
    total_y = 0.0
    for match in TRANSFORM_RE.finditer(transform):
        total_x += float(match.group(1))
        total_y += float(match.group(2) or 0.0)
    return total_x, total_y


def flatten(node: ET.Element, dx: float = 0.0, dy: float = 0.0, shadow: bool = False) -> list[FlatNode]:
    flat: list[FlatNode] = []
    for child in list(node):
        tag = local_name(child.tag)
        if tag in {"defs", "title", "desc"}:
            continue
        child_dx, child_dy = parse_transform(child.attrib.get("transform"))
        child_shadow = shadow or ("shadow" in child.attrib.get("filter", ""))
        if tag == "g":
            flat.extend(flatten(child, dx + child_dx, dy + child_dy, child_shadow))
        else:
            flat.append(FlatNode(child, dx + child_dx, dy + child_dy, child_shadow))
    return flat


def merged_style(element: ET.Element, class_styles: dict[str, dict[str, str]]) -> dict[str, str]:
    merged: dict[str, str] = {}
    classes = element.attrib.get("class", "").split()
    for class_name in classes:
        merged.update(class_styles.get(class_name, {}))
    for key in ("fill", "stroke", "stroke-width", "stroke-dasharray", "font", "text-anchor"):
        if key in element.attrib:
            merged[key] = element.attrib[key]
    return merged


def get_number(text: str | None, default: float = 0.0) -> float:
    if text is None:
        return default
    return float(text)


def parse_font(style: dict[str, str]) -> tuple[float, int, str | None]:
    size = 12.0
    weight = 400
    family: str | None = None
    font_value = style.get("font")
    if font_value:
        match = FONT_RE.search(font_value)
        if match:
            weight = int(match.group("weight"))
            size = float(match.group("size"))
            family_value = (match.group("family") or "").strip()
            if family_value:
                family = family_value.split(",", 1)[0].strip().strip("'\"")
    return size, weight, family


def estimate_text_box(text: str, font_size: float) -> tuple[float, float]:
    longest = max((len(line) for line in text.splitlines()), default=len(text))
    width = max(20.0, longest * font_size * 0.58)
    height = max(font_size * 1.4, 18.0)
    return width, height


def build_style(parts: list[str | tuple[str, str | None]]) -> str:
    rendered: list[str] = []
    for part in parts:
        if isinstance(part, str):
            rendered.append(part)
            continue
        key, value = part
        if value is not None:
            rendered.append(f"{key}={value}")
    return ";".join(rendered) + ";"


def path_points(path_data: str, cubic_samples: int = 12) -> list[Point]:
    tokens = PATH_TOKEN_RE.findall(path_data)
    idx = 0
    points: list[Point] = []
    current = Point(0.0, 0.0)
    start = Point(0.0, 0.0)

    def next_float() -> float:
        nonlocal idx
        value = float(tokens[idx])
        idx += 1
        return value

    while idx < len(tokens):
        cmd = tokens[idx]
        idx += 1

        if cmd == "M":
            current = Point(next_float(), next_float())
            start = current
            points.append(current)
        elif cmd == "L":
            current = Point(next_float(), next_float())
            points.append(current)
        elif cmd == "C":
            control_1 = Point(next_float(), next_float())
            control_2 = Point(next_float(), next_float())
            end = Point(next_float(), next_float())
            for step in range(1, cubic_samples + 1):
                t = step / cubic_samples
                mt = 1.0 - t
                x = (
                    (mt**3) * current.x
                    + 3 * (mt**2) * t * control_1.x
                    + 3 * mt * (t**2) * control_2.x
                    + (t**3) * end.x
                )
                y = (
                    (mt**3) * current.y
                    + 3 * (mt**2) * t * control_1.y
                    + 3 * mt * (t**2) * control_2.y
                    + (t**3) * end.y
                )
                points.append(Point(x, y))
            current = end
        elif cmd == "z":
            points.append(start)
            current = start
        else:
            raise ValueError(f"Unsupported path command: {cmd}")

    deduped: list[Point] = []
    for point in points:
        if not deduped or abs(deduped[-1].x - point.x) > 1e-9 or abs(deduped[-1].y - point.y) > 1e-9:
            deduped.append(point)
    return deduped


def edge_style(style: dict[str, str]) -> str:
    parts: list[tuple[str, str | None]] = [
        ("edgeStyle", "none"),
        ("rounded", "0"),
        ("orthogonalLoop", "0"),
        ("jettySize", "auto"),
        ("html", "1"),
        ("strokeColor", style.get("stroke")),
        ("strokeWidth", style.get("stroke-width", "1")),
    ]
    if style.get("stroke-dasharray"):
        dash = " ".join(style["stroke-dasharray"].replace(",", " ").split())
        parts.append(("dashed", "1"))
        parts.append(("dashPattern", dash))
    if style.get("marker-start"):
        parts.append(("startArrow", "classic"))
        parts.append(("startFill", "1"))
    else:
        parts.append(("startArrow", "none"))
    if style.get("marker-end"):
        parts.append(("endArrow", "classic"))
        parts.append(("endFill", "1"))
    else:
        parts.append(("endArrow", "none"))
    return build_style(parts)


def vertex_style(style: dict[str, str], *, rounded: bool = False, ellipse: bool = False, shadow: bool = False) -> str:
    parts: list[tuple[str, str | None]] = [
        ("whiteSpace", "wrap"),
        ("html", "1"),
        ("fillColor", "none" if style.get("fill") in {None, "none"} else style.get("fill")),
        ("strokeColor", "none" if style.get("stroke") in {None, "none"} else style.get("stroke")),
        ("strokeWidth", style.get("stroke-width", "1")),
    ]
    if rounded:
        parts.append(("rounded", "1"))
    if ellipse:
        parts.append(("shape", "ellipse"))
    if shadow:
        parts.append(("shadow", "1"))
    if style.get("stroke-dasharray"):
        dash = " ".join(style["stroke-dasharray"].replace(",", " ").split())
        parts.append(("dashed", "1"))
        parts.append(("dashPattern", dash))
    return build_style(parts)


def text_style(style: dict[str, str]) -> str:
    font_size, weight, family = parse_font(style)
    anchor = style.get("text-anchor", "start")
    align = {"middle": "center", "end": "right"}.get(anchor, "left")
    parts: list[str | tuple[str, str | None]] = [
        "text",
        ("html", "1"),
        ("whiteSpace", "wrap"),
        ("strokeColor", "none"),
        ("fillColor", "none"),
        ("align", align),
        ("verticalAlign", "middle"),
        ("fontSize", fmt(font_size)),
        ("fontColor", style.get("fill", "#000000")),
    ]
    if weight >= 600:
        parts.append(("fontStyle", "1"))
    if family:
        parts.append(("fontFamily", family))
    return build_style(parts)


def add_geometry(parent: ET.Element, *, x: float, y: float, width: float, height: float) -> None:
    ET.SubElement(
        parent,
        "mxGeometry",
        {
            "x": fmt(x),
            "y": fmt(y),
            "width": fmt(width),
            "height": fmt(height),
            "as": "geometry",
        },
    )


def create_drawio(svg_path: Path, drawio_path: Path) -> None:
    tree = ET.parse(svg_path)
    root = tree.getroot()

    width = int(float(root.attrib.get("width", "2400")))
    height = int(float(root.attrib.get("height", "1680")))
    style_node = root.find(f"{SVG_NS}defs/{SVG_NS}style")
    class_styles = parse_css(style_node.text or "") if style_node is not None else {}

    mxfile = ET.Element(
        "mxfile",
        {
            "host": "app.diagrams.net",
            "agent": "Codex",
            "version": "29.6.6",
        },
    )
    diagram = ET.SubElement(mxfile, "diagram", {"id": "system-architecture-native", "name": "System Architecture"})
    model = ET.SubElement(
        diagram,
        "mxGraphModel",
        {
            "dx": str(width),
            "dy": str(height),
            "grid": "1",
            "gridSize": "10",
            "guides": "1",
            "tooltips": "1",
            "connect": "1",
            "arrows": "1",
            "fold": "1",
            "page": "1",
            "pageScale": "1",
            "pageWidth": str(width),
            "pageHeight": str(height),
            "math": "0",
            "shadow": "0",
        },
    )
    mxroot = ET.SubElement(model, "root")
    ET.SubElement(mxroot, "mxCell", {"id": "0"})
    ET.SubElement(mxroot, "mxCell", {"id": "1", "parent": "0"})

    flattened = flatten(root)
    counter = 2
    index = 0

    def next_id(prefix: str) -> str:
        nonlocal counter
        value = f"{prefix}-{counter}"
        counter += 1
        return value

    while index < len(flattened):
        node = flattened[index]
        element = node.element
        tag = local_name(element.tag)
        style = merged_style(element, class_styles)

        if tag == "rect":
            fill = style.get("fill")
            if fill == "url(#grid)":
                index += 1
                continue

            rect = ET.SubElement(
                mxroot,
                "mxCell",
                {
                    "id": next_id("rect"),
                    "value": "",
                    "style": vertex_style(
                        style,
                        rounded=get_number(element.attrib.get("rx")) > 0 or get_number(element.attrib.get("ry")) > 0,
                        shadow=node.shadow,
                    ),
                    "vertex": "1",
                    "parent": "1",
                },
            )
            add_geometry(
                rect,
                x=get_number(element.attrib.get("x")) + node.dx,
                y=get_number(element.attrib.get("y")) + node.dy,
                width=get_number(element.attrib.get("width")),
                height=get_number(element.attrib.get("height")),
            )

        elif tag == "ellipse":
            ellipse = ET.SubElement(
                mxroot,
                "mxCell",
                {
                    "id": next_id("ellipse"),
                    "value": "",
                    "style": vertex_style(style, ellipse=True, shadow=node.shadow),
                    "vertex": "1",
                    "parent": "1",
                },
            )
            rx = get_number(element.attrib.get("rx"))
            ry = get_number(element.attrib.get("ry"))
            add_geometry(
                ellipse,
                x=get_number(element.attrib.get("cx")) - rx + node.dx,
                y=get_number(element.attrib.get("cy")) - ry + node.dy,
                width=rx * 2,
                height=ry * 2,
            )

        elif tag == "circle":
            circle_value = ""
            circle_font_style = ""
            if index + 1 < len(flattened):
                next_node = flattened[index + 1]
                next_element = next_node.element
                if (
                    local_name(next_element.tag) == "text"
                    and "num" in next_element.attrib.get("class", "").split()
                    and abs((get_number(next_element.attrib.get("x")) + next_node.dx) - (get_number(element.attrib.get("cx")) + node.dx)) < 1.0
                    and abs((get_number(next_element.attrib.get("y")) + next_node.dy) - (get_number(element.attrib.get("cy")) + node.dy + 4.0)) < 6.0
                ):
                    circle_value = "".join(next_element.itertext()).strip()
                    circle_font_style = ";fontColor=#ffffff;fontSize=12;fontStyle=1;"
                    index += 1

            circle = ET.SubElement(
                mxroot,
                "mxCell",
                {
                    "id": next_id("circle"),
                    "value": circle_value,
                    "style": vertex_style(style, ellipse=True, shadow=node.shadow) + circle_font_style,
                    "vertex": "1",
                    "parent": "1",
                },
            )
            radius = get_number(element.attrib.get("r"))
            add_geometry(
                circle,
                x=get_number(element.attrib.get("cx")) - radius + node.dx,
                y=get_number(element.attrib.get("cy")) - radius + node.dy,
                width=radius * 2,
                height=radius * 2,
            )

        elif tag == "text":
            if "num" in element.attrib.get("class", "").split():
                index += 1
                continue

            text_value = "".join(element.itertext()).strip()
            font_size, _, _ = parse_font(style)
            text_width, text_height = estimate_text_box(text_value, font_size)
            x = get_number(element.attrib.get("x")) + node.dx
            y = get_number(element.attrib.get("y")) + node.dy
            anchor = style.get("text-anchor", "start")
            if anchor == "middle":
                left = x - text_width / 2
            elif anchor == "end":
                left = x - text_width
            else:
                left = x
            top = y - font_size

            text_cell = ET.SubElement(
                mxroot,
                "mxCell",
                {
                    "id": next_id("text"),
                    "value": text_value,
                    "style": text_style(style),
                    "vertex": "1",
                    "parent": "1",
                },
            )
            add_geometry(text_cell, x=left, y=top, width=text_width, height=text_height)

        elif tag == "path":
            points = path_points(element.attrib["d"])
            if len(points) < 2:
                index += 1
                continue
            adjusted = [Point(point.x + node.dx, point.y + node.dy) for point in points]
            edge = ET.SubElement(
                mxroot,
                "mxCell",
                {
                    "id": next_id("edge"),
                    "value": "",
                    "style": edge_style(style),
                    "edge": "1",
                    "parent": "1",
                },
            )
            geometry = ET.SubElement(edge, "mxGeometry", {"relative": "1", "as": "geometry"})
            ET.SubElement(
                geometry,
                "mxPoint",
                {"x": fmt(adjusted[0].x), "y": fmt(adjusted[0].y), "as": "sourcePoint"},
            )
            ET.SubElement(
                geometry,
                "mxPoint",
                {"x": fmt(adjusted[-1].x), "y": fmt(adjusted[-1].y), "as": "targetPoint"},
            )
            if len(adjusted) > 2:
                array = ET.SubElement(geometry, "Array", {"as": "points"})
                for point in adjusted[1:-1]:
                    ET.SubElement(array, "mxPoint", {"x": fmt(point.x), "y": fmt(point.y)})

        index += 1

    ET.indent(mxfile)
    drawio_path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n', encoding="utf-8")
    tree = ET.ElementTree(mxfile)
    tree.write(drawio_path, encoding="unicode", xml_declaration=False)
    drawio_path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + drawio_path.read_text(encoding="utf-8"), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert an SVG diagram into native draw.io XML shapes.")
    parser.add_argument("input", nargs="?", default="docs/system-architecture.svg", help="Input SVG path")
    parser.add_argument("output", nargs="?", default="docs/system-architecture.drawio.xml", help="Output draw.io XML path")
    args = parser.parse_args()

    create_drawio(Path(args.input), Path(args.output))


if __name__ == "__main__":
    main()
