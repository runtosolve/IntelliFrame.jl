using HTTP
using JSON3
using IntelliFrameAPI

const PORT = parse(Int, get(ENV, "PORT", "8001"))
const ALLOWED_ORIGINS = [
    strip(origin)
    for origin in split(
        get(ENV, "CORS_ORIGIN", "http://localhost:3000,https://main.d6fk15p3rzwjj.amplifyapp.com"),
        ",",
    )
    if !isempty(strip(origin))
]

function cors_headers(request::HTTP.Request)
    origin = HTTP.header(request, "Origin", "")
    allow_origin = origin in ALLOWED_ORIGINS ? origin : first(ALLOWED_ORIGINS)
    [
        "Access-Control-Allow-Origin" => allow_origin,
        "Access-Control-Allow-Headers" => "Content-Type, Authorization",
        "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
        "Content-Type" => "application/json",
    ]
end

json_response(request, status, body) = HTTP.Response(status, cors_headers(request), JSON3.write(body))

function handle_health(request::HTTP.Request)
    json_response(request, 200, (
        status = "ok",
        service = "IntelliFrameAPI",
        endpoint = "/intelliframe/base",
    ))
end

handle_options(request::HTTP.Request) = HTTP.Response(204, cors_headers(request))

function handle_calculate(request::HTTP.Request)
    try
        input = JSON3.read(String(request.body), IntelliFrameAPI.RunIntelliFrame)
        json_response(request, 200, IntelliFrameAPI.calculate(input))
    catch error
        @error "IntelliFrame calculation failed" exception = (error, catch_backtrace())
        json_response(request, 400, (
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
