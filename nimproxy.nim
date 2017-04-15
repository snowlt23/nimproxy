
import asynchttpserver, asyncdispatch
import httpclient
import strutils
import parsecfg
import options
import os

const configFilename* = getHomeDir() / ".nimproxy.cfg"
let serverconfig* = loadConfig(configFilename)

proc getServerPort*(): Port =
  let value = serverconfig.getSectionValue("Server", "port")
  if value != "":
    return Port(parseInt(value))
  else:
    return Port(80)

proc findRedirectPathFromConfig*(path: string): Option[string] =
  let value = serverconfig.getSectionValue("Routes", path)
  if value != "":
    return some(value)
  else:
    return none(string)

var server = newAsyncHttpServer()
proc handler(req: Request) {.async.} =
  let firstpath = req.url.path.split("/")[1]
  let restpath = req.url.path.split("/")[2..^1]
  let proxypath = findRedirectPathFromConfig(firstpath)
  if proxypath.isSome():
    var client = newHttpClient()
    let path = proxypath.get & "/" & restpath.join("/")
    var headers = req.headers
    headers["path"] = "/" & restpath.join("/")
    let resp = client.request(path, req.reqMethod, req.body, )
    echo "PROXY TO: ", path
    debugEcho resp.status
    debugEcho resp.body
    await req.respond(resp.code, resp.body, resp.headers)
  else:
    await req.respond(Http404, "couldn't find path")
waitfor server.serve(getServerPort(), handler)
