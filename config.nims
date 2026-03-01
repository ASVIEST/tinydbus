import std/[os, strutils]

task examples, "Build all examples":
  for f in listFiles("examples"):
    if f.endsWith(".nim"):
      selfExec "c " & f
