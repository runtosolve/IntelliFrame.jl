using HTTP
using JSON3
include(joinpath(@__DIR__, "IntelliFrameAPI.jl"))
using .IntelliFrameAPI

const PORT = parse(Int, get(ENV, "PORT", "8001"))
const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => get(ENV, "CORS_ORIGIN", "http://localhost:3000"),
    "Access-Control-Allow-Headers" => "Content-Type, Authorization",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
    "Content-Type" => "application/json",
]

json_response(status, body) = HTTP.Response(status, CORS_HEADERS, JSON3.write(body))

function handle_health(::HTTP.Request)
    json_response(200, (
        status = "ok",
        service = "IntelliFrameAPI",
        endpoint = "/intelliframe/base",
    ))
end

handle_options(::HTTP.Request) = HTTP.Response(204, CORS_HEADERS)

function handle_calculate(request::HTTP.Request)
    try
        input = JSON3.read(String(request.body), IntelliFrameAPI.RunIntelliFrame)
        json_response(200, IntelliFrameAPI.calculate(input))
    catch error
        @error "IntelliFrame calculation failed" exception = (error, catch_backtrace())
        json_response(400, (
            error = "Calculation failed",
            detail = sprint(showerror, error),
        ))
    end
end

const ROUTER = HTTP.Router()
HTTP.register!(ROUTER, "GET", "/", handle_health)
HTTP.register!(ROUTER, "OPTIONS", "/", handle_options)
HTTP.register!(ROUTER, "POST", "/intelliframe/base", handle_calculate)
HTTP.register!(ROUTER, "OPTIONS", "/intelliframe/base", handle_options)

@info "Starting IntelliFrameAPI" port = PORT
HTTP.serve(ROUTER, "0.0.0.0", PORT)
