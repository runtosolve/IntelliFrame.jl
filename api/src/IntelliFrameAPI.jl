module IntelliFrameAPI

using CSV, DataFrames, IntelliFrame, PurlinLine, StructTypes, UUIDs

export RunIntelliFrame, IntelliFrameResult, calculate

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

function calculate(data::RunIntelliFrame)::IntelliFrameResult
  purlin_types = existing_purlin_types(data.purlin_types, DATABASES.intelli_frame_data)
  model = IntelliFrame.UI.existing_roof_UI_mapper(
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

  if data.analysis_type == "retrofit"
    model = IntelliFrame.UI.retrofit_UI_mapper(
      model,
      DATABASES.intelli_frame_data,
      data.intelli_frame_type,
      data.deck_type,
      DATABASES.new_deck_data,
      data.deck_type,
      DATABASES.existing_deck_data,
      INTELLI_FRAME_MATERIAL,
      data.loading_direction,
    )
  end

  output = IntelliFrameResult()
  output.applied_pressure = model.applied_pressure
  output.failure_limit_state = model.failure_limit_state
  output.failure_location = model.failure_location
  output.input_z = model.model.inputs.z
  output.output_v = model.model.outputs.v
  output.report_id = data.generate_report ? string(uuid4()) : ""
  return output
end

end
