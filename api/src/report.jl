# PDF report export: the client report (generate_report/Report.typ) or the detailed report
# (generate_report/Report_detailed.typ) of IntelliFrame.jl, built from one request body.
#
# Each request gets its own temporary work folder laid out like the IntelliFrame.jl repository, so the
# templates' relative paths resolve unchanged:
#
#   <work>/frontend_output/inputs.json            request body + project block (the report reads it)
#   <work>/generate_report/Report.typ             template copied from the package
#   <work>/generate_report/Report_detailed.typ
#   <work>/generate_report/figures/IMETCO_Logo.png
#
# IntelliFrame_cFSM.run_all_calculations writes the JSON results and figures next to the templates, and
# IntelliFrame_cFSM.export_pdf compiles them with the Typst CLI (`typst` on PATH) using --root <work>.

# The report pipeline lives in IntelliFrame.jl/src but is not part of the IntelliFrame package module.
include(joinpath(pkgdir(IntelliFrame), "src", "IntelliFrame_cFSM.jl"))

const REPORT_SOURCE_DIR = joinpath(pkgdir(IntelliFrame), "generate_report")
const REPORT_TEMPLATES = ("Report.typ", "Report_detailed.typ")
const REPORT_LOGO = joinpath("figures", "IMETCO_Logo.png")

# Keys of the request body the analysis needs (the /intelliframe/base fields).
const REPORT_REQUIRED_KEYS = ("purlin_types", "purlin_spans", "purlin_size_span_assignment", "purlin_laps",
                              "purlin_spacing", "frame_flange_width", "roof_slope", "deck_type",
                              "intelli_frame_type", "purlin_frame_connection")

# Project block shown in the report header; blank or missing values print as an em dash.
const REPORT_PROJECT_KEYS = ("project_name", "project_location", "project_reference", "client_name")

# One report at a time: the pipeline is CPU-bound and CairoMakie is not meant to be driven from
# several tasks at once. Concurrent requests queue here.
const REPORT_LOCK = ReentrantLock()

_text(x) = (s = x === nothing ? "" : strip(string(x)); isempty(s) ? "—" : s)

"""
    report_inputs(body) -> Dict{String,Any}

The `inputs.json` the report templates read: the analysis fields of `body` plus the project block.
`report_type`, `analysis_type` and `generate_report` are request options, not report inputs.
"""
function report_inputs(body::AbstractDict)
    missing_keys = [k for k in REPORT_REQUIRED_KEYS if !haskey(body, k)]
    isempty(missing_keys) || throw(ArgumentError("missing field(s): " * join(missing_keys, ", ")))
    # names the databases do not list would otherwise fail deep in the analysis with an unreadable error
    known(name, column) = String(name) in String.(column)
    unknown_purlins = [p for p in body["purlin_types"] if !known(p, DATABASES.purlin_data.section_name)]
    isempty(unknown_purlins) ||
        throw(ArgumentError("purlin section(s) not in the IntelliFrame database: " * join(unknown_purlins, ", ")))
    known(body["intelli_frame_type"], DATABASES.intelli_frame_data.section_name) ||
        throw(ArgumentError("IntelliFrame profile not in the database: $(body["intelli_frame_type"])"))
    known(body["deck_type"], DATABASES.existing_deck_data.deck_name) ||
        throw(ArgumentError("deck type not in the database: $(body["deck_type"])"))
    inputs = Dict{String,Any}(k => body[k] for k in REPORT_REQUIRED_KEYS)
    inputs["loading_direction"] = get(body, "loading_direction", "gravity")
    for k in REPORT_PROJECT_KEYS
        inputs[k] = _text(get(body, k, nothing))
    end
    now = Dates.now()
    inputs["design_report_date"] = _text(get(body, "design_report_date", Dates.format(now, "mm/dd/yyyy")))
    inputs["time"] = _text(get(body, "time", Dates.format(now, "HH:MM:SS")))
    inputs["revision_no."] = _text(get(body, "revision_no", get(body, "revision_no.", "0")))
    return inputs
end

"Report file name for the download: the project name (or \"IntelliFrame_Report\"), plus \"_detailed\"."
function report_filename(inputs, detailed::Bool)
    name = inputs["project_name"] == "—" ? "IntelliFrame_Report" : inputs["project_name"]
    name = replace(name, r"[^A-Za-z0-9._ -]" => "_")
    return name * (detailed ? "_detailed" : "") * ".pdf"
end

"""
    export_report(body; detailed = false) -> (pdf::Vector{UInt8}, filename::String)

Runs the full report pipeline (bare-IntelliFrame cFSM study, then the existing and retrofit purlin
lines for gravity and uplift) for the request `body` and returns the compiled PDF bytes.
"""
function export_report(body::AbstractDict; detailed::Bool = false)
    inputs = report_inputs(body)
    lock(REPORT_LOCK) do
        mktempdir() do work
            input_dir = mkpath(joinpath(work, "frontend_output"))
            output_dir = joinpath(work, "generate_report")
            mkpath(joinpath(output_dir, "figures"))
            inputs_path = joinpath(input_dir, "inputs.json")
            open(io -> JSON3.write(io, inputs), inputs_path, "w")
            for f in REPORT_TEMPLATES
                cp(joinpath(REPORT_SOURCE_DIR, f), joinpath(output_dir, f))
            end
            cp(joinpath(REPORT_SOURCE_DIR, REPORT_LOGO), joinpath(output_dir, REPORT_LOGO))
            # files copied out of a read-only package depot keep their read-only mode; the pipeline only reads
            # them, but mktempdir must be able to delete them afterwards
            foreach(p -> chmod(p, 0o644), [joinpath(output_dir, f) for f in (REPORT_TEMPLATES..., REPORT_LOGO)])

            IntelliFrame_cFSM.run_all_calculations(inputs_path, output_dir)
            IntelliFrame_cFSM.export_pdf(inputs_path, output_dir; root_dir = work)
            pdf = read(joinpath(output_dir, detailed ? "Report_detailed.pdf" : "Report.pdf"))
            return pdf, report_filename(inputs, detailed)
        end
    end
end

"Default inputs (the frontend's defaults) for warming the report pipeline at server start."
const WARMUP_BODY = Dict{String,Any}(
    "purlin_types" => ["Z8x2.5 060"], "purlin_spans" => [16.0, 20.0], "purlin_size_span_assignment" => [1, 1],
    "purlin_laps" => [2.0, 2.0], "purlin_spacing" => 5.0, "frame_flange_width" => 6.0, "roof_slope" => 1 / 12,
    "deck_type" => "SSR Ultra-Dek 18 in. 24 ga", "intelli_frame_type" => "2x4.5x2.5 16g",
    "purlin_frame_connection" => "Clip-mounted", "project_name" => "Warm-up")

"""
    warmup_report()

Runs one report so the first real request does not pay Julia's compilation time (a cold report takes
roughly 3 minutes, a warm one a little over 1 minute). Failures are logged, never thrown.
"""
function warmup_report()
    try
        t = @elapsed export_report(WARMUP_BODY)
        @info "IntelliFrame report pipeline warmed up" seconds = round(t, digits = 1)
    catch error
        @error "IntelliFrame report warm-up failed" exception = (error, catch_backtrace())
    end
    return nothing
end
