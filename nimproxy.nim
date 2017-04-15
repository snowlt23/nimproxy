
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

proc debugHeaders*(headers: HttpHeaders) =
  if not defined(release):
    for key, value in headers:
      echo key, ":", value

let rootpathhtmlreg = re"""(src|href|action)\s*=\s*"\s*(/.*?)""""
let rootpathcssreg = re"""url\(\s*"*(/.*?)"*\)"""
proc rewriteHTMLRootPath*(src: string, basepath: string): string =
  src.replace(rootpathhtmlreg, "$#=\"/$#$#\"" % ["$1", basepath, "$2"])
proc rewriteCSSRootPath*(src: string, basepath: string): string =
  src.replace(rootpathcssreg, "url(/$#$#)" % [basepath, "$1"])
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

    var reqheaders = req.headers
    reqheaders.del("host")
    reqheaders.del("accept-encoding")
    debugHeaders reqheaders
    var resp: Response
    try:
      resp = client.request(path, req.reqMethod, req.body, reqheaders)
    except:
      echo getCurrentExceptionMsg()
      return
    debugEcho resp.body
    let respbody = if ext == ".html" or resp.body.find("<html") != -1:
                     resp.body.rewriteHTMLRootPath(firstpath)
                   elif ext == ".css":
                     resp.body.rewriteCSSRootPath(firstpath)
                   else:
                     resp.body
    var respheaders = resp.headers
    debugHeaders respheaders
    await req.respond(resp.code, respbody, respheaders)
  else:
    await req.respond(Http404, "couldn't find path")
waitfor server.serve(getServerPort(), handler)
