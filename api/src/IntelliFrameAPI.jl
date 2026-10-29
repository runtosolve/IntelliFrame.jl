module IntelliFrameAPI

using CSV, DataFrames, Dates, IntelliFrame, JSON3, PurlinLine, StructTypes, UUIDs

export RunIntelliFrame, IntelliFrameResult, calculate, export_report

const DEFAULT_EXISTING_PURLIN = "Z8x2.5 060"
const INTELLI_FRAME_MATERIAL = [(29500.0, 0.30, 55.0, 70.0)]

mutable struct RunIntelliFrame
  purlin_types::Vector{String}
  purlin_spans::Vector{Float64}
  purlin_size_span_assignment::Vector{Int}
  purlin_laps::Vector{Float64}
  purlin_spacing::Float64
  frame_flange_width::Float64
  roof_slope::Float64
  deck_type::String
  loading_direction::String
  generate_report::Bool
  intelli_frame_type::String
  analysis_type::String
  purlin_frame_connection::String

  RunIntelliFrame() = new()
end

mutable struct IntelliFrameResult
  applied_pressure::Float64
  failure_limit_state::String
  failure_location::Float64
  input_z::Vector{Float64}
  output_v::Vector{Float64}
  report_id::String

  IntelliFrameResult() = new()
end

StructTypes.StructType(::Type{RunIntelliFrame}) = StructTypes.Mutable()
StructTypes.StructType(::Type{IntelliFrameResult}) = StructTypes.Mutable()

function with_purlin_decks(deck_data)
  purlin_deck = CSV.read(joinpath(pkgdir(PurlinLine), "database", "Existing_Deck.csv"), DataFrame)
  known = Set(String.(deck_data.deck_name))
  extra = filter(row -> !(String(row.deck_name) in known), purlin_deck)
  return vcat(deck_data, extra)
end

function load_section_databases()
  databases = IntelliFrame.UI.load_databases()
  return (
    purlin_data = databases.purlin_data,
    intelli_frame_data = databases.intelli_frame_data,
    existing_deck_data = with_purlin_decks(databases.existing_deck_data),
    new_deck_data = with_purlin_decks(databases.new_deck_data),
  )
end

const DATABASES = load_section_databases()

function existing_purlin_types(types, intelli_frame_data)
  section_names = String.(intelli_frame_data.section_name)
  if all(type -> type in section_names, types)
    return [DEFAULT_EXISTING_PURLIN]
  end
  return types
end

# The report pipeline (IntelliFrame_cFSM and IntelliFrame_Capacity); the retrofit analysis below uses it too.
include("report.jl")

# Finished analyses are kept per set of inputs, so running the same roof again answers at once.
const ANALYSIS_CACHE = Dict{String, IntelliFrameResult}()
const ANALYSIS_CACHE_LOCK = ReentrantLock()
const ANALYSIS_CACHE_SIZE = 200

analysis_key(data::RunIntelliFrame) = JSON3.write([isdefined(data, f) ? getfield(data, f) : nothing
                                                   for f in fieldnames(RunIntelliFrame) if f != :generate_report])

function calculate(data::RunIntelliFrame)::IntelliFrameResult
  key = analysis_key(data)
  result = lock(() -> get(ANALYSIS_CACHE, key, nothing), ANALYSIS_CACHE_LOCK)
  if result === nothing
    result = analyze(data)
    lock(ANALYSIS_CACHE_LOCK) do
      length(ANALYSIS_CACHE) >= ANALYSIS_CACHE_SIZE && empty!(ANALYSIS_CACHE)
      ANALYSIS_CACHE[key] = result
    end
  end

  output = IntelliFrameResult()
  output.applied_pressure = result.applied_pressure
  output.failure_limit_state = result.failure_limit_state
  output.failure_location = result.failure_location
  output.input_z = copy(result.input_z)
  output.output_v = copy(result.output_v)
  output.report_id = data.generate_report ? string(uuid4()) : ""
  return output
end

function analyze(data::RunIntelliFrame)::IntelliFrameResult
  purlin_types = existing_purlin_types(data.purlin_types, DATABASES.intelli_frame_data)
  existing_roof = (
    data.purlin_spans,
    data.purlin_laps,
    data.purlin_spacing,
    data.roof_slope,
    DATABASES.purlin_data,
    data.deck_type,
    DATABASES.existing_deck_data,
    data.frame_flange_width,
    data.purlin_frame_connection,
    purlin_types,
    data.purlin_size_span_assignment,
    data.loading_direction,
  )

  model = if data.analysis_type == "retrofit"
    # the retrofit needs only the existing line's inputs, not its capacity
    retrofit_analysis(data, IntelliFrame.UI.existing_roof_inputs(existing_roof...))
  else
    IntelliFrame.UI.existing_roof_UI_mapper(existing_roof...)
  end

  output = IntelliFrameResult()
  output.applied_pressure = model.applied_pressure
  output.failure_limit_state = model.failure_limit_state
  output.failure_location = model.failure_location
  output.input_z = model.model.inputs.z
  output.output_v = model.model.outputs.v
  output.report_id = ""
  return output
end

"""
The IntelliFrame retrofit as the report computes it (`IntelliFrame_Capacity.retrofit_define` and
`retrofit_capacity`): `IntelliFrame.UI.retrofit_UI_mapper` plus the governing (minimum) positive local
buckling moment of the combined section and the bare IntelliFrame cFSM study, so the analysis and the
report give the same allowable pressure. The cFSM study is memoized per profile and material.
"""
function retrofit_analysis(data::RunIntelliFrame, existing_inputs)
  capacity = IntelliFrame_cFSM.IntelliFrame_Capacity
  profile = findfirst(==(data.intelli_frame_type), DATABASES.intelli_frame_data.section_name)
  profile === nothing && throw(ArgumentError("IntelliFrame profile not in the database: $(data.intelli_frame_type)"))
  E, ν, Fy = INTELLI_FRAME_MATERIAL[1][1:3]
  cfsm = IntelliFrame_cFSM.governing_local_buckling_inputs(DATABASES.intelli_frame_data[profile, :], E, ν, Fy)
  line = (intelli_frame = data.intelli_frame_type, new_deck = data.deck_type, existing_deck = data.deck_type,
          if_mat = INTELLI_FRAME_MATERIAL)
  intelli_frame_line, _ = capacity.retrofit_define((inputs = existing_inputs,), line, DATABASES, cfsm)
  return capacity.retrofit_capacity(intelli_frame_line, data.loading_direction)
end

"""
    warmup_calculate()

Runs the default existing and retrofit analyses (the report warm-up's inputs) so the first
/intelliframe/base request after a start does not pay Julia's compilation time. Failures are
logged, never thrown.
"""
function warmup_calculate()
  try
    t = @elapsed for analysis_type in ("existing", "retrofit")
      body = merge(WARMUP_BODY, Dict{String,Any}("loading_direction" => "gravity", "generate_report" => false,
                                                 "analysis_type" => analysis_type))
      calculate(JSON3.read(JSON3.write(body), RunIntelliFrame))
    end
    @info "IntelliFrame analysis warmed up" seconds = round(t, digits = 1)
  catch error
    @error "IntelliFrame analysis warm-up failed" exception = (error, catch_backtrace())
  end
  return nothing
end

end
