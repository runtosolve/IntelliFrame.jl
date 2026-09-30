using CSV, DataFrames, IntelliFrame, Plots




purlin_data = CSV.read("database/Purlins.csv",
DataFrame);

intelli_frame_data = CSV.read("database/IntelliFrameRF.csv",
DataFrame);

existing_deck_data = CSV.read("database/Existing_Deck.csv",
DataFrame);

new_deck_data = CSV.read("database/New_Deck.csv",
DataFrame);


purlin_spans = (25.0)

purlin_type_1 = "C6x2.5 1345"
purlin_type_2 = "none"

purlin_size_span_assignment = (1)

purlin_laps = ()

purlin_spacing = 4.0

frame_flange_width = 10.0 

purlin_frame_connection = "Clip-mounted"

roof_slope = 1/12

existing_deck_type = "PBR 22 gauge"

span_segments = UI.define_span_segments(purlin_spans, purlin_laps, purlin_size_span_assignment)

purlin_line = UI.existing_roof_UI_mapper(purlin_spans, purlin_laps, purlin_spacing, roof_slope, purlin_data, existing_deck_type, existing_deck_data, frame_flange_width, purlin_frame_connection, (purlin_type_1, purlin_type_2), purlin_size_span_assignment, "gravity");
	
plot(purlin_line.model.inputs.z, purlin_line.model.outputs.u)
plot(purlin_line.model.inputs.z, purlin_line.model.outputs.v)
plot(purlin_line.model.inputs.z, purlin_line.model.outputs.ϕ)

plot(purlin_line.model.inputs.z, purlin_line.internal_forces.Mxx, markershape = :o)
plot(purlin_line.model.inputs.z, purlin_line.internal_forces.Myy, markershape = :o)
plot(purlin_line.model.inputs.z, purlin_line.internal_forces.T, markershape = :o)
plot(purlin_line.model.inputs.z, purlin_line.internal_forces.Vyy, markershape = :o)

purlin_line.failure_location
purlin_line.failure_limit_state
purlin_line.applied_pressure*1000*144



intelli_frame_type = "1.75x4.5x2.125 16g"

hugger_window_dimensions = (2.5, 1.625)  #(width, height) in inches

new_deck_type = "PBR 22 gauge"


intelli_frame_material_properties = [(29500.0, 0.30, 55.0, 70.0)]  #E, ν, Fy, Fu

intelli_frame_purlin_line = UI.retrofit_UI_mapper(purlin_line, intelli_frame_data, intelli_frame_type, new_deck_type, new_deck_data, existing_deck_type, existing_deck_data, intelli_frame_material_properties, "gravity");


intelli_frame_purlin_line.applied_pressure*1000*144