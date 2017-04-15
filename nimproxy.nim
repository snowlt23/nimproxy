
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
    debugEcho "PROXY TO: ", path

    var reqheaders = req.headers
    headers["path"] = "/" & restpath.join("/")
    let resp = client.request(path, req.reqMethod, req.body, )
    var respheaders = resp.headers
    if not defined(release):
      for key, value in respheaders.pairs:
        echo key, ":", value

    await req.respond(resp.code, resp.body, respheaders)
  else:
    await req.respond(Http404, "couldn't find path")
waitfor server.serve(getServerPort(), handler)
