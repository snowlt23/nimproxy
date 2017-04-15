
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

let rootpathhtmlreg = re"""src\s*=\s*"\s*/.*?""""
let rootpathcssreg = re"url(\s*/.*?)"
proc rewriteHTMLRootPath*(src: string, basepath: string): string =
  src.replace(rootpathhtmlreg) do (match: string) -> string:
    "\"" & "/" & basepath & match.replace("\"") & "\""
proc rewriteCSSRootPath*(src: string, basepath: string): string =
  src.replace(rootpathcssreg) do (match: string) -> string:
    "url(/" & basepath & match.replace("url()")
var server = newAsyncHttpServer()
proc handler(req: Request) {.async.} =
  let
    splittedpath = req.url.path.split("/")
    firstpath = splittedpath[1]
    restpath = splittedpath[2..^1]
    lastpath = splittedpath[^1]
    ext = lastpath.splitFile().ext
  let proxypath = findRedirectPathFromConfig(firstpath)
  if proxypath.isSome():
    var client = newHttpClient()
    let path = proxypath.get & "/" & restpath.join("/")
    debugEcho "PROXY TO: ", path

    let resp = client.request(path, req.reqMethod, req.body)
    let respbody = if ext == ".html" or resp.body.find("<html") != -1:
                     resp.body.rewriteHTMLRootPath(firstpath)
                   elif ext == ".css":
                     resp.body.rewriteCSSRootPath(firstpath)
                   else:
                     resp.body
    await req.respond(resp.code, respbody)
  else:
    await req.respond(Http404, "couldn't find path")
waitfor server.serve(getServerPort(), handler)
