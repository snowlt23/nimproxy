
import asynchttpserver, asyncdispatch
import httpclient
import strutils
import parsecfg
import options
import os
import nre

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

let rootpathreg = re""""\s*/.*""""
proc rewriteRootPath*(src: string, basepath: string): string =
  src.replace(rootpathreg) do (match: string) -> string:
    "/" & basepath & match.replace("\"")

var server = newAsyncHttpServer()
proc handler(req: Request) {.async.} =
  let firstpath = req.url.path.split("/")[1]
  let restpath = req.url.path.split("/")[2..^1]
  let proxypath = findRedirectPathFromConfig(firstpath)
  if proxypath.isSome():
    var client = newHttpClient()
    let path = proxypath.get & "/" & restpath.join("/")
    debugEcho "PROXY TO: ", path

    let resp = client.request(path, req.reqMethod, req.body)
    let respbody = if resp.body.find("<html") != -1:
                     resp.body.rewriteRootPath(firstpath)
                   else:
                     resp.body
    await req.respond(resp.code, respbody)
  else:
    await req.respond(Http404, "couldn't find path")
waitfor server.serve(getServerPort(), handler)
