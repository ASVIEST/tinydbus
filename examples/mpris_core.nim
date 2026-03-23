## MPRIS2 media player control example using tinydbus.

import pkg/tinydbus
import std/strutils

const
  RootIface* = "org.mpris.MediaPlayer2"
  MprisPrefix* = RootIface & "."
  MprisPath* = ObjectPath("/org/mpris/MediaPlayer2")
  PlayerIface* = MprisPrefix & "Player"
  PropsIface = "org.freedesktop.DBus.Properties"

type Player* = object
  conn: BusConnection
  busName: string

proc listPlayers*(conn: var BusConnection): seq[string] =
  let msg = initMethodCallMsg(
    "org.freedesktop.DBus", "/org/freedesktop/DBus",
    "org.freedesktop.DBus", "ListNames")
  let reply = conn.call(msg)
  var br = initBodyReader(reply.body, reply.signature)
  let endPos = br.readArrayBegin("s")
  while br.readArrayHasMore(endPos):
    let name = read[string](br)
    if name.startsWith(MprisPrefix):
      result.add name

proc playerName*(busName: string): string =
  result = busName
  result.removePrefix(MprisPrefix)

proc getProperty*[T](conn: var BusConnection, busName, iface, name: string): T =
  let msg = initMethodCallMsg(busName, $MprisPath, PropsIface, "Get")
  var body = initBodyBuilder()
  body.add iface
  body.add name
  msg.setBody(body)
  let reply = conn.call(msg)
  var br = initBodyReader(reply.body, reply.signature)
  discard br.readVariantSignature()
  read[T](br)

proc initPlayer*(conn: sink BusConnection, busName: string): Player =
  Player(conn: conn, busName: busName)

proc initPlayerShort*(conn: sink BusConnection, name: string): Player =
  initPlayer(conn, MprisPrefix & name)

proc getProperty*[T](p: var Player, iface, name: string): T =
  getProperty[T](p.conn, p.busName, iface, name)

proc getPropertyReply*(p: var Player, iface, name: string): Message =
  let msg = initMethodCallMsg(p.busName, $MprisPath, PropsIface, "Get")
  var body = initBodyBuilder()
  body.add iface
  body.add name
  msg.setBody(body)
  p.conn.call(msg)

proc setProperty*[T](p: var Player, iface, name: string, value: T) =
  let msg = initMethodCallMsg(p.busName, $MprisPath, PropsIface, "Set")
  var body = initBodyBuilder()
  body.add iface
  body.add name
  body.addVariant($sigChar(T)) do(b: var BodyBuilder):
    b.add value
  msg.setBody(body)
  discard p.conn.call(msg)

template playerCall(p: var Player, member: string, buildBody: untyped) =
  let msg = initMethodCallMsg(p.busName, $MprisPath, PlayerIface, member)
  block:
    var body {.inject.} = initBodyBuilder()
    buildBody
    msg.setBody(body)
  discard p.conn.call(msg)

template playerCall(p: var Player, member: string) =
  let msg = initMethodCallMsg(p.busName, $MprisPath, PlayerIface, member)
  discard p.conn.call(msg)

proc play*(p: var Player) = p.playerCall("Play")
proc pause*(p: var Player) = p.playerCall("Pause")
proc playPause*(p: var Player) = p.playerCall("PlayPause")
proc stop*(p: var Player) = p.playerCall("Stop")
proc next*(p: var Player) = p.playerCall("Next")
proc previous*(p: var Player) = p.playerCall("Previous")

proc seek*(p: var Player, offsetUs: int64) =
  p.playerCall("Seek"):
    body.add offsetUs

proc setPosition*(p: var Player, trackId: ObjectPath, positionUs: int64) =
  p.playerCall("SetPosition"):
    body.add trackId
    body.add positionUs

proc openUri*(p: var Player, uri: string) =
  p.playerCall("OpenUri"):
    body.add uri

type Metadata* = object
  trackId*: ObjectPath
  title*, album*, artUrl*, url*: string
  artists*, albumArtists*, genre*: seq[string]
  length*: int64
  trackNumber*, discNumber*: int32

proc readStringArray(br: var BodyReader): seq[string] =
  result = @[]
  let endPos = br.readArrayBegin("s")
  while br.readArrayHasMore(endPos):
    result.add read[string](br)

proc metadata*(p: var Player): Metadata =
  result = Metadata()
  let reply = p.getPropertyReply(PlayerIface, "Metadata")
  var br = initBodyReader(reply.body, reply.signature)
  discard br.readVariantSignature()
  let dictEnd = br.readArrayBegin("{sv}")
  while br.readArrayHasMore(dictEnd):
    br.readStructBegin()
    let key = read[string](br)
    let varSig = br.readVariantSignature()
    case key
    of "mpris:trackid":
      result.trackId = read[ObjectPath](br)
    of "xesam:title":
      result.title = read[string](br)
    of "xesam:album":
      result.album = read[string](br)
    of "xesam:artist":
      result.artists = br.readStringArray()
    of "xesam:albumArtist":
      result.albumArtists = br.readStringArray()
    of "xesam:genre":
      result.genre = br.readStringArray()
    of "xesam:url":
      result.url = read[string](br)
    of "mpris:artUrl":
      result.artUrl = read[string](br)
    of "mpris:length":
      result.length = read[int64](br)
    of "xesam:trackNumber":
      result.trackNumber = read[int32](br)
    of "xesam:discNumber":
      result.discNumber = read[int32](br)
    else:
      br.skip(varSig)
    br.readStructEnd()

when isMainModule:
  import std/parseopt

  const Usage = """
mpris_core [--player=NAME] <command> [args]

Commands:
  list                  List available players
  status                Show player status and current track
  play / pause / toggle / stop / next / prev
  volume [VALUE]        Get or set volume [0.0, 1.0]
  pos [SECONDS]         Get or set position in seconds
  seek <SECONDS>        Seek by offset in seconds
  open <URI>            Open a URI

Options:
  -p, --player=NAME     Player short name (default: first available)"""

  proc findPlayer(conn: sink BusConnection, name: string): Player =
    var conn = conn
    if name.len > 0:
      return initPlayerShort(ensureMove conn, name)
    let players = listPlayers(conn)
    if players.len == 0:
      echo "No MPRIS players found."
      quit(1)
    initPlayer(ensureMove conn, players[0])

  proc cli() =
    var (conn, _) = openSessionBus()

    var playerOpt = ""
    var cmd = ""
    var cmdArg = ""

    var p = initOptParser(shortNoVal = {'h'}, longNoVal = @["help"])
    for kind, key, val in p.getopt():
      if cmd.len > 0:
        case kind
        of cmdArgument:
          cmdArg = key
        of cmdShortOption, cmdLongOption:
          cmdArg = "-" & key & val
        of cmdEnd: discard
      else:
        case kind
        of cmdLongOption, cmdShortOption:
          case key
          of "player", "p":
            playerOpt = val
          of "help", "h":
            echo Usage
            quit(0)
          else:
            echo "Unknown option: ", key
            quit(1)
        of cmdArgument:
          cmd = key
        of cmdEnd: discard

    if cmd.len == 0:
      echo Usage
      quit(0)

    if cmd == "list":
      let players = listPlayers(conn)
      if players.len == 0:
        echo "No MPRIS players found."
      else:
        # This loop must reuse `conn`, so it can't build owning `Player` values.
        # If you want many objects to hide/share the same connection internally,
        # store `ref BusConnection` in them instead of `BusConnection` by value.
        for name in players:
          echo playerName(name),
            " (", getProperty[string](conn, name, RootIface, "Identity"), ")"
      return

    var pl = findPlayer(ensureMove conn, playerOpt)

    case cmd
    of "status":
      echo "Player:   ", getProperty[string](pl, RootIface, "Identity")
      echo "Status:   ", getProperty[string](pl, PlayerIface, "PlaybackStatus")
      echo "Volume:   ", getProperty[float64](pl, PlayerIface, "Volume")
      echo "Position: ",
        getProperty[int64](pl, PlayerIface, "Position").float64 / 1_000_000, " s"
      let meta = pl.metadata()
      if meta.title.len > 0:
        echo "Track:    ",
          "{",
          meta.artists.join(", "),
          "} ",
          meta.title,
          (if meta.album.len > 0: " [" & meta.album & "]" else: "")
    of "play": pl.play()
    of "pause": pl.pause()
    of "toggle": pl.playPause()
    of "stop": pl.stop()
    of "next": pl.next()
    of "prev": pl.previous()
    of "volume":
      if cmdArg.len > 0:
        pl.setProperty(PlayerIface, "Volume", parseFloat(cmdArg))
      else:
        echo getProperty[float64](pl, PlayerIface, "Volume")
    of "pos":
      if cmdArg.len > 0:
        let meta = pl.metadata()
        pl.setPosition(meta.trackId, int64(parseFloat(cmdArg) * 1_000_000))
      else:
        echo getProperty[int64](pl, PlayerIface, "Position").float64 / 1_000_000, " s"
    of "seek":
      if cmdArg.len == 0:
        echo "Usage: mpris_core seek <seconds>"
        quit(1)
      pl.seek(int64(parseFloat(cmdArg) * 1_000_000))
    of "open":
      if cmdArg.len == 0:
        echo "Usage: mpris_core open <uri>"
        quit(1)
      pl.openUri(cmdArg)
    else:
      echo "Unknown command: ", cmd
      echo Usage
      quit(1)

  cli()
