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

function cors_headers(request::HTTP.Request; content_type = "application/json")
    origin = HTTP.header(request, "Origin", "")
    allow_origin = origin in ALLOWED_ORIGINS ? origin : first(ALLOWED_ORIGINS)
    [
        "Access-Control-Allow-Origin" => allow_origin,
        "Access-Control-Allow-Headers" => "Content-Type, Authorization",
        "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
        "Access-Control-Expose-Headers" => "Content-Disposition",
        "Content-Type" => content_type,
    ]
end

json_response(request, status, body) = HTTP.Response(status, cors_headers(request), JSON3.write(body))

function handle_health(request::HTTP.Request)
    json_response(request, 200, (
        status = "ok",
        service = "IntelliFrameAPI",
        endpoints = ["/intelliframe/base", "/intelliframe/export-pdf"],
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

# POST body: the /intelliframe/base fields plus the report header (project_name, project_location,
# project_reference, client_name, revision_no, design_report_date, time) and report_type
# ("summary" -> Report.pdf, "detailed" -> Report_detailed.pdf). Runs all four cases (existing and
# retrofit, gravity and uplift) and returns the PDF bytes.
function handle_export_pdf(request::HTTP.Request)
    try
        body = JSON3.read(String(request.body), Dict{String,Any})
        detailed = get(body, "report_type", "summary") == "detailed"
        pdf, filename = IntelliFrameAPI.export_report(body; detailed)
        headers = [cors_headers(request; content_type = "application/pdf");
                   "Content-Disposition" => "inline; filename=\"$filename\""]
        HTTP.Response(200, headers, pdf)
    catch error
        @error "IntelliFrame report export failed" exception = (error, catch_backtrace())
        # ArgumentError = bad input (shown to the user as is); anything else is a server failure
        json_response(request, error isa ArgumentError ? 400 : 500, (
            error = "Report export failed",
            detail = error isa ArgumentError ? error.msg : sprint(showerror, error),
        ))
    end
end

const ROUTER = HTTP.Router()
HTTP.register!(ROUTER, "GET", "/", handle_health)
HTTP.register!(ROUTER, "OPTIONS", "/", handle_options)
HTTP.register!(ROUTER, "POST", "/intelliframe/base", handle_calculate)
HTTP.register!(ROUTER, "OPTIONS", "/intelliframe/base", handle_options)
HTTP.register!(ROUTER, "POST", "/intelliframe/export-pdf", handle_export_pdf)
HTTP.register!(ROUTER, "OPTIONS", "/intelliframe/export-pdf", handle_options)

@info "Starting IntelliFrameAPI" port = PORT threads = Threads.nthreads()
server = HTTP.serve!(ROUTER, "0.0.0.0", PORT)

# Compile the analysis and the report pipeline in the background so the first requests do not pay
# Julia's compilation time. A report requested meanwhile waits on the report lock.
# Set INTELLIFRAME_REPORT_WARMUP=false to skip.
if lowercase(get(ENV, "INTELLIFRAME_REPORT_WARMUP", "true")) != "false"
    Threads.@spawn begin
        IntelliFrameAPI.warmup_calculate()
        IntelliFrameAPI.warmup_report()
    end
end

wait(server)
