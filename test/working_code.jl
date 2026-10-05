include("../src/IntelliFrame_cFSM.jl")

const INPUTS_PATH = joinpath(dirname(@__DIR__), "frontend_output", "inputs.json")
const OUTPUT_DIR  = joinpath(dirname(@__DIR__), "generate_report")


### Generate button
IntelliFrame_cFSM.run_all_calculations(INPUTS_PATH, OUTPUT_DIR)


### Export PDF button
IntelliFrame_cFSM.export_pdf(INPUTS_PATH, OUTPUT_DIR; root_dir = dirname(@__DIR__))
