
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

proc debugHeaders*(headers: HttpHeaders, indent = 2) =
  if not defined(release):
    for key, value in headers:
      echo " ".repeat(indent), key, ":", value

let rootpathhtmlreg = re"""(src|href|action)\s*=\s*("|')\s*(/.*?)("|')"""
let rootpathcssreg = re"""url\(\s*"*(/.*?)"*\)"""
proc rewriteHTMLRootPath*(src: string, basepath: string): string =
  src.replace(rootpathhtmlreg, "$#=$#/$#$#$#" % ["$1", "$2", basepath, "$3", "$4"])
proc rewriteCSSRootPath*(src: string, basepath: string): string =
  src.replace(rootpathcssreg, "url(/$#$#)" % [basepath, "$1"])
var server = newAsyncHttpServer()
proc handler(req: Request) {.async.} =
  debugEcho "REQUEST PROXY: ", req.reqMethod, " ", req.url
  let
    splittedpath = req.url.path.split("/")
    firstpath = splittedpath[1]
    restpath = splittedpath[2..^1]
    lastpath = splittedpath[^1]
    ext = lastpath.splitFile().ext
  let proxypath = findRedirectPathFromConfig("/" & firstpath)
  if proxypath.isSome():
    var client = newHttpClient()
    let
      relpath = if restpath.join("/") == "":
                      ""
                    else:
                      "/" & restpath.join("/")
      query = if req.url.query == "":
                  ""
                else:
                  "?" & req.url.query
      path = proxypath.get & relpath & query
    debugEcho "PROXY TO: ", path # DEBUG:

    var reqheaders = req.headers
    reqheaders.del("host")
    reqheaders.del("accept-encoding")
    
    debugEcho "Request:" # DEBUG:
    debugHeaders reqheaders # DEBUG:

    var resp: Response
    try:
      resp = client.request(path, req.reqMethod, req.body, reqheaders)
    except:
      echo getCurrentExceptionMsg()
      return

    let respbody = if ext == ".html" or resp.body.find("<html") != -1:
                     resp.body.rewriteHTMLRootPath(firstpath)
                   elif ext == ".css":
                     resp.body.rewriteCSSRootPath(firstpath)
                   else:
                     resp.body
    var respheaders = resp.headers
    respheaders.del("content-length")
    respheaders.del("transfer-encoding")

    debugEcho "Response:" # DEBUG:
    debugHeaders respheaders # DEBUG:
    debugEcho "Response Body:" # DEBUG:
    debugEcho resp.body # DEBUG:

    await req.respond(resp.code, respbody, respheaders)
  else:
    await req.respond(Http404, "couldn't find path")
waitfor server.serve(getServerPort(), handler)
