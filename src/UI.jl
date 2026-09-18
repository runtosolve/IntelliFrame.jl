module UI

using PurlinLine, Plots, LinesCurvesNodes, CrossSectionGeometry, CSV, DataFrames

using ..IntelliFrame

function define_lap_section_types(purlin_size_span_assignment)

    #There are 3 possible combinations of purlin types at a lap: 1-1, 2-2, or 1-2.

    num_laps = length(purlin_size_span_assignment) - 1

    # lap_section_types = Array{String}(undef, num_laps)

    lap_section_types = Vector{Tuple{Int64, Int64}}(undef, num_laps)

    for i = 1:num_laps

        lap_section_types[i] = (purlin_size_span_assignment[i], purlin_size_span_assignment[i+1])
        # purlin_span_1 = purlin_size_span_assignment[i]
        # purlin_span_2 = purlin_size_span_assignment[i+1]

        # if (purlin_span_1 == purlin_span_2) & (purlin_span_1 == 1)

        #     lap_section_types[i] = "1-1"

        # elseif (purlin_span_1 == purlin_span_2) & (purlin_span_1 == 2)

        #     lap_section_types[i] = "2-2"

        # elseif purlin_span_1 != purlin_span_2

        #     lap_section_types[i] = "1-2"

        # end

    end

    return lap_section_types

end

function define_lap_section_index(lap_section_types, purlin_size_span_assignment)

    num_lap_sections = length(lap_section_types)

    num_unique_lap_sections = length(unique(lap_section_types))

    unique_lap_sections = unique(lap_section_types)

    lap_section_index = Array{Int64}(undef, num_lap_sections)

    for i = 1:num_unique_lap_sections

        index = findall(x -> x == unique_lap_sections[i], lap_section_types)

        lap_section_index[index] .= maximum(purlin_size_span_assignment) + i

    end

    return lap_section_index

end

function define_lap_segments(purlin_laps, purlin_size_span_assignment)

    num_interior_supports = trunc(Int, length(purlin_laps) / 2)

    lap_segments = Array{Tuple{Float64,Float64,Int64,Int64},1}(undef, num_interior_supports * 2)

    lap_section_types = define_lap_section_types(purlin_size_span_assignment)

    lap_section_index = define_lap_section_index(lap_section_types, purlin_size_span_assignment)

    for i = 1:num_interior_supports

        lap_segments[2*i-1] = (purlin_laps[2*i-1] * 12.0, (purlin_laps[2*i-1] * 12.0) / 6, lap_section_index[i], 1)
        lap_segments[2*i] = (purlin_laps[2*i] * 12.0, (purlin_laps[2*i] * 12.0) / 6, lap_section_index[i], 1)

    end

    return lap_segments

end

function define_purlin_line_segments(span_segments, lap_segments)

    num_spans = length(span_segments)

    num_purlin_line_segments = length(span_segments) + length(lap_segments)

    purlin_line_segments = Array{Tuple{Float64,Float64,Int64,Int64},1}(undef, num_purlin_line_segments)

    segment_index = 1

    lap_segment_index = 1

    for i = 1:num_spans

        if i == 1 #first span

            purlin_line_segments[i] = span_segments[1]

            if num_spans > 1
                purlin_line_segments[i+1] = lap_segments[1]

                lap_segment_index = lap_segment_index + 1
                segment_index = segment_index + 2
            end

        elseif (i > 1) & (i != num_spans) #interior span

            purlin_line_segments[segment_index] = lap_segments[lap_segment_index]
            purlin_line_segments[segment_index+1] = span_segments[i]
            purlin_line_segments[segment_index+2] = lap_segments[lap_segment_index+1]

            lap_segment_index = lap_segment_index + 2
            segment_index = segment_index + 3

        elseif i == num_spans  #end span

            purlin_line_segments[segment_index] = lap_segments[lap_segment_index]
            purlin_line_segments[segment_index+1] = span_segments[i]

        end

    end

    return purlin_line_segments

end

function define_purlin_line_cross_section_dimensions(purlin_line_segments, lap_section_types, purlin_data, purlin_types)

    purlin_line_cross_section_indices = [purlin_line_segments[i][3] for i = 1:length(purlin_line_segments)]

    unique_purlin_line_cross_section_indices = sort(unique(purlin_line_cross_section_indices))

    # if !isempty(lap_section_types) #for multiple spans only

    #     if isempty(findall(x -> x == 2, unique_purlin_line_cross_section_indices)) #if there is no second purlin type defined, then add it, it won't be used though

    #         unique_purlin_line_cross_section_indices = [unique_purlin_line_cross_section_indices[1]; 2; unique_purlin_line_cross_section_indices[2:end]]

    #     end

    # end

    num_cross_sections = length(unique_purlin_line_cross_section_indices)

    unique_lap_cross_sections = unique(lap_section_types)

    num_lap_cross_sections = length(unique_lap_cross_sections)

    num_purlin_cross_sections = num_cross_sections - num_lap_cross_sections

    purlin_line_cross_section_dimensions = Vector{Tuple{String,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64,Float64}}(undef, num_cross_sections)

    # purlin_index_1 = findfirst(==(purlin_type_1), purlin_data.section_name)
    # purlin_index_2 = findfirst(==(purlin_type_2), purlin_data.section_name)

    # purlin_type_indices = [purlin_index_1; purlin_index_2]

    for i = 1:num_cross_sections

        if i <= num_purlin_cross_sections

            purlin_index = findfirst(purlin->purlin==purlin_types[i], purlin_data.section_name)
            purlin_line_cross_section_dimensions[i] = tuple([purlin_data[purlin_index, :][i] for i = 2:17]...)

        else

            # purlin_index_1 = findfirst(lap->lap == lap_section_types[i][1], purlin_data.section_name)
            # purlin_index_2 = findfirst(lap->lap == lap_section_types[i][2], purlin_data.section_name)

            baseline_cross_section_dimensions = [purlin_line_cross_section_dimensions[unique_lap_cross_sections[i-num_purlin_cross_sections][1]][j] for j=1:16]  #use the first purlin index here 

            #add the purlin 1 and purlin 2 thicknesses together
            baseline_cross_section_dimensions[2] += purlin_line_cross_section_dimensions[unique_lap_cross_sections[i-num_purlin_cross_sections][2]][2]

            purlin_line_cross_section_dimensions[i] = tuple([baseline_cross_section_dimensions[i] for i = 1:16]...)


        end

    end

        # cross_section_index = unique_purlin_line_cross_section_indices[i]

        # if cross_section_index <= 2

        #     if purlin_type_2 == "none" #not used, set cross-section equal to purlin_type_1

        #         cross_section_index = unique_purlin_line_cross_section_indices[1]

        #     end

        #     purlin_line_cross_section_dimensions[i] = tuple([purlin_data[purlin_type_indices[cross_section_index], :][i] for i = 2:17]...)

        # elseif cross_section_index > 2 #these are the laps

        #     lap_type = lap_section_types[cross_section_index-2]

        #     if lap_type == "1-1"

        #         cross_section_index = unique_purlin_line_cross_section_indices[1]

        #         baseline_cross_section_dimensions = deepcopy(purlin_data[purlin_type_indices[cross_section_index], :])

        #         #multiply base metal thickness by 2
        #         baseline_cross_section_dimensions[3] = baseline_cross_section_dimensions[3] * 2.0

        #         purlin_line_cross_section_dimensions[i] = tuple([baseline_cross_section_dimensions[i] for i = 2:17]...)

        #     elseif lap_type == "2-2"

        #         cross_section_index = unique_purlin_line_cross_section_indices[2]

        #         baseline_cross_section_dimensions = deepcopy(purlin_data[purlin_type_indices[cross_section_index], :])

        #         #multiply base metal thickness by 2
        #         baseline_cross_section_dimensions[3] = baseline_cross_section_dimensions[3] * 2.0

        #         purlin_line_cross_section_dimensions[i] = tuple([baseline_cross_section_dimensions[i] for i = 2:17]...)

        #     elseif lap_type == "1-2"

        #         cross_section_index = unique_purlin_line_cross_section_indices[1]

        #         baseline_cross_section_dimensions = deepcopy(purlin_data[purlin_type_indices[cross_section_index], :])

        #         #add the purlin 1 and purlin 2 thicknesses together
        #         baseline_cross_section_dimensions[3] = baseline_cross_section_dimensions[3] + purlin_line_cross_section_dimensions[2][2]


        #         purlin_line_cross_section_dimensions[i] = tuple([baseline_cross_section_dimensions[i] for i = 2:17]...)

        #     end

        # end

    # end

    return purlin_line_cross_section_dimensions

end

function define_span_segments(purlin_spans, purlin_laps, purlin_size_span_assignment)

    num_spans = length(purlin_spans)

    span_segments = Array{Tuple{Float64,Float64,Int64,Int64},1}(undef, num_spans)

    lap_index = 1

    for i = 1:num_spans

        if i == 1 #first spans

            if num_spans == 1 #for single span

                segment_length = purlin_spans[i] * 12

            else #multiple spans

                segment_length = purlin_spans[i] * 12 - purlin_laps[lap_index] * 12

            end

            span_segments[i] = (segment_length, segment_length / 18, purlin_size_span_assignment[i], 1)

            lap_index = lap_index + 1

        elseif (i > 1) & (i != num_spans) #interior span

            segment_length = purlin_spans[i] * 12 - purlin_laps[lap_index] * 12 - purlin_laps[lap_index+1] * 12
            span_segments[i] = (segment_length, segment_length / 18, purlin_size_span_assignment[i], 1)

            lap_index = lap_index + 2

        elseif i == num_spans #end span

            segment_length = purlin_spans[i] * 12 - purlin_laps[lap_index] * 12
            span_segments[i] = (segment_length, segment_length / 18, purlin_size_span_assignment[i], 1)

        end

    end

    return span_segments

end

function existing_roof_UI_mapper(purlin_spans, purlin_laps, purlin_spacing, roof_slope, purlin_data, existing_deck_type, existing_deck_data, frame_flange_width, purlin_frame_connection, purlin_types, purlin_size_span_assignment, loading_direction)

    design_code = "ASD"

    span_segments = define_span_segments(purlin_spans, purlin_laps, purlin_size_span_assignment)

    lap_section_types = define_lap_section_types(purlin_size_span_assignment)

    lap_segments = define_lap_segments(purlin_laps, purlin_size_span_assignment)

    purlin_segments = define_purlin_line_segments(span_segments, lap_segments)

    purlin_spacing = purlin_spacing * 12.0

    roof_slope = rad2deg(atan(roof_slope))

    purlin_cross_section_dimensions = define_purlin_line_cross_section_dimensions(purlin_segments, lap_section_types, purlin_data, purlin_types)

    purlin_material_properties = [(29500.0, 0.30, 50.0, 70.0)]  #E, ν, Fy, Fu

    deck_index = findfirst(==(existing_deck_type), existing_deck_data.deck_name)

    if !ismissing(existing_deck_data.fastener_spacing[deck_index])
        existing_roof_panel_details = ("screw-fastened", existing_deck_data[deck_index, 2], existing_deck_data[deck_index, 3], existing_deck_data[deck_index, 4], existing_deck_data[deck_index, 5])
	elseif !ismissing(existing_deck_data.clip_spacing[deck_index])
        existing_roof_panel_details = ("vertical leg standing seam", existing_deck_data[deck_index, 7])
    end

    existing_roof_panel_material_properties = (29500.0, 0.30, 55.0, 70.0)  #E, ν, Fy, Fu

    support_locations = [0.0; collect(cumsum(purlin_spans .* 12.0))]

    if purlin_frame_connection == "Clip-mounted"

        purlin_frame_connections = "anti-roll clip"

    elseif purlin_frame_connection == "Direct"

        purlin_frame_connections = "bottom flange connection"

    end

    intermediate_bridging_locations = []

    # loading_direction = "gravity"

    inputs = PurlinLine.Inputs(loading_direction, design_code, purlin_segments, purlin_spacing, roof_slope, purlin_cross_section_dimensions, purlin_material_properties, existing_roof_panel_details, existing_roof_panel_material_properties, frame_flange_width, support_locations, purlin_frame_connections, intermediate_bridging_locations)

    purlin_line = PurlinLine.build(inputs)

    # purlin_line = PurlinLine.build(design_code, purlin_segments, purlin_spacing, roof_slope, purlin_cross_section_dimensions, purlin_material_properties, existing_roof_panel_details, existing_roof_panel_material_properties, frame_flange_width, support_locations, purlin_frame_connections, intermediate_bridging_locations)

    #Run a gravity test.
    # purlin_line.loading_direction = "gravity"
    purlin_line = PurlinLine.test(purlin_line);

    return purlin_line;

end;

function retrofit_UI_mapper(purlin_line, intelli_frame_data, intelli_frame_type, new_deck_type, new_deck_data, existing_deck_type, existing_deck_data, intelli_frame_material_properties, loading_direction)


    intelli_frame_section_index = findfirst(==(intelli_frame_type), intelli_frame_data.section_name)

    intelli_frame_cross_section_dimensions = [tuple([intelli_frame_data[intelli_frame_section_index, :][i] for i = 2:13]...)]

    # Define the IntelliFrame material properties.
    # intelli_frame_material_properties = [(29500.0, 0.30, 55.0, 70.0)] #E, ν, Fy, Fu

    # Define the IntelliFrame punchout dimensions.
	intelli_frame_punch_out_dimensions = [(intelli_frame_data[intelli_frame_section_index, :punchout_width], intelli_frame_data[intelli_frame_section_index, :punchout_height])]

	
    # intelli_frame_punch_out_dimensions = [hugger_window_dimensions] #length, height

    #Define the new deck details.

    new_deck_index = findfirst(==(new_deck_type), new_deck_data.deck_name)


    if new_deck_type == "no deck"

        new_roof_panel_details = ["no deck"]

    elseif !ismissing(new_deck_data[new_deck_index, 3]) #screw_fastened

        new_roof_panel_details = ("screw-fastened", new_deck_data[new_deck_index, 2], new_deck_data[new_deck_index, 3], new_deck_data[new_deck_index, 4], new_deck_data[new_deck_index, 5])

    elseif ismissing(new_deck_data[new_deck_index, 3]) #SSR

        new_roof_panel_details = ("vertical leg standing seam", new_deck_data[new_deck_index, 7])

    end

    new_roof_panel_material_properties = (29500.0, 0.30, 55.0, 70.0)


    #L, dL, purlin type, Hugger type, purlin mat props, Hugger mat props, Hugger punchout type

    #length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

    num_segments = length(purlin_line.inputs.segments)
    # segment_lengths = [purlin_line.inputs.segments[i][1] for i=1:num_segments]
    # segment_length = purlin_line.inputs.segments[1][1]

    hugger_purlin_segments = Vector{Tuple{Float64,Float64,Int64,Int64,Int64,Int64,Int64}}(undef, num_segments)

    for i = 1:num_segments

        hugger_purlin_segments[i] = (purlin_line.inputs.segments[i][1], purlin_line.inputs.segments[i][2], purlin_line.inputs.segments[i][3], 1, 1, 1, 1)

    end




	#IntelliFrame is attached with closely spaced screws to existing deck so update existing deck details.
	existing_deck_index = findfirst(==(existing_deck_type), existing_deck_data.deck_name)
    
    fastener_diameter = 0.212
    Fss = 2.5
    fastener_spacing = 3.0
    purlin_line.inputs.deck_details = ("screw-fastened", existing_deck_data[existing_deck_index, 2], fastener_spacing, fastener_diameter, Fss)

    # Assemble the purlin line model, now with the addition of Hugger Framing.
    intelli_frame_purlin_line = IntelliFrame.define(purlin_line.inputs.design_code, hugger_purlin_segments, purlin_line.inputs.spacing, purlin_line.inputs.roof_slope, purlin_line.inputs.cross_section_dimensions, intelli_frame_cross_section_dimensions, intelli_frame_punch_out_dimensions, purlin_line.inputs.material_properties, intelli_frame_material_properties, purlin_line.inputs.deck_details, purlin_line.inputs.deck_material_properties, new_roof_panel_details, new_roof_panel_material_properties, purlin_line.inputs.frame_flange_width, purlin_line.inputs.support_locations, purlin_line.inputs.purlin_frame_connections, purlin_line.inputs.bridging_locations)


    # Run a test to calculate the expected roof system failure pressure including the IntelliFrame.
    # intelli_frame_purlin_line.loading_direction = "gravity"
    intelli_frame_purlin_line.loading_direction = loading_direction
    intelli_frame_purlin_line = IntelliFrame.capacity(intelli_frame_purlin_line)

    return intelli_frame_purlin_line

end

function show_multi_branch_cross_section(xcoords, ycoords, element_connectivity, markershape, xlims, ylims)

    num_elem = size(element_connectivity)[1]

    plt = []

    for i = 1:num_elem

        node_i = Int(element_connectivity[i, 1])
        node_j = Int(element_connectivity[i, 2])

        if i == 1

            plt = plot([xcoords[node_i], xcoords[node_j]], [ycoords[node_i], ycoords[node_j]], size=(600, 600), legend=false, linecolor=:blue, markercolor=:black, markershape=markershape, seriestype=:line, xlims=xlims, ylims=ylims)

        else

            plot!(plt, [xcoords[node_i], xcoords[node_j]], [ycoords[node_i], ycoords[node_j]], size=(600, 600), legend=false, linecolor=:blue, markercolor=:black, markershape=markershape, seriestype=:line, xlims=xlims, ylims=ylims)

        end

    end

    return plt

end

#################

function generate_purlin_geometry(t, xcoords_center, ycoords_center, roof_slope)

    center_nodes = [xcoords_center ycoords_center zeros(Float64, length(xcoords_center))]

    center_nodes_rotated = LinesCurvesNodes.rotate_nodes(center_nodes, rotation_axis="z", rotation_center=[0.0, 0.0, 0.0], θ=atan(roof_slope))

    cross_section = [[xcoords_center[i], ycoords_center[i]] for i in eachindex(xcoords_center)]

    unit_node_normals = CrossSectionGeometry.calculate_cross_section_unit_node_normals(cross_section)

    outside = CrossSectionGeometry.get_coords_along_node_normals(cross_section, unit_node_normals, t / 2)
    X = [outside[i][1] for i in eachindex(outside)]
    Y = [outside[i][2] for i in eachindex(outside)]
    out_nodes = [X Y zeros(Float64, length(xcoords_center))]
    out_nodes_rotated = LinesCurvesNodes.rotate_nodes(out_nodes, rotation_axis="z", rotation_center=[0.0, 0.0, 0.0], θ=atan(roof_slope))

    inside = CrossSectionGeometry.get_coords_along_node_normals(cross_section, unit_node_normals, -t / 2)
    X = [inside[i][1] for i in eachindex(inside)]
    Y = [inside[i][2] for i in eachindex(inside)]
    in_nodes = [X Y zeros(Float64, length(xcoords_center))]
    in_nodes_rotated = LinesCurvesNodes.rotate_nodes(in_nodes, rotation_axis="z", rotation_center=[0.0, 0.0, 0.0], θ=atan(roof_slope))

    return center_nodes_rotated, out_nodes_rotated, in_nodes_rotated

end

function plot_purlin_geometry(t, xcoords_center, ycoords_center, roof_slope)

    center_nodes, out_nodes, in_nodes = generate_purlin_geometry(t, xcoords_center, ycoords_center, roof_slope)

    plot(center_nodes[:, 1], center_nodes[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(out_nodes[:, 1], out_nodes[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(in_nodes[:, 1], in_nodes[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

end



function plot_intelli_frame_purlin_geometry(t_purlin, t_hugger, xcoords_center_purlin, ycoords_center_purlin, roof_slope, xcoords_intelli_frame_purlin_line, ycoords_intelli_frame_purlin_line, xcoords_center_intelli_frame, ycoords_center_intelli_frame)

    center_nodes_purlin, out_nodes_purlin, in_nodes_purlin = generate_purlin_geometry(t_purlin, xcoords_center_purlin, ycoords_center_purlin, roof_slope)

    plot(center_nodes_purlin[:, 1], center_nodes_purlin[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(out_nodes_purlin[:, 1], out_nodes_purlin[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(in_nodes_purlin[:, 1], in_nodes_purlin[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    intelli_frame_bottom_flange_centerline_node = 28
    Δx = xcoords_intelli_frame_purlin_line[intelli_frame_bottom_flange_centerline_node]
    Δy = ycoords_intelli_frame_purlin_line[intelli_frame_bottom_flange_centerline_node]
    Δz = 0.0

    center_nodes_intelli_frame, out_nodes_intelli_frame, in_nodes_intelli_frame = generate_intelli_frame_geometry(t_hugger, xcoords_center_intelli_frame, ycoords_center_intelli_frame, roof_slope, Δx, Δy, Δz)

    plot!(center_nodes_intelli_frame[:, 1], center_nodes_intelli_frame[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(out_nodes_intelli_frame[:, 1], out_nodes_intelli_frame[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(in_nodes_intelli_frame[:, 1], in_nodes_intelli_frame[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

end


function plot_net_section_intelli_frame_purlin_geometry(t_purlin, t_hugger, xcoords_center_purlin, ycoords_center_purlin, xcoords_center_intelli_frame, ycoords_center_intelli_frame, roof_slope, xcoords_center_intelli_frame_purlin, ycoords_center_intelli_frame_purlin, net_intelli_frame_purlin_node_geometry)

    center_nodes_purlin, out_nodes_purlin, in_nodes_purlin = generate_purlin_geometry(t_purlin, xcoords_center_purlin, ycoords_center_purlin, roof_slope)

    plot(center_nodes_purlin[:, 1], center_nodes_purlin[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(out_nodes_purlin[:, 1], out_nodes_purlin[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(in_nodes_purlin[:, 1], in_nodes_purlin[:, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    intelli_frame_bottom_flange_centerline_node = 28
    Δx = xcoords_center_intelli_frame_purlin[intelli_frame_bottom_flange_centerline_node]
    Δy = ycoords_center_intelli_frame_purlin[intelli_frame_bottom_flange_centerline_node]
    Δz = 0.0

    center_nodes_intelli_frame, out_nodes_intelli_frame, in_nodes_intelli_frame = generate_intelli_frame_geometry(t_hugger, xcoords_center_intelli_frame, ycoords_center_intelli_frame, roof_slope, Δx, Δy, Δz)

    num_intelli_frame_purlin_net_section_nodes = size(net_intelli_frame_purlin_node_geometry, 1)

    num_purlin_nodes = size(xcoords_center_purlin, 1)

    num_intelli_frame_net_section_nodes = num_intelli_frame_purlin_net_section_nodes - num_purlin_nodes

    plot_index = num_intelli_frame_net_section_nodes

    # plot!(center_nodes_intelli_frame[1:plot_index,1], center_nodes_intelli_frame[1:plot_index,2], aspect_ratio=:equal, linecolor = :grey, legend=false)

    # plot!(out_nodes_intelli_frame[1:plot_index,1], out_nodes_intelli_frame[1:plot_index,2], aspect_ratio=:equal, linecolor = :grey, legend=false)

    # plot!(in_nodes_intelli_frame[1:plot_index,1], in_nodes_intelli_frame[1:plot_index,2], aspect_ratio=:equal, linecolor = :grey, legend=false)

    plot!(center_nodes_intelli_frame[end-plot_index+1:end, 1], center_nodes_intelli_frame[end-plot_index+1:end, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(out_nodes_intelli_frame[end-plot_index+1:end, 1], out_nodes_intelli_frame[end-plot_index+1:end, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

    plot!(in_nodes_intelli_frame[end-plot_index+1:end, 1], in_nodes_intelli_frame[end-plot_index+1:end, 2], aspect_ratio=:equal, linecolor=:grey, legend=false)

end



function generate_intelli_frame_geometry(t, xcoords_center, ycoords_center, roof_slope, Δx, Δy, Δz)

    center_nodes = [xcoords_center ycoords_center zeros(Float64, length(xcoords_center))]

    center_nodes = LinesCurvesNodes.shift_nodes(center_nodes, Δx=Δx, Δy=Δy, Δz=Δz)

    center_nodes_rotated = LinesCurvesNodes.rotate_nodes(center_nodes, rotation_axis="z", rotation_center=[0.0, 0.0, 0.0], θ=atan(roof_slope))


    cross_section = [[xcoords_center[i], ycoords_center[i]] for i in eachindex(xcoords_center)]

    unit_node_normals = CrossSectionGeometry.calculate_cross_section_unit_node_normals(cross_section)

    outside = CrossSectionGeometry.get_coords_along_node_normals(cross_section, unit_node_normals, t / 2)
    X = [outside[i][1] for i in eachindex(outside)]
    Y = [outside[i][2] for i in eachindex(outside)]
    out_nodes = [X Y zeros(Float64, length(xcoords_center))]
    out_nodes = LinesCurvesNodes.shift_nodes(out_nodes, Δx=Δx, Δy=Δy, Δz=Δz)
    out_nodes_rotated = LinesCurvesNodes.rotate_nodes(out_nodes, rotation_axis="z", rotation_center=[0.0, 0.0, 0.0], θ=atan(roof_slope))

    inside = CrossSectionGeometry.get_coords_along_node_normals(cross_section, unit_node_normals, -t / 2)
    X = [inside[i][1] for i in eachindex(inside)]
    Y = [inside[i][2] for i in eachindex(inside)]
    in_nodes = [X Y zeros(Float64, length(xcoords_center))]
    in_nodes = LinesCurvesNodes.shift_nodes(in_nodes, Δx=Δx, Δy=Δy, Δz=Δz)
    in_nodes_rotated = LinesCurvesNodes.rotate_nodes(in_nodes, rotation_axis="z", rotation_center=[0.0, 0.0, 0.0], θ=atan(roof_slope))


    ####3

    # center_nodes_rotated = Geometry.rotate_nodes(center_nodes, rotation_axis = "z", rotation_center = [0.0, 0.0, 0.0], θ=atan(roof_slope))

    # 	#Calculate surface normals.
    # closed_or_open = 1
    # unitnormals = SectionProperties.surface_normals(center_nodes[:, 1], center_nodes[:, 2], closed_or_open)


    # nodenormals = SectionProperties.avg_node_normals(unitnormals, closed_or_open)


    # xcoords_out, ycoords_out = SectionProperties.xycoords_along_normal(center_nodes[:, 1], center_nodes[:, 2], nodenormals, t/2)

    # out_nodes_rotated = [xcoords_out ycoords_out zeros(Float64, length(xcoords_center))]

    # # out_nodes_rotated = Geometry.rotate_nodes(out_nodes, rotation_axis = "z", rotation_center = [0.0, 0.0, 0.0], θ=atan(roof_slope))

    # xcoords_in, ycoords_in = SectionProperties.xycoords_along_normal(center_nodes[:, 1], center_nodes[:, 2], nodenormals, -t/2)

    # in_nodes_rotated = [xcoords_in ycoords_in zeros(Float64, length(xcoords_center))]

    # in_nodes_rotated = Geometry.rotate_nodes(in_nodes, rotation_axis = "z", rotation_center = [0.0, 0.0, 0.0], θ=atan(roof_slope))

    return center_nodes_rotated, out_nodes_rotated, in_nodes_rotated

end


function load_databases()

    database_dir = joinpath(@__DIR__, "..", "database")

    purlin_data = CSV.read(joinpath(database_dir, "Purlins.csv"), DataFrame)

    intelli_frame_data = CSV.read(joinpath(database_dir, "IntelliFrameRF.csv"), DataFrame)

    existing_deck_data = CSV.read(joinpath(database_dir, "Existing_Deck.csv"), DataFrame)

    new_deck_data = CSV.read(joinpath(database_dir, "New_Deck.csv"), DataFrame)

    return (purlin_data = purlin_data, intelli_frame_data = intelli_frame_data, existing_deck_data = existing_deck_data, new_deck_data = new_deck_data)

end

end #module 
