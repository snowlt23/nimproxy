
import asynchttpserver, asyncdispatch

var server = newAsyncHttpServer()
proc handler(req: Request) {.async.} =
  echo req.url.path
  echo req.url.query
  if req.url.path == "/":
    await req.respond(Http200, readFile("public/test.html"))
  elif req.url.path == "/test.js":
    await req.respond(Http200, readFile("public/test.js"))
  elif req.url.path == "/test2.js":
    await req.respond(Http200, readFile("public/test2.js"))
  else:
    await req.respond(Http200, "couldn't path")
waitfor server.serve(Port(5000), handler)
