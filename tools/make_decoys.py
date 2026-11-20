#!/usr/bin/env python3
"""Builds the blank decoy files shipped in the app bundle.

Usage: python3 -I tools/make_decoys.py Resources/Decoys

Each file is the smallest document its app opens without complaint:
an empty sheet, a blank page, a deck with no slides, a blank PDF page.
Standard library only, so the output is reproducible.
"""
import sys
import zipfile
from pathlib import Path

STAMP = (2024, 1, 1, 9, 0, 0)

CT = "http://schemas.openxmlformats.org/package/2006/content-types"
REL = "http://schemas.openxmlformats.org/package/2006/relationships"
OFFICE_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


def write_zip(path: Path, parts: list[tuple[str, str]]) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, body in parts:
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, XML + body)


def content_types(overrides: dict[str, str]) -> str:
    rows = "".join(f'<Override PartName="{p}" ContentType="{t}"/>' for p, t in overrides.items())
    return (
        f'<Types xmlns="{CT}">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f"{rows}</Types>"
    )


def rels(items: list[tuple[str, str, str]]) -> str:
    rows = "".join(f'<Relationship Id="{i}" Type="{OFFICE_REL}/{t}" Target="{target}"/>' for i, t, target in items)
    return f'<Relationships xmlns="{REL}">{rows}</Relationships>'


def xlsx(path: Path) -> None:
    main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    write_zip(path, [
        ("[Content_Types].xml", content_types({
            "/xl/workbook.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
            "/xl/worksheets/sheet1.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
            "/xl/styles.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml",
        })),
        ("_rels/.rels", rels([("rId1", "officeDocument", "xl/workbook.xml")])),
        ("xl/workbook.xml",
         f'<workbook xmlns="{main}" xmlns:r="{OFFICE_REL}">'
         '<bookViews><workbookView/></bookViews>'
         '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'),
        ("xl/_rels/workbook.xml.rels", rels([
            ("rId1", "worksheet", "worksheets/sheet1.xml"),
            ("rId2", "styles", "styles.xml"),
        ])),
        ("xl/worksheets/sheet1.xml",
         f'<worksheet xmlns="{main}"><sheetViews><sheetView workbookViewId="0" tabSelected="1"/></sheetViews>'
         '<sheetFormatPr defaultRowHeight="16"/><sheetData/></worksheet>'),
        ("xl/styles.xml",
         f'<styleSheet xmlns="{main}">'
         '<fonts count="1"><font><sz val="12"/><name val="Aptos Narrow"/><family val="2"/></font></fonts>'
         '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
         '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
         '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
         '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
         '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
         '</styleSheet>'),
    ])


def docx(path: Path) -> None:
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    write_zip(path, [
        ("[Content_Types].xml", content_types({
            "/word/document.xml": "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
            "/word/settings.xml": "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml",
        })),
        ("_rels/.rels", rels([("rId1", "officeDocument", "word/document.xml")])),
        ("word/_rels/document.xml.rels", rels([("rId1", "settings", "settings.xml")])),
        # Without compatibilityMode 15, Word shows "Compatibility Mode" in the title bar.
        ("word/settings.xml",
         f'<w:settings xmlns:w="{w}"><w:compat>'
         '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/>'
         '</w:compat></w:settings>'),
        ("word/document.xml",
         f'<w:document xmlns:w="{w}"><w:body><w:p/>'
         '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
         '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
         '</w:sectPr></w:body></w:document>'),
    ])


def pptx(path: Path) -> None:
    a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    p = "http://schemas.openxmlformats.org/presentationml/2006/main"
    ns = f'xmlns:a="{a}" xmlns:r="{OFFICE_REL}" xmlns:p="{p}"'
    empty_tree = (
        '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree>'
    )
    colors = [("dk2", "0E2841"), ("lt2", "E8E8E8"), ("accent1", "156082"), ("accent2", "E97132"),
              ("accent3", "196B24"), ("accent4", "0F9ED5"), ("accent5", "A02B93"), ("accent6", "4EA72E"),
              ("hlink", "467886"), ("folHlink", "96607D")]
    scheme = ('<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
              '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
              + "".join(f'<a:{n}><a:srgbClr val="{v}"/></a:{n}>' for n, v in colors))
    solid = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    line = f'<a:ln w="12700">{solid}</a:ln>'
    theme = (
        f'<a:theme xmlns:a="{a}" name="Office Theme"><a:themeElements>'
        f'<a:clrScheme name="Office">{scheme}</a:clrScheme>'
        '<a:fontScheme name="Office">'
        '<a:majorFont><a:latin typeface="Aptos Display"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
        '<a:minorFont><a:latin typeface="Aptos"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
        '</a:fontScheme>'
        '<a:fmtScheme name="Office">'
        f'<a:fillStyleLst>{solid * 3}</a:fillStyleLst>'
        f'<a:lnStyleLst>{line * 3}</a:lnStyleLst>'
        f'<a:effectStyleLst>{"<a:effectStyle><a:effectLst/></a:effectStyle>" * 3}</a:effectStyleLst>'
        f'<a:bgFillStyleLst>{solid * 3}</a:bgFillStyleLst>'
        '</a:fmtScheme></a:themeElements></a:theme>'
    )
    clr_map = ('<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" '
               'accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>')
    write_zip(path, [
        ("[Content_Types].xml", content_types({
            "/ppt/presentation.xml": "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
            "/ppt/slideMasters/slideMaster1.xml": "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml",
            "/ppt/slideLayouts/slideLayout1.xml": "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml",
            "/ppt/theme/theme1.xml": "application/vnd.openxmlformats-officedocument.theme+xml",
        })),
        ("_rels/.rels", rels([("rId1", "officeDocument", "ppt/presentation.xml")])),
        ("ppt/presentation.xml",
         f'<p:presentation {ns} saveSubsetFonts="1">'
         '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
         '<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/>'
         '</p:presentation>'),
        ("ppt/_rels/presentation.xml.rels", rels([
            ("rId1", "slideMaster", "slideMasters/slideMaster1.xml"),
            ("rId2", "theme", "theme/theme1.xml"),
        ])),
        ("ppt/slideMasters/slideMaster1.xml",
         f'<p:sldMaster {ns}><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
         f'{empty_tree}</p:cSld>{clr_map}'
         '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
         '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>'),
        ("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([
            ("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", "theme", "../theme/theme1.xml"),
        ])),
        ("ppt/slideLayouts/slideLayout1.xml",
         f'<p:sldLayout {ns} type="blank" preserve="1"><p:cSld name="Blank">{empty_tree}</p:cSld>'
         '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>'),
        ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([
            ("rId1", "slideMaster", "../slideMasters/slideMaster1.xml"),
        ])),
        ("ppt/theme/theme1.xml", theme),
    ])


def pdf(path: Path) -> None:
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 4 0 R >>",
        "<< /Length 0 >>\nstream\n\nendstream",
    ]
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{body}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    path.write_bytes(bytes(out))


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "Resources/Decoys")
    out.mkdir(parents=True, exist_ok=True)
    xlsx(out / "empty.xlsx")
    docx(out / "empty.docx")
    pptx(out / "empty.pptx")
    pdf(out / "empty.pdf")
    for f in sorted(out.iterdir()):
        print(f"{f.name}: {f.stat().st_size} bytes")


if __name__ == "__main__":
    main()
