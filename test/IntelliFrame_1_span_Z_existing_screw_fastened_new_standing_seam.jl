# using CSV, DataFrames, IntelliFrame, Plots

using IntelliFrame, CSV, DataFrames, Plots


purlin_data = CSV.read("database/Purlins.csv",
DataFrame);

intelli_frame_data = CSV.read("database/IntelliFrameRF.csv",
DataFrame);

existing_deck_data = CSV.read("database/Existing_Deck.csv",
DataFrame);

new_deck_data = CSV.read("database/New_Deck.csv",
DataFrame);





purlin_spans = (25.0)

purlin_type_1 = "Z8x2.5 060"
purlin_type_2 = "none"

purlin_size_span_assignment = (1)

purlin_laps = ()

purlin_spacing = 5.0

frame_flange_width = 10.0 

purlin_frame_connection = "Clip-mounted"

roof_slope = 1/12

existing_deck_type = "PBR 22 gauge"

span_segments = UI.define_span_segments(purlin_spans, purlin_laps, purlin_size_span_assignment)

purlin_line = UI.existing_roof_UI_mapper(purlin_spans, purlin_laps, purlin_spacing, roof_slope, purlin_data, existing_deck_type, existing_deck_data, frame_flange_width, purlin_frame_connection, (purlin_type_1, purlin_type_2), purlin_size_span_assignment, "gravity");
	
# plot(purlin_line.model.inputs.z, purlin_line.model.outputs.u)
# plot(purlin_line.model.z, purlin_line.model.v)
# plot(purlin_line.model.z, purlin_line.model.ϕ)

# plot(purlin_line.model.z, purlin_line.internal_forces.Mxx, markershape = :o)
# plot(purlin_line.model.z, purlin_line.internal_forces.Myy, markershape = :o)
# plot(purlin_line.model.z, purlin_line.internal_forces.T, markershape = :o)
# plot(purlin_line.model.z, purlin_line.internal_forces.Vyy, markershape = :o)

purlin_line.failure_location
purlin_line.failure_limit_state
purlin_line.applied_pressure*1000*144



intelli_frame_type = "2x4.5x2.5 16g"

new_deck_type = "Vertical Rib SS 18 24 gauge"

intelli_frame_material_properties = [(29500.0, 0.30, 55.0, 70.0)]  #E, ν, Fy, Fu

intelli_frame_purlin_line = UI.retrofit_UI_mapper(purlin_line, intelli_frame_data, intelli_frame_type, new_deck_type, new_deck_data, existing_deck_type, existing_deck_data, intelli_frame_material_properties, "gravity");


intelli_frame_purlin_line.applied_pressure*1000*144

intelli_frame_purlin_line.failure_limit_state

# flexure_torsion_demand_to_capacity::PurlinLine.FlexureTorsion_DemandToCapacity_Data
# biaxial_bending_demand_to_capacity::PurlinLine.BiaxialBending_DemandToCapacity_Data
# distortional_demand_to_capacity::Array{Float64}
# flexure_shear_demand_to_capacity::Array{Float64}


struct BiaxialBending_DemandToCapacity_Data
    
    action_P::Array{Float64}
    action_Mxx::Array{Float64}
    action_Myy::Array{Float64}
    interaction::Array{Float64}
    demand_to_capacity::Array{Float64}

end


plot(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.biaxial_bending_demand_to_capacity.action_Mxx, markershape = :o)
plot(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.biaxial_bending_demand_to_capacity.action_Myy, markershape = :o)



plot(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.flexure_shear_demand_to_capacity, markershape = :o)
plot!(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.distortional_demand_to_capacity, markershape = :o)


intelli_frame_purlin_line.local_global_flexural_strength_xx

intelli_frame_purlin_line.yielding_flexural_strength_xx_net

intelli_frame_purlin_line.yielding_flexural_strength_xx


intelli_frame_purlin_line.distortional_flexural_strength_xx

# Mne::Float64
# Mnℓ_pos::Float64
# Mnℓ_neg::Float64
# eMnℓ_pos::Float64
# eMnℓ_neg::Float64




intelli_frame_purlin_line.local_global_flexural_strength_xx_no_hole


intelli_frame_purlin_line.local_global_flexural_strength_xx_hole


plot(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.Β_distortional_gradient_factor, markershape = :o)
# Β_distortional_gradient_factor


plot(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.internal_forces.Mxx, markershape = :o)

plot(intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.expected_strengths.eMnd_xx, markershape = :o)


minimum(intelli_frame_purlin_line.expected_strengths.eMnd_xx)


# eMnd_xx

# plot(purlin_line.model.z, purlin_line.internal_forces.Mxx, markershape = :o)
# plot(purlin_line.model.z, purlin_line.internal_forces.Myy, markershape = :o)

# intelli_frame_purlin_line.model.inputs.kx
# intelli_frame_purlin_line.model.inputs.kϕ