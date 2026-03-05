import std/[os, strutils]

task examples, "Build all examples":
  for f in listFiles("examples"):
    if f.endsWith(".nim"):
      selfExec "c " & f

task test, "Run tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      selfExec "c -r " & f

