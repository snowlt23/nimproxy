
import asynchttpserver, asyncdispatch

var server = newAsyncHttpServer()
proc handler(req: Request) {.async.} =
   await req.respond(Http200, "Hello Nim!!")
waitfor server.serve(Port(5000), handler)
