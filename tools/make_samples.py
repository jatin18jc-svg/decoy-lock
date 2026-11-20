#!/usr/bin/env python3
"""Makes sample files with visible content for hand testing.

Usage: python3 -I tools/make_samples.py samples

Writes a locked-to-be copy and an untouched copy of each type, so they can sit
side by side in Finder. Standard library only.
"""
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_decoys import STAMP, XML, OFFICE_REL, content_types, rels, write_zip  # noqa: E402

ROWS = [("Rent", 1450, 1450, 1450), ("Food", 320, 295, 340), ("Savings", 600, 650, 700)]


def xlsx(path: Path) -> None:
    main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

    def cell(ref, value):
        if isinstance(value, str):
            return f'<c r="{ref}" t="inlineStr"><is><t>{value}</t></is></c>'
        return f'<c r="{ref}"><v>{value}</v></c>'

    rows = ['<row r="1">' + cell("A1", "Budget") + cell("B1", "Jan") + cell("C1", "Feb") + cell("D1", "Mar") + "</row>"]
    for i, (name, *vals) in enumerate(ROWS, start=2):
        rows.append(f'<row r="{i}">' + cell(f"A{i}", name) + "".join(cell(f"{c}{i}", v) for c, v in zip("BCD", vals)) + "</row>")
    write_zip(path, [
        ("[Content_Types].xml", content_types({
            "/xl/workbook.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
            "/xl/worksheets/sheet1.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
        })),
        ("_rels/.rels", rels([("rId1", "officeDocument", "xl/workbook.xml")])),
        ("xl/workbook.xml", f'<workbook xmlns="{main}" xmlns:r="{OFFICE_REL}"><sheets><sheet name="Budget" sheetId="1" r:id="rId1"/></sheets></workbook>'),
        ("xl/_rels/workbook.xml.rels", rels([("rId1", "worksheet", "worksheets/sheet1.xml")])),
        ("xl/worksheets/sheet1.xml", f'<worksheet xmlns="{main}"><sheetData>{"".join(rows)}</sheetData></worksheet>'),
    ])


def docx(path: Path) -> None:
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    paras = ["Private notes", "The spare key is under the blue pot.", "Call the bank about the savings account on Monday."]
    body = "".join(f"<w:p><w:r><w:t>{p}</w:t></w:r></w:p>" for p in paras)
    write_zip(path, [
        ("[Content_Types].xml", content_types({
            "/word/document.xml": "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
            "/word/settings.xml": "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml",
        })),
        ("_rels/.rels", rels([("rId1", "officeDocument", "word/document.xml")])),
        ("word/_rels/document.xml.rels", rels([("rId1", "settings", "settings.xml")])),
        ("word/settings.xml",
         f'<w:settings xmlns:w="{w}"><w:compat><w:compatSetting w:name="compatibilityMode" '
         'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'),
        ("word/document.xml", f'<w:document xmlns:w="{w}"><w:body>{body}</w:body></w:document>'),
    ])


def pptx(path: Path, blank: Path) -> None:
    """The blank deck from make_decoys plus one slide with a title."""
    a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    p = "http://schemas.openxmlformats.org/presentationml/2006/main"
    slide = (
        f'<p:sld xmlns:a="{a}" xmlns:r="{OFFICE_REL}" xmlns:p="{p}"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="914400" y="2286000"/><a:ext cx="10363200" cy="1524000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="4400"/><a:t>Surprise party plan</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'
    )
    with zipfile.ZipFile(blank) as src:
        parts = {n: src.read(n).decode() for n in src.namelist()}
    parts["[Content_Types].xml"] = parts["[Content_Types].xml"].replace(
        "</Types>",
        '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>')
    parts["ppt/presentation.xml"] = parts["ppt/presentation.xml"].replace(
        "</p:sldMasterIdLst>", '</p:sldMasterIdLst><p:sldIdLst><p:sldId id="256" r:id="rId3"/></p:sldIdLst>')
    parts["ppt/_rels/presentation.xml.rels"] = parts["ppt/_rels/presentation.xml.rels"].replace(
        "</Relationships>", f'<Relationship Id="rId3" Type="{OFFICE_REL}/slide" Target="slides/slide1.xml"/></Relationships>')
    parts["ppt/slides/slide1.xml"] = XML + slide
    parts["ppt/slides/_rels/slide1.xml.rels"] = XML + rels([("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml")])
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as out:
        for name, body in parts.items():
            out.writestr(zipfile.ZipInfo(name, STAMP), body)


def pdf(path: Path) -> None:
    text = b"BT /F1 28 Tf 72 700 Td (Account numbers) Tj 0 -40 Td /F1 16 Tf (Savings: 0000 1111 2222) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        b"<< /Length " + str(len(text)).encode() + b" >>\nstream\n" + text + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    path.write_bytes(bytes(out))


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "samples")
    out.mkdir(parents=True, exist_ok=True)
    blank = out / ".blank.pptx"
    from make_decoys import pptx as blank_pptx
    blank_pptx(blank)
    for prefix in ("Lock me", "Leave me"):
        xlsx(out / f"{prefix} - Budget.xlsx")
        docx(out / f"{prefix} - Notes.docx")
        pptx(out / f"{prefix} - Plan.pptx", blank)
        pdf(out / f"{prefix} - Accounts.pdf")
    blank.unlink()
    for f in sorted(out.iterdir()):
        print(f.name)


if __name__ == "__main__":
    main()
