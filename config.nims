import std/[os, strutils]

task examples, "Build all examples":
  for f in listFiles("examples"):
    if f.endsWith(".nim"):
      selfExec "c " & f

task test, "Run tests":
  for f in listFiles("tests"):
    let (_, name, ext) = splitFile(f)
    if ext == ".nim" and name.startsWith("test_") and not name.endsWith("_live"):
      selfExec "c -r " & f

task testLive, "Run tests fetching content from the internet":
  selfExec "c -r -d:ssl tests/test_spec_quote_live.nim"
