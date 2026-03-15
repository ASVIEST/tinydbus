## check that validation_layer.nim satisfy D-Bus specification.

import std/[os, strutils, parseutils]
import pkg/unittest2

const validationLayerPath = currentSourcePath().parentDir / ".." / "src" / "validation_layer.nim"

type
  QuoteKind = enum
    qkExact ## spec: "..." — spec substring
    qkTable ## spec-table: "k1" "k2" ... — each keyword must appear on page

  SpecQuote = object
    lineNum: int
    case kind: QuoteKind
    of qkExact: text: string
    of qkTable: keywords: seq[string]

proc stripTags(html: string): string {.inline.} =
  result = newStringOfCap(html.len)
  var inTag = false
  for c in html:
    case c
    of '<': inTag = true
    of '>': inTag = false; result.add ' '
    elif not inTag: result.add c
    else: discard

proc normalizeWhitespace(s: string): string = s.splitWhitespace().join(" ")

proc cleanHtml*(html: string): string =
  html
  .stripTags()
  .multiReplace(
    ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
    ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
    ("\xE2\x80\x9C", "\""), ("\xE2\x80\x9D", "\""),
    ("\xE2\x80\x98", "'"), ("\xE2\x80\x99", "'"),
    ("\xC2\xA0", " "))
  .normalizeWhitespace()
  .multiReplace((" .", "."), (" ,", ","), (" ;", ";"), (" :", ":"))

proc extractQuoted(line: string): seq[string] =
  let parts = line.split('"')
  for i in countup(1, parts.high, 2):
    result.add parts[i]

proc parseSpecQuotes(source: string): seq[SpecQuote] =
  result = @[]
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    var pos = 0

    if (pos = stripped.skip("# spec-table:"); pos) > 0:
      result.add SpecQuote(
        lineNum: i + 1, kind: qkTable, keywords: extractQuoted(stripped))
    elif (pos = stripped.skip("# spec: \""); pos) > 0:
      var fullText = stripped[pos..^1]
      while i + 1 < lines.len:
        pos = lines[i + 1].strip().skip("#  ")
        if pos == 0: break # '#  ' not found
        fullText &= " " & lines[i + 1].strip()[pos..^1]
        inc i
      fullText.removeSuffix('"')
      result.add SpecQuote(lineNum: i + 1, kind: qkExact, text: fullText)

    inc i

template specQuoteSuite*(suiteName: static[string]; html: untyped) =
  suite suiteName:
    let page = cleanHtml(html)
    let quotes = parseSpecQuotes(readFile(validationLayerPath))

    for q in quotes:
      case q.kind
      of qkExact:
        test "line " & $q.lineNum & ": " & q.text:
          for part in q.text.split("..."):
            let cleaned = normalizeWhitespace(part.strip())
            if cleaned.len > 0:
              check page.find(cleaned) >= 0

      of qkTable:
        test "line " & $q.lineNum & " (table): " & q.keywords.join(", "):
          for kw in q.keywords:
            check page.find(kw) >= 0
