module IntelliFrame

using PurlinLine, CUFSM, NumericalIntegration, ThinWalledBeam, PlautBeamColumnElement, AISIS100, ScrewConnections, CrossSectionGeometry, SectionProperties


export define, analysis, capacity

export UI
include("UI.jl")
using .UI


mutable struct Inputs

    design_code::String
    segments::Vector{Tuple{Float64, Float64, Int64, Int64, Int64, Int64, Int64}}
    spacing::Float64
    roof_slope::Float64
    purlin_cross_section_dimensions::Vector{Tuple{String, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64}}
    intelli_frame_cross_section_dimensions::Vector{NTuple{12, Float64}}
    intelli_frame_punch_out_dimensions::Vector{NTuple{2, Float64}}
    purlin_material_properties::Vector{NTuple{4, Float64}}
    intelli_frame_material_properties::Vector{NTuple{4, Float64}}
    deck_details::Any
    deck_material_properties::NTuple{4, Float64}
    new_deck_details::Any
    new_deck_material_properties::NTuple{4, Float64}
    frame_flange_width::Float64
    support_locations::Vector{Float64}
    purlin_frame_connections::String
    bridging_locations::Vector{Float64}

end

struct DeckSprings 

    kx_existing_deck::Array{Float64}
    kx_new_deck::Array{Float64}
    ay_kx_existing_deck::Array{Float64}
    ay_kx_new_deck::Array{Float64}
    kϕ_existing_deck::Array{Float64}
    kϕ_new_deck::Array{Float64}
    
end

mutable struct IntelliFrameObject

    inputs::IntelliFrame.Inputs

    applied_pressure::Float64

    loading_direction::String

    purlin_cross_section_data::Array{PurlinLine.CrossSectionData}

    free_flange_cross_section_data::Array{PurlinLine.CrossSectionData}

    intelli_frame_cross_section_data::Array{PurlinLine.CrossSectionData}

    intelli_frame_purlin_cross_section_data::Array{PurlinLine.CrossSectionData}

    intelli_frame_purlin_net_cross_section_data::Array{PurlinLine.CrossSectionData}

    intelli_frame_purlin_distortional_net_cross_section_data::Array{PurlinLine.CrossSectionData}

    bracing_data::Array{PurlinLine.BracingData}

    new_deck_bracing_data::Array{PurlinLine.BracingData}

    free_flange_data::Array{PurlinLine.FreeFlangeData}

    local_buckling_xx_pos::Array{PurlinLine.ElasticBucklingData}
    local_buckling_xx_net_pos::Array{PurlinLine.ElasticBucklingData}
    local_buckling_xx_neg::Array{PurlinLine.ElasticBucklingData}
    local_buckling_yy_pos::Array{PurlinLine.ElasticBucklingData}
    local_buckling_yy_neg::Array{PurlinLine.ElasticBucklingData}
    distortional_buckling_xx_pos::Array{PurlinLine.ElasticBucklingData}
    distortional_buckling_xx_net_pos::Array{PurlinLine.ElasticBucklingData}
    distortional_buckling_xx_neg::Array{PurlinLine.ElasticBucklingData}

    yielding_flexural_strength_xx::Array{PurlinLine.YieldingFlexuralStrengthData}
    yielding_flexural_strength_xx_net::Array{PurlinLine.YieldingFlexuralStrengthData}
    yielding_flexural_strength_yy::Array{PurlinLine.YieldingFlexuralStrengthData}
    yielding_flexural_strength_free_flange_yy::Array{PurlinLine.YieldingFlexuralStrengthData}

    local_global_flexural_strength_xx_no_hole::Array{PurlinLine.LocalGlobalFlexuralStrengthData}
    local_global_flexural_strength_xx_hole::Array{PurlinLine.LocalGlobalFlexuralStrengthData}
    local_global_flexural_strength_xx::Array{PurlinLine.LocalGlobalFlexuralStrengthData}
    local_global_flexural_strength_yy::Array{PurlinLine.LocalGlobalFlexuralStrengthData}
    local_global_flexural_strength_free_flange_yy::Array{PurlinLine.LocalGlobalFlexuralStrengthData}

    distortional_flexural_strength_xx::Array{PurlinLine.DistortionalFlexuralStrengthData}

    torsion_strength_purlin::Array{PurlinLine.TorsionStrengthData}
    torsion_strength_intelli_frame::Array{PurlinLine.TorsionStrengthData}
    torsion_strength::Array{PurlinLine.TorsionStrengthData}

    shear_strength_purlin::Array{PurlinLine.ShearStrengthData}
    shear_strength_intelli_frame::Array{PurlinLine.ShearStrengthData}
    shear_strength::Array{PurlinLine.ShearStrengthData}

    purlin_web_crippling::Array{PurlinLine.WebCripplingData}
    intelli_frame_web_crippling::Array{PurlinLine.WebCripplingData}

    model::ThinWalledBeam.Model

    deck_springs::DeckSprings

    free_flange_model::PlautBeamColumnElement.Model

    internal_forces::PurlinLine.InternalForceData

    free_flange_internal_forces::PurlinLine.InternalForceData

    support_reactions::PurlinLine.Reactions

    flexure_torsion_demand_to_capacity::PurlinLine.FlexureTorsion_DemandToCapacity_Data
    biaxial_bending_demand_to_capacity::PurlinLine.BiaxialBending_DemandToCapacity_Data
    distortional_demand_to_capacity::Array{Float64}
    flexure_shear_demand_to_capacity::Array{Float64}

    Β_distortional_gradient_factor::Array{Float64}
    
    purlin_web_crippling_demand_to_capacity::Array{Float64}
    intelli_frame_web_crippling_demand_to_capacity::Array{Float64}
    web_crippling_demand_to_capacity::Array{Float64}
    
    expected_strengths::PurlinLine.ExpectedStrengths

    failure_limit_state::String

    failure_location::Float64

    IntelliFrameObject() = new()

end


function define_intelli_frame_cross_sections(cross_section_dimensions, n, n_radius)

    num_intelli_frame_sections = size(cross_section_dimensions)[1]

    cross_section_data = Vector{PurlinLine.CrossSectionData}(undef, num_intelli_frame_sections)

    for i = 1:num_intelli_frame_sections

        #Map dimensions to cross-section nomenclature.
        t = cross_section_dimensions[i][1]
        b_bottom = cross_section_dimensions[i][2]
        h = cross_section_dimensions[i][3]
        b_top = cross_section_dimensions[i][4]
        d_top = cross_section_dimensions[i][5]
        α1 = cross_section_dimensions[i][6]
        α2 = cross_section_dimensions[i][7]
        α3 = cross_section_dimensions[i][8]
        α4 = cross_section_dimensions[i][9]
        r1 = cross_section_dimensions[i][10]
        r2 = cross_section_dimensions[i][11]
        r3 = cross_section_dimensions[i][12]

        #Define straight-line lengths on the top cross-section surface.   
        L = [b_bottom - t, h - t, b_top, d_top]
        θ = deg2rad.([α1, α2, α3, α4])

        #Note that the outside radius is used at the top flanges, and the inside radius is used for the bottom flange.
        radius = [r1-t, r2, r3]

        # closed_or_open = 1

        # n = [4, 6, 4, 4]
        # n_radius = [4, 4, 4]

        # intelli_frame_section = SectionProperties.Feature(ΔL, θ, n, radius, n_radius, closed_or_open)

        # #Calculate the out-to-out surface coordinates.
        # xcoords_out, ycoords_out = SectionProperties.get_xy_coordinates(intelli_frame_section)

        # #Calculate centerline coordinates.
        # unitnormals = SectionProperties.surface_normals(xcoords_out, ycoords_out, closed_or_open)
        # nodenormals = SectionProperties.avg_node_normals(unitnormals, closed_or_open)
        # xcoords_center, ycoords_center = SectionProperties.xycoords_along_normal(xcoords_out, ycoords_out, nodenormals, -t/2)


        cross_section = CrossSectionGeometry.generate_thin_walled(L, θ, n, radius, n_radius)

        #Get node normals on cross-section
        unit_node_normals = CrossSectionGeometry.calculate_cross_section_unit_node_normals(cross_section)
        #Get centerline coords
        centerline = CrossSectionGeometry.get_coords_along_node_normals(cross_section, unit_node_normals, t/2)
          
        xcoords_center = [centerline[i][1] for i in eachindex(cross_section)]
        ycoords_center = [centerline[i][2] for i in eachindex(cross_section)]



        #Shift y coordinates so that the bottom face is at y = 0.
        ycoords_center = ycoords_center .- minimum(ycoords_center) .+ t/2

        #Shift x coordinates so that the bottom flange centerline is at x = 0.
        index = floor(Int, n[1]/2)  + 1
        xcoords_center = xcoords_center .- xcoords_center[index]

        #Package nodal geometry.
        node_geometry = [xcoords_center ycoords_center]

        #Define cross-section element connectivity and thicknesses.
        num_cross_section_nodes = length(xcoords_center)
        element_info = [1:(num_cross_section_nodes - 1) 2:num_cross_section_nodes ones(num_cross_section_nodes - 1) * t]

        #Calculate section properties.
        section_properties = CUFSM.cutwp_prop2(node_geometry, element_info)

        #Add cross section information to data structure.
        cross_section_data[i] = PurlinLine.CrossSectionData(n, n_radius, node_geometry, element_info, section_properties, nothing)

    end

    return cross_section_data

end



function combine_intelli_frame_purlin_geometry(purlin_cross_section_dimensions, purlin_cross_section_data, intelli_frame_cross_section_data)

    #Find purlin top flange centerline.
    purlin_top_flange_centerline_index = sum(purlin_cross_section_data.n[1:3]) + floor(Int,purlin_cross_section_data.n[4]/2) + sum(purlin_cross_section_data.n_radius[1:3]) + 1
    purlin_top_flange_centerline_geometry = purlin_cross_section_data.node_geometry[purlin_top_flange_centerline_index, :]

    #Shift IntelliFrame geometry to sit on top of purlin top flange.
    intelli_frame_node_geometry = deepcopy(intelli_frame_cross_section_data.node_geometry)
    purlin_t = purlin_cross_section_dimensions[2]

    #Orient the IntelliFrame so that its top flange points the same way as the purlin bottom flange (IRF installation
    #convention). The IntelliFrame geometry has its bottom flange centered on x = 0, so mirroring it is x -> -x.
    #Purlin node order: lip, bottom flange, web, top flange, lip. IntelliFrame node order: bottom flange, web, top flange, lip.
    pn, pnr = purlin_cross_section_data.n, purlin_cross_section_data.n_radius
    purlin_bottom_flange_node = pn[1] + pnr[1] + floor(Int, pn[2] / 2) + 1
    purlin_web_node = sum(pn[1:2]) + sum(pnr[1:2]) + floor(Int, pn[3] / 2) + 1
    purlin_bottom_flange_direction = sign(purlin_cross_section_data.node_geometry[purlin_bottom_flange_node, 1] - purlin_cross_section_data.node_geometry[purlin_web_node, 1])
    hn, hnr = intelli_frame_cross_section_data.n, intelli_frame_cross_section_data.n_radius
    intelli_frame_web_node = hn[1] + hnr[1] + floor(Int, hn[2] / 2) + 1
    intelli_frame_top_flange_node = sum(hn[1:2]) + sum(hnr[1:2]) + floor(Int, hn[3] / 2) + 1
    intelli_frame_top_flange_direction = sign(intelli_frame_node_geometry[intelli_frame_top_flange_node, 1] - intelli_frame_node_geometry[intelli_frame_web_node, 1])
    if intelli_frame_top_flange_direction != purlin_bottom_flange_direction
        intelli_frame_node_geometry[:, 1] = -intelli_frame_node_geometry[:, 1]
    end

    intelli_frame_node_geometry[:, 1] = intelli_frame_node_geometry[:, 1] .+ purlin_top_flange_centerline_geometry[1]
    intelli_frame_node_geometry[:, 2] = intelli_frame_node_geometry[:, 2] .+ purlin_top_flange_centerline_geometry[2] .+ purlin_t/2 #check this

    # #Shift IntelliFrame node numbers after purlin node numbers.

    num_purlin_nodes = size(purlin_cross_section_data.node_geometry)[1]
    intelli_frame_element_definitions = deepcopy(intelli_frame_cross_section_data.element_definitions)

    intelli_frame_element_definitions[:,1:2] = intelli_frame_element_definitions[:,1:2] .+ num_purlin_nodes

    #Combine node geometry and element definitions for IntelliFrame and purlin.

    intelli_frame_purlin_node_geometry = [purlin_cross_section_data.node_geometry; intelli_frame_node_geometry]

    intelli_frame_purlin_element_definitions = [purlin_cross_section_data.element_definitions; intelli_frame_element_definitions]

    return intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions

end









function define_intelli_frame_purlin_cross_sections(segments, purlin_cross_section_dimensions, purlin_cross_section_data, intelli_frame_cross_section_data, purlin_plastic_cross_section_data, intelli_frame_plastic_cross_section_data)

    #Assume that for each purlin segment, there is a purlin cross-section and a IntelliFrame cross-section defined.
    num_strengthened_sections = size(segments)[1]

    intelli_frame_purlin_cross_section_data = Vector{PurlinLine.CrossSectionData}(undef, num_strengthened_sections)

    for i=1:num_strengthened_sections

        purlin_index = segments[i][3]
        intelli_frame_index = segments[i][4]

        intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions = combine_intelli_frame_purlin_geometry(purlin_cross_section_dimensions[purlin_index], purlin_cross_section_data[purlin_index], intelli_frame_cross_section_data[intelli_frame_index])

        #Calculate section properties.
        intelli_frame_purlin_section_properties = CUFSM.cutwp_prop2(intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions)

        #Combine discretization info.
        n = [purlin_cross_section_data[purlin_index].n; intelli_frame_cross_section_data[intelli_frame_index].n]
        n_radius = [purlin_cross_section_data[purlin_index].n_radius; intelli_frame_cross_section_data[intelli_frame_index].n_radius]

        #######
        #Calculate IntelliFrame+purlin plastic neutral axis and plastic modulus.
        intelli_frame_purlin_plastic_node_geometry, intelli_frame_purlin_plastic_element_definitions = combine_intelli_frame_purlin_geometry(purlin_cross_section_dimensions[purlin_index], purlin_plastic_cross_section_data[purlin_index], intelli_frame_plastic_cross_section_data[intelli_frame_index])

        about_axis = "x"  #The strong axis plastic properties are needed for now.  
        intelli_frame_purlin_plastic_section_properties = SectionProperties.calculate_plastic_section_properties(intelli_frame_purlin_plastic_node_geometry, intelli_frame_purlin_plastic_element_definitions, about_axis)

        #Add cross section information to data structure.
        intelli_frame_purlin_cross_section_data[i] = PurlinLine.CrossSectionData(n, n_radius, intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions, intelli_frame_purlin_section_properties, intelli_frame_purlin_plastic_section_properties)

    end

    return intelli_frame_purlin_cross_section_data

end

function define_new_deck_bracing_properties(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    bracing_data = Array{PurlinLine.BracingData, 1}(undef, num_purlin_segments)

    if intelli_frame_purlin_line.inputs.new_deck_details[1] == "screw-fastened"

        #Define the deck to IntelliFrame screw-fastened connection spacing.
        deck_intelli_frame_fastener_spacing = intelli_frame_purlin_line.inputs.new_deck_details[3]

        #Define the deck to purlin screw diameter.
        deck_intelli_frame_fastener_diameter = intelli_frame_purlin_line.inputs.new_deck_details[4]

        #Define the nominal shear strength of the typical screw.
        Fss = intelli_frame_purlin_line.inputs.new_deck_details[5]

        #Define the roof deck base metal thickness.
        t_roof_deck = intelli_frame_purlin_line.inputs.new_deck_details[2]

        #Define roof deck steel elastic modulus.
        E_roof_deck = intelli_frame_purlin_line.inputs.new_deck_material_properties[1]

        #Define roof deck steel ultimate yield stress.
        Fu_roof_deck = intelli_frame_purlin_line.inputs.new_deck_material_properties[4]

        #Define the distance between fasteners as the distortional discrete bracing length.
        Lm = deck_intelli_frame_fastener_spacing

        #Loop over all the Hugger+purlin segments in the line.  

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

    
        for i = 1:num_purlin_segments

            #Define the Hugger section property index associated with purlin segment i.
            section_index = intelli_frame_purlin_line.inputs.segments[i][4]

            #Define the Hugger material property index associated with purlin segment i.
            material_index = intelli_frame_purlin_line.inputs.segments[i][6]

            #Define IntelliFrame steel elastic modulus.
            E_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[material_index][1]

            #Define IntelliFrame steel Poisson's ratio.
            μ_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[material_index][2]

            #Define IntelliFrame steel ultimate stress.
            Fu_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[material_index][4]

            #Define the IntelliFrame top flange width.
            b_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][4]

            #Define IntelliFrame base metal thickness.
            t_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][1]

            #Define out-to-out IntelliFrame web depth.
            ho = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][3]

            #Define IntelliFrame top flange lip length.
            d_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][5]

            #Define IntelliFrame top flange lip angle from the horizon, in degrees.
            θ_top = abs(intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][9])

            #Define the location from the IntelliFrame top flange pivot point to the fastener.  Assume the fastener is centered in the flange.
            c = b_top/2

            #Define the deck fastener pull-through plate stiffness.  Assume the fastener is centered between two panel ribs.
            kp = PurlinLine.deck_pull_through_fastener_stiffness(intelli_frame_purlin_line.inputs.new_deck_material_properties, b_top, t_roof_deck)

            #Apply Cee or Zee binary.   Assume the IntelliFrame behaves like a Z for this stiffness calculation.
            CorZ = 1

            #Calculate the rotational stiffness provided to each IntelliFrame flange by the screw-fastened connection between the deck and the IntelliFrame.  It is assumed that the deck flexural stiffness is much higher than the connection stiffness.
            
            #Calculate the rotational stiffness provided to the purlin by the screw-fastened connection between the deck and the purlin.  It is assumed that the deck flexural stiffness is much higher than the connection stiffness.
            rotational_stiffness = ScrewConnections.rotational_stiffness(b_top, c, deck_intelli_frame_fastener_spacing, t_intelli_frame, kp, E_intelli_frame, "Z")  #hard code Z here, assume Hugger behaves like a Z
       
            # kϕ = ScrewConnections.cfs_rot_screwfastened_k(b_top, c, deck_intelli_frame_fastener_spacing, t_intelli_frame, kp, E_intelli_frame, CorZ)

            #Calculate the IntelliFrame distortional buckling half-wavelength.

            #Calculate top flange + lip section properties.
            Af, Jf, Ixf, Iyf, Ixyf, Cwf, xof,  hxf, hyf, yof = AISIS100.v16.table23131(CorZ, t_intelli_frame, b_top, d_top, θ_top)

            #Calculate the IntelliFrame distortional buckling half-wavelength.
            Lcrd, L = AISIS100.v16.app23334(ho, μ_intelli_frame, t_intelli_frame, Ixf, xof, hxf, Cwf, Ixyf, Iyf, Lm)

            #If Lcrd is longer than the fastener spacing, then the distortional buckling will be restrained by the deck.
            if Lcrd >= Lm
                kϕ_dist = rotational_stiffness.kϕ
            else
                kϕ_dist = 0.0
            end

            #Approximate the lateral stiffness provided to the top of each IntelliFrame flange by the screw-fastened connection between the deck and the IntelliFrame.

            #Calculate the stiffness of a single screw-fastened connection.
            α = 0.27  #for steel-to-steel, monotonic from Tao and Moen 2016 Table 8
            β = - 0.69  
            shear_stiffness = ScrewConnections.shear_stiffness(t_roof_deck, t_intelli_frame, E_roof_deck, E_intelli_frame, Fss, Fu_roof_deck, Fu_intelli_frame, deck_intelli_frame_fastener_diameter, α, β)

            #Convert the discrete stiffness to a distributed stiffness, divide by the fastener spacing.
            kx = shear_stiffness.Ke / deck_intelli_frame_fastener_spacing

            #Collect all the outputs.
            bracing_data[i] = PurlinLine.BracingData(kp, rotational_stiffness, rotational_stiffness.kϕ, kϕ_dist, shear_stiffness, kx, Lcrd, Lm)

        end

    elseif intelli_frame_purlin_line.inputs.new_deck_details[1] == "no deck"

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

              
        #Loop over all the Hugger+purlin segments in the line.  
        for i = 1:num_purlin_segments

            #Define the Hugger section property index associated with purlin segment i.
            section_index = intelli_frame_purlin_line.inputs.segments[i][4]

            #Define the Hugger material property index associated with purlin segment i.
            material_index = intelli_frame_purlin_line.inputs.segments[i][6]

            #Define IntelliFrame steel Poisson's ratio.
            μ_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[material_index][2]

            #Define the IntelliFrame top flange width.
            b_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][3]

            #Define IntelliFrame base metal thickness.
            t_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][1]

            #Define out-to-out IntelliFrame web depth.
            ho = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][4]

            #Define IntelliFrame top flange lip length.
            d_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][2]

            #Define IntelliFrame top flange lip angle from the horizon, in degrees.
            θ_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][9]

            #Apply Cee or Zee binary.   Assume the IntelliFrame behaves like a Z for this stiffness calculation.
            CorZ = 1

            #Calculate top flange + lip section properties.
            Af, Jf, Ixf, Iyf, Ixyf, Cwf, xof, hxf, hyf, yof = AISIS100.v16.table23131(CorZ, t_intelli_frame, b_top, d_top, θ_top)

            #Define the distance between fasteners as the distortional discrete bracing length.  There are no deck or fasteners in this case, so set Lm = length of purlin line.
            num_segments = size(intelli_frame_purlin_line.inputs.segments)[1]
            Lm = sum([intelli_frame_purlin_line.inputs.segments[i][1] for i = 1:num_segments])

            #Calculate the IntelliFrame distortional buckling half-wavelength.
            Lcrd, L = AISIS100.v16.app23334(ho, μ_intelli_frame, t_intelli_frame, Ixf, xof, hxf, Cwf, Ixyf, Iyf, Lm)

            rotational_stiffness = []

            shear_stiffness = []

            #Collect all the outputs.
            bracing_data[i] = PurlinLine.BracingData(0.0, rotational_stiffness, 0.0, 0.0, shear_stiffness, 0.0, Lcrd, Lm)

        end

    elseif intelli_frame_purlin_line.inputs.new_deck_details[1] == "vertical leg standing seam"  
        
        #There is no deck pullout stiffness needed here.
        kp = 0.0

        #Define the standing seam roof clip spacing.
        standing_seam_clip_spacing = intelli_frame_purlin_line.inputs.new_deck_details[2]

        #Define the standing seam roof clip height.
        # standing_seam_clip_height = intelli_frame_purlin_line.inputs.new_deck_details[3]

        #Define the distance between clips as the distortional discrete bracing length.
        Lm = standing_seam_clip_spacing

        # if standing_seam_clip_height == 2.25

            kϕ_standing_seam = 0.200  #From Seek et al. 2021, short floating clip, not exactly MR-24, kip-in/rad/in, https://www.researchgate.net/publication/349693825_Effective_standoff_in_standing_seam_roof_systems
            kx_standing_seam = 0.002  #From Cronin and Moen (2012), Figure 4.8  kips/in/in, https://vtechworks.lib.vt.edu/bitstream/handle/10919/18711/Flexural%20Capacity%20Prediction%20Method%20for%20an%20Open%20Web%20Joist%20Laterally%20Braced%20by%20a%20Standing%20Seam%20Roof%20System%20R10.pdf?sequence=1&isAllowed=y
        
        # end

        #Loop over all the Hugger+purlin segments in the line.  
        for i = 1:num_purlin_segments

            #Define the Hugger section property index associated with purlin segment i.
            section_index = intelli_frame_purlin_line.inputs.segments[i][4]

            #Define the Hugger material property index associated with purlin segment i.
            material_index = intelli_frame_purlin_line.inputs.segments[i][6]

            #Define the standing seam roof distributed clip stiffness.
            kϕ = kϕ_standing_seam

            #Define IntelliFrame steel Poisson's ratio.
            μ_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[material_index][2]

            #Define the IntelliFrame top flange width.
            b_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][3]

            #Define IntelliFrame base metal thickness.
            t_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][1]

            #Define out-to-out IntelliFrame web depth.
            ho = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][4]

            #Define IntelliFrame top flange lip length.
            d_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][2]

            #Define IntelliFrame top flange lip angle from the horizon, in degrees.
            θ_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][9]

            #Apply Cee or Zee binary.   Assume the IntelliFrame behaves like a Z for this stiffness calculation.
            CorZ = 1

            #Calculate the IntelliFrame distortional buckling half-wavelength.

            #Calculate top flange + lip section properties.
            Af, Jf, Ixf, Iyf, Ixyf, Cwf, xof,  hxf, hyf, yof = AISIS100.v16.table23131(CorZ, t_intelli_frame, b_top, d_top, θ_top)

            #Calculate the IntelliFrame distortional buckling half-wavelength.
            Lcrd, L = AISIS100.v16.app23334(ho, μ_intelli_frame, t_intelli_frame, Ixf, xof, hxf, Cwf, Ixyf, Iyf, Lm)

            #If Lcrd is longer than the fastener spacing, then the distortional buckling will be restrained by the deck.
            if Lcrd >= Lm
                kϕ_dist = kϕ
            else
                kϕ_dist = 0.0
            end

            #Define standing seam roof lateral stiffness.
            kx = kx_standing_seam

            rotational_stiffness = []

            shear_stiffness = []

            #Collect all the outputs.
            bracing_data[i] = PurlinLine.BracingData(kp, rotational_stiffness, kϕ, kϕ_dist, shear_stiffness, kx, Lcrd, Lm)

        end

    end

    return bracing_data

end


######
#This is for the existing deck once the Huggers have been attached to the purlins
function define_existing_deck_bracing_properties(purlin_line)

    num_purlin_segments = size(purlin_line.inputs.segments)[1]

    bracing_data = Array{PurlinLine.BracingData, 1}(undef, num_purlin_segments)

     #Define the deck to purlin screw-fastened connection spacing.
     deck_purlin_fastener_spacing = purlin_line.inputs.deck_details[3]

     #Define the deck to purlin screw diameter.
     deck_purlin_fastener_diameter = purlin_line.inputs.deck_details[4]

     #Define the nominal shear strength of the typical screw.
     Fss = purlin_line.inputs.deck_details[5]

     #Define the roof deck base metal thickness.
     t_roof_deck = purlin_line.inputs.deck_details[2]

     #Define roof deck steel elastic modulus.
     E_roof_deck = purlin_line.inputs.deck_material_properties[1]

     #Define roof deck steel ultimate yield stress.
     Fu_roof_deck = purlin_line.inputs.deck_material_properties[4]

     #Define the distance between fasteners as the distortional discrete bracing length.
     Lm = deck_purlin_fastener_spacing

     #Loop over all the purlin segments in the line.
     for i = 1:num_purlin_segments

         #Define the section property index associated with purlin segment i.
         section_index = purlin_line.inputs.segments[i][3]

         #Define the material property index associated with purlin segment i.
         material_index = purlin_line.inputs.segments[i][4]

         #Define purlin steel elastic modulus.
         E_purlin = purlin_line.inputs.material_properties[material_index][1]

         #Define purlin steel Poisson's ratio.
         μ_purlin = purlin_line.inputs.material_properties[material_index][2]

         #Define purlin steel ultimate stress.
         Fu_purlin = purlin_line.inputs.material_properties[material_index][4]

         #Define the purlin top flange width.
         b_top = purlin_line.inputs.cross_section_dimensions[section_index][6]

         #Define purlin base metal thickness.
         t_purlin = purlin_line.inputs.cross_section_dimensions[section_index][2]

         #Define out-to-out purlin web depth.
         ho = purlin_line.inputs.cross_section_dimensions[section_index][5]

         #Define purlin top flange lip length.
         d_top = purlin_line.inputs.cross_section_dimensions[section_index][7]

         #Define purlin top flange lip angle from the horizon, in degrees.
         θ_top = purlin_line.inputs.cross_section_dimensions[section_index][11] - purlin_line.inputs.cross_section_dimensions[section_index][12]

         #Define the location from the purlin top flange pivot point to the fastener.  Assume the fastener is centered in the flange.
         c = b_top/2

         #Define the deck fastener pull-through plate stiffness.  Assume the fastener is centered between two panel ribs.
         kp = PurlinLine.deck_pull_through_fastener_stiffness(purlin_line.inputs.deck_material_properties, b_top, t_roof_deck)

         #Apply Cee or Zee binary.
         if purlin_line.inputs.cross_section_dimensions[section_index][1] == "Z"
             CorZ = 1
         elseif purlin_line.inputs.cross_section_dimensions[section_index][1] == "C"
             CorZ = 0
         end

         #Calculate the rotational stiffness provided to the purlin by the screw-fastened connection between the deck and the purlin.  It is assumed that the deck flexural stiffness is much higher than the connection stiffness.
         rotational_stiffness = ScrewConnections.rotational_stiffness(b_top, c, deck_purlin_fastener_spacing, t_purlin, kp, E_purlin, purlin_line.inputs.cross_section_dimensions[section_index][1])

         #Calculate the purlin distortional buckling half-wavelength.

         #Calculate top flange + lip section properties.
         Af, Jf, Ixf, Iyf, Ixyf, Cwf, xof,  hxf, hyf, yof = AISIS100.v16.table23131(CorZ, t_purlin, b_top, d_top, θ_top)

         #Calculate the purlin distortional buckling half-wavelength.
         Lcrd, L = AISIS100.v16.app23334(ho, μ_purlin, t_purlin, Ixf, xof, hxf, Cwf, Ixyf, Iyf, Lm)

         #If Lcrd is longer than the fastener spacing, then the distortional buckling will be restrained by the deck.
         if Lcrd >= Lm
             kϕ_dist = rotational_stiffness.kϕ
         else
             kϕ_dist = 0.0
         end

         #Approximate the lateral stiffness provided to the top of the purlin by the screw-fastened connection between the deck and the purlin.

        #Calculate the stiffness of a single screw-fastened connection.
        α = 0.27  #for steel-to-steel, monotonic from Tao and Moen 2016 Table 8
        β = - 0.69  
        shear_stiffness = ScrewConnections.shear_stiffness(t_roof_deck, t_purlin, E_roof_deck, E_purlin, Fss, Fu_roof_deck, Fu_purlin, deck_purlin_fastener_diameter, α, β)

        #Convert the discrete stiffness to a distributed stiffness, divide by the fastener spacing.
        kx = shear_stiffness.Ke / deck_purlin_fastener_spacing

        #Collect all the outputs.
        bracing_data[i] = PurlinLine.BracingData(kp, rotational_stiffness, rotational_stiffness.kϕ, kϕ_dist, shear_stiffness, kx, Lcrd, Lm)


    end


    return bracing_data

end



######

function calculate_elastic_buckling_properties(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize vectors that will carry output.
    local_buckling_xx_pos = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    local_buckling_xx_neg = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    
    local_buckling_yy_pos = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    local_buckling_yy_neg = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    
    distortional_buckling_xx_pos = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    distortional_buckling_xx_neg = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
 
    #Loop over all the purlin segments in the line.
    for i = 1:num_purlin_segments

        
        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]
        hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][4]

        #Define the material property index associated with purlin segment i.
        material_index = intelli_frame_purlin_line.inputs.segments[i][5]
        
        #Map section properties to CUFSM.
        A = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.A
        xcg = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.xc
        zcg = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.yc
        Ixx = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.Ixx
        Izz = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.Iyy
        Ixz = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.Ixy
        thetap = rad2deg(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.θ)
        I11 = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.I1
        I22 = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.I2
        unsymm = 0  #Sets Ixz=0 if unsymm = 0

        #Define the number of cross-section nodes.
        num_cross_section_nodes = size(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].node_geometry)[1]

        #Initialize CUFSM node matrix.
        node = zeros(Float64, (num_cross_section_nodes, 8))

        #Add node numbers to node matrix.
        node[:, 1] .= 1:num_cross_section_nodes

        #Add nodal coordinates to node matrix.
        node[:, 2:3] .= intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].node_geometry

        #Add nodal restraints to node matrix.
        node[:, 4:7] .= ones(num_cross_section_nodes,4)

        #Define number of cross-section elements.
        num_cross_section_elements = size(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].element_definitions)[1]

        #Initialize CUFSM elem matrix.
        elem = zeros(Float64, (num_cross_section_elements, 5))

        #Add element numbers to elem matrix.
        elem[:, 1] = 1:num_cross_section_elements

        #Add element connectivity and thickness to elem matrix.
        elem[:, 2:4] .= intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].element_definitions

        #Add element material reference to elem matrix.
        elem[:, 5] .= ones(num_cross_section_elements) * 100
                                
        #Find the purlin top flange centerline node.
        #lip curve bottom_flange curve web curve top_flange
        center_top_flange_purlin_node = sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[1:3]) + sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius[1:3]) + floor(Int, intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[4]/2) + 1  #This floor command is a little dangerous.

        #Find the IntelliFrame top flange centerline node.
        num_purlin_nodes = size(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index ].node_geometry)[1]
        center_intelli_frame_flange_node = num_purlin_nodes + sum(intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n[1:2]) + sum(intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n_radius[1:2]) + floor(Int, intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n[3]/2) + 1
       
        #Set up springs in CUFSM.  There can be translational and rotational springs at the purlin top flange, and at the IntelliFrame top flange.
        springs = [1 center_top_flange_purlin_node 0 intelli_frame_purlin_line.bracing_data[i].kx 0 0 intelli_frame_purlin_line.bracing_data[i].kϕ_dist 0 0 0
                   2 center_intelli_frame_flange_node 0 intelli_frame_purlin_line.new_deck_bracing_data[i].kx 0 0 intelli_frame_purlin_line.new_deck_bracing_data[i].kϕ_dist 0 0 0]
        
        #Constrain the IntelliFrame bottom flange to the purlin top flange in all dof (x, z, y, and q).
        intelli_frame_bottom_flange_centerline_node = num_purlin_nodes + floor(Int, intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n[1] / 2) + 1
        
        #node#e DOFe coeff node#k DOFk
        constraints = [center_top_flange_purlin_node 1 1.0 intelli_frame_bottom_flange_centerline_node 1
                       center_top_flange_purlin_node 2 1.0 intelli_frame_bottom_flange_centerline_node 2
                       center_top_flange_purlin_node 3 1.0 intelli_frame_bottom_flange_centerline_node 3
                       center_top_flange_purlin_node 4 1.0 intelli_frame_bottom_flange_centerline_node 4]

        # constraints = 0

        #Assume here that purlin and IntelliFrame have the same elastic modulus.
        E = intelli_frame_purlin_line.inputs.purlin_material_properties[material_index][1]
        ν = intelli_frame_purlin_line.inputs.purlin_material_properties[material_index][2]
        G = E / (2 *(1 + ν))
        prop = [100 E E ν ν G]

        neigs = 1  #just need the first mode 

        ###Local buckling - xx axis, positive 

        #Add reference stress to node matrix.

        #Define reference loads.  
        P = 0.0
        Mxx = 1.0  #assume centroidal moment always for now
        Mzz = 0.0
        M11 = 0.0
        M22 = 0.0

        #Define the IntelliFrame flange width.
        b_top = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][4]  #this is a little dangerous
        length_inc = 5
        lengths = collect(0.25*b_top:0.75*b_top/length_inc:1.0*b_top)   #define to catch the local minimum

        CUFSM_local_xx_pos_data, Mcrℓ_xx_pos, Lcrℓ_xx_pos = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)   
        
        # mode_index = 4
        # shapes = CUFSM_local_xx_pos_data.shapes
        # scale_x = 1.0
        # scale_y = 1.0
        # # CUFSM.view_multi_branch_section_mode_shape(node, elem, shapes, mode_index, scale_x, scale_y)

        # half_wavelength = [curve[i,1][1] for i=1:length(lengths)]
        # load_factor = [curve[i,1][2] for i=1:length(lengths)]


        #Needed this deepcopy here to make struct work correctly.  Otherwise 'node' just kept changing.

        local_buckling_xx_pos[i] = PurlinLine.ElasticBucklingData(CUFSM_local_xx_pos_data, Lcrℓ_xx_pos, Mcrℓ_xx_pos)

        ###Local buckling - xx axis, negative 

        #Add reference stress to node matrix.

        #Define reference loads.  
        P = 0.0
        Mxx = -1.0  #assume centroidal moment always for now
        Mzz = 0.0
        M11 = 0.0
        M22 = 0.0

        #Use purlin web depth here.
        h = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][5]  #this is a little dangerous
        length_inc = 5
        lengths = collect(0.25*h:0.75*h/length_inc:1.0*h)   #define to catch the local minimum

        CUFSM_local_xx_neg_data, Mcrℓ_xx_neg, Lcrℓ_xx_neg = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)

        local_buckling_xx_neg[i] = PurlinLine.ElasticBucklingData(CUFSM_local_xx_neg_data, Lcrℓ_xx_neg, Mcrℓ_xx_neg)


        ###local buckling - yy axis, positive  (compression at tip of purlin bottom flange lip)
        
        #Define reference loads.  
        P = 0.0
        Mxx = 0.0  
        Mzz = 1.0  #assume centroidal moment always for now
        M11 = 0.0
        M22 = 0.0

        #Try Lcrd of the purlin as a guide for finding the half-wavelength of the flange and lip (unstiffened element).
        #It turns out that for the case I studied, the purlin web buckled, not the purlin bottom flange lip.  Makes sense I guess.
        length_inc = 5
        lengths = collect(0.25 * intelli_frame_purlin_line.bracing_data[i].Lcrd:(1.0 * intelli_frame_purlin_line.bracing_data[i].Lcrd)/length_inc:1.25 * intelli_frame_purlin_line.bracing_data[i].Lcrd)   #define to catch the local minimum

        CUFSM_local_yy_pos_data, Mcrℓ_yy_pos, Lcrℓ_yy_pos = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)

    #                 mode_index = 3
    # shapes = CUFSM_local_yy_pos_data.shapes
    # scale_x = 1.0
    # scale_y = 1.0
    # CUFSM.view_multi_branch_section_mode_shape(node, elem, shapes, mode_index, scale_x, scale_y)


        local_buckling_yy_pos[i] = PurlinLine.ElasticBucklingData(CUFSM_local_yy_pos_data, Lcrℓ_yy_pos, Mcrℓ_yy_pos)
  
        ###local buckling - yy axis, negative  (compression in IntelliFrame top flange lip)
        
        #Define reference loads.  
        P = 0.0
        Mxx = 0.0  
        Mzz = -1.0  #assume centroidal moment always for now
        M11 = 0.0
        M22 = 0.0
    
        length_inc = 5
        #Try Lcrd of the IntelliFrame as a guide for finding the half-wavelength of the flange and lip (unstiffened element).
        lengths = collect(0.25 * intelli_frame_purlin_line.new_deck_bracing_data[i].Lcrd:(1.0 * intelli_frame_purlin_line.new_deck_bracing_data[i].Lcrd)/length_inc:1.25 * intelli_frame_purlin_line.new_deck_bracing_data[i].Lcrd)   #define to catch the local minimum

        CUFSM_local_yy_neg_data, Mcrℓ_yy_neg, Lcrℓ_yy_neg = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)

        local_buckling_yy_neg[i] = PurlinLine.ElasticBucklingData(CUFSM_local_yy_neg_data, Lcrℓ_yy_neg, Mcrℓ_yy_neg)

        ###Distortional buckling - xx axis, positive

        #Define reference loads.  
        P = 0.0
        Mxx = 1.0  #assume centroidal moment always for now
        Mzz = 0.0
        M11 = 0.0
        M22 = 0.0

        length_inc = 5
        #Use IntelliFrame Lcrd here.
        lengths = collect(0.75 * intelli_frame_purlin_line.new_deck_bracing_data[i].Lcrd:(0.50 * intelli_frame_purlin_line.new_deck_bracing_data[i].Lcrd)/length_inc:1.25 * intelli_frame_purlin_line.new_deck_bracing_data[i].Lcrd)  #define to catch distortional minimum

        CUFSM_dist_pos_data, Mcrd_pos, Lcrd_pos_CUFSM = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)

        distortional_buckling_xx_pos[i] = PurlinLine.ElasticBucklingData(CUFSM_dist_pos_data, Lcrd_pos_CUFSM, Mcrd_pos)


 

         ###Distortional buckling - xx axis, negative

        #Define reference loads.  
        P = 0.0
        Mxx = -1.0  #assume centroidal moment always for now
        Mzz = 0.0
        M11 = 0.0
        M22 = 0.0

        length_inc = 5
        #Use purlin Lcrd here.
        lengths = collect(0.75 * intelli_frame_purlin_line.bracing_data[i].Lcrd:(0.50 * intelli_frame_purlin_line.bracing_data[i].Lcrd)/length_inc:1.25 * intelli_frame_purlin_line.bracing_data[i].Lcrd)  #define to catch distortional minimum

        CUFSM_dist_neg_data, Mcrd_neg, Lcrd_neg_CUFSM = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)

        distortional_buckling_xx_neg[i] = PurlinLine.ElasticBucklingData(CUFSM_dist_neg_data, Lcrd_neg_CUFSM, Mcrd_neg)

    end

    return local_buckling_xx_pos, local_buckling_xx_neg, local_buckling_yy_pos, local_buckling_yy_neg, distortional_buckling_xx_pos, distortional_buckling_xx_neg


end


function generate_intelli_frame_net_section_purlin_geometry(intelli_frame_purlin_cross_section_data, intelli_frame_cross_section_data, purlin_cross_section_data, purlin_cross_section_dimensions, intelli_frame_punch_out_dimensions)

    num_purlin_nodes = size(purlin_cross_section_data.node_geometry)[1]

    #Find all cross-section nodes that are in the IntelliFrame punchout region.
    intelli_frame_node_geometry = intelli_frame_cross_section_data.node_geometry[:,1:2]

    #Find all the nodes lower than the punchout.
    hole_index_y = findall(x->x<intelli_frame_punch_out_dimensions[2], intelli_frame_node_geometry[:,2])

    #Restrict to the bottom flange, bottom corner and web (node order: bottom flange, corner, web, corner, top flange, lip),
    #so that a lip dipping below the punchout height is never picked up. This does not depend on which way the
    #IntelliFrame faces on the purlin.
    intelli_frame_web_top_node = intelli_frame_cross_section_data.n[1] + intelli_frame_cross_section_data.n_radius[1] + intelli_frame_cross_section_data.n[2] + 1
    hole_index_x = collect(1:intelli_frame_web_top_node)

    #These are the nodes to be removed
    hole_index = sort(intersect(hole_index_y, hole_index_x))

    #Shift the cross-section node to match up with the punch out dimensions.
    h_purlin = purlin_cross_section_dimensions[5]
    intelli_frame_purlin_node_geometry = intelli_frame_purlin_cross_section_data.node_geometry[:,1:2]
    intelli_frame_purlin_node_geometry[hole_index[end] + num_purlin_nodes, 2] =  h_purlin + intelli_frame_punch_out_dimensions[2]


    #These are the nodes within the punchout region.
    remove_hole_nodes_index = hole_index[1:(end-1)] .+ num_purlin_nodes
    intelli_frame_purlin_node_geometry = intelli_frame_purlin_node_geometry[setdiff(1:end, remove_hole_nodes_index), :]

    #Remove elements in punchout region.
    intelli_frame_purlin_element_definitions = intelli_frame_purlin_cross_section_data.element_definitions
    remove_hole_elements_index = hole_index[1:end-1] .+ num_purlin_nodes .- 1

    intelli_frame_purlin_element_definitions = intelli_frame_purlin_element_definitions[setdiff(1:end, remove_hole_elements_index), :]

    #Update nodal connectivity.
    update_index = remove_hole_elements_index[1]
    num_removed_elements = length(remove_hole_elements_index)

    intelli_frame_purlin_element_definitions[update_index:end, 1:2] = intelli_frame_purlin_element_definitions[update_index:end, 1:2] .- num_removed_elements

    return intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions

end


function define_intelli_frame_purlin_net_section(segments, purlin_cross_section_dimensions, intelli_frame_cross_section_data, intelli_frame_plastic_cross_section_data, purlin_cross_section_data, purlin_plastic_cross_section_data, intelli_frame_purlin_cross_section_data, intelli_frame_purlin_plastic_cross_section_data, intelli_frame_punch_out_dimensions)
    
    num_hugger_purlin_sections = size(segments)[1]

    cross_section_data = Vector{PurlinLine.CrossSectionData}(undef, num_hugger_purlin_sections)

    for i=1:num_hugger_purlin_sections

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

        purlin_section_index = segments[i][3]
        hugger_section_index = segments[i][4]
        hugger_punchout_index = segments[i][7]
        
        intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions = generate_intelli_frame_net_section_purlin_geometry(intelli_frame_purlin_cross_section_data[i], intelli_frame_cross_section_data[hugger_section_index], purlin_cross_section_data[purlin_section_index], purlin_cross_section_dimensions[purlin_section_index],intelli_frame_punch_out_dimensions[hugger_punchout_index])

        #Calculate section properties of net section at a IntelliFrame punchout.
        section_properties = CUFSM.cutwp_prop2(intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions)
    

        #Calculate IntelliFrame+purlin plastic neutral axis and plastic modulus at the punchout net section.
        intelli_frame_purlin_plastic_node_geometry, intelli_frame_purlin_plastic_element_definitions = generate_intelli_frame_net_section_purlin_geometry(intelli_frame_purlin_plastic_cross_section_data[i], intelli_frame_plastic_cross_section_data[hugger_section_index], purlin_plastic_cross_section_data[purlin_section_index], purlin_cross_section_dimensions[purlin_section_index], intelli_frame_punch_out_dimensions[hugger_punchout_index])

        about_axis = "x"  #The strong axis plastic properties are needed for now.  
        intelli_frame_purlin_plastic_section_properties = SectionProperties.calculate_plastic_section_properties(intelli_frame_purlin_plastic_node_geometry, intelli_frame_purlin_plastic_element_definitions, about_axis)

        #Add cross section information to data structure.
        cross_section_data[i] = PurlinLine.CrossSectionData(intelli_frame_purlin_cross_section_data[i].n, intelli_frame_purlin_cross_section_data[i].n_radius, intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions, section_properties, intelli_frame_purlin_plastic_section_properties)

    end

    return cross_section_data

end



function calculate_net_section_local_buckling_properties(intelli_frame_purlin_line)
        
    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize vectors that will carry output.
    local_buckling_xx_net_pos = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    
    	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


    #Loop over all the purlin segments in the line.
    for i = 1:num_purlin_segments

        # #Define the section property index associated with purlin segment i.
        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]

        #Define the material property index associated with purlin segment i.
        material_index = intelli_frame_purlin_line.inputs.segments[i][5]

        hugger_punchout_index = intelli_frame_purlin_line.inputs.segments[i][7]


        
        #Map section properties to CUFSM.
        A = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.A
        xcg = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.xc
        zcg = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.yc
        Ixx = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.Ixx
        Izz = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.Iyy
        Ixz = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.Ixy
        thetap = rad2deg(intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.θ)
        I11 = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.I1
        I22 = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.I2
        unsymm = 0  #Sets Ixz=0 if unsymm = 0

        #Define the number of cross-section nodes.
        num_cross_section_nodes = size(intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].node_geometry)[1]

        #Initialize CUFSM node matrix.
        node = zeros(Float64, (num_cross_section_nodes, 8))

        #Add node numbers to node matrix.
        node[:, 1] .= 1:num_cross_section_nodes

        #Add nodal coordinates to node matrix.
        node[:, 2:3] .= intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].node_geometry

        #Add nodal restraints to node matrix.
        node[:, 4:7] .= ones(num_cross_section_nodes,4)

        #Define number of cross-section elements.
        num_cross_section_elements = size(intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].element_definitions)[1]

        #Initialize CUFSM elem matrix.
        elem = zeros(Float64, (num_cross_section_elements, 5))

        #Add element numbers to elem matrix.
        elem[:, 1] = 1:num_cross_section_elements

        #Add element connectivity and thickness to elem matrix.
        elem[:, 2:4] .= intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].element_definitions

        #Add element material reference to elem matrix.
        elem[:, 5] .= ones(num_cross_section_elements) * 100
                                
        #Find the purlin top flange centerline node.
        #lip curve bottom_flange curve web curve top_flange
        center_top_flange_purlin_node =  sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[1:3]) + sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius[1:3]) + floor(Int, intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[4]/2) + 1  #This floor command is a little dangerous.

        #Find the IntelliFrame top flange centerline nodes.
        num_intelli_frame_purlin_nodes = size(intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].node_geometry)[1]
        center_intelli_frame_flange_node = num_intelli_frame_purlin_nodes -  intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].n[end] - intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].n_radius[end] - floor(Int, intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].n[end-1]/2)

        #Set up springs in CUFSM.  There can be translational and rotational springs at the purlin top flange, and at the IntelliFrame top flange.
        springs = [1 center_top_flange_purlin_node 0 intelli_frame_purlin_line.bracing_data[i].kx 0 0 intelli_frame_purlin_line.bracing_data[i].kϕ_dist 0 0 0
        2 center_intelli_frame_flange_node 0 intelli_frame_purlin_line.new_deck_bracing_data[i].kx 0 0 intelli_frame_purlin_line.new_deck_bracing_data[i].kϕ_dist 0 0 0]


        constraints = 0

        #Assume here that purlin and IntelliFrame have the same elastic modulus.
        E = intelli_frame_purlin_line.inputs.purlin_material_properties[material_index][1]
        ν = intelli_frame_purlin_line.inputs.purlin_material_properties[material_index][2]
        G = E / (2 *(1 + ν))
        prop = [100 E E ν ν G]

        neigs = 1  #just need the first mode 

        ###Local buckling - xx axis, positive 

        #Add reference stress to node matrix.

        #Define reference loads.  
        P = 0.0
        Mxx = 1.0  #assume centroidal moment always for now
        Mzz = 0.0
        M11 = 0.0
        M22 = 0.0

        #Define the length of the punchout.
        L_hole = intelli_frame_purlin_line.inputs.intelli_frame_punch_out_dimensions[hugger_punchout_index][1]  

        #Assume the buckling half-wavelength is longer than IntelliFrame punchout.  This seems reasonable based on wavelength studies where the mininum was around 15 in. for the net section IntelliFrame + purlin model.  
        lengths = [L_hole]

        # node_with_stress = CUFSM.stresgen(node,P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)

        # #Now delete the purlin nodes and elements.  CUFSM for sure gives a good answer here for the local buckling net section analysis.  Otherwise with discontinous members (IntelliFrame and purlin) the results were weird and inconsistent, also if t=0 set for the elements in the punchout.

        # num_purlin_nodes = sum(intelli_frame_purlin_line.purlin_cross_section_data[i].n) + sum(intelli_frame_purlin_line.purlin_cross_section_data[i].n_radius) + 1

        # #Remove purlin nodes.
        # node_with_stress = node_with_stress[num_purlin_nodes + 1: end, :]

        # #Update node numbers.
        # num_nodes = size(node_with_stress)[1]
        # node_with_stress[:,1] .= 1:num_nodes

        # #Remove element numbers.
        # num_purlin_elem = sum(intelli_frame_purlin_line.purlin_cross_section_data[i].n) + sum(intelli_frame_purlin_line.purlin_cross_section_data[i].n_radius)
        # elem = elem[num_purlin_elem + 1:end, :]

        # #Update element numbers.
        # num_elem = size(elem)[1]
        # elem[:, 1] .= 1:num_elem
        # elem[:, 2] .= 1:num_nodes-1
        # elem[:, 3] .= 2:num_nodes

        # curve, shapes = CUFSM.strip(prop, node_with_stress, elem, lengths, springs, constraints, neigs)

        # CUFSM_local_xx_net_pos_data = CUFSM.data(prop, node_with_stress, elem, lengths, springs, constraints, neigs, curve, shapes)

        # half_wavelength = [curve[i,1][1] for i=1:length(lengths)]
        # load_factor = [curve[i,1][2] for i=1:length(lengths)]

        # Mcrℓ_xx_net_pos = minimum(load_factor)

        # min_index = findfirst(x->x==minimum(load_factor), load_factor)    

        # Lcrℓ_xx_net_pos = half_wavelength[min_index]

        ###########

        CUFSM_local_xx_net_pos_data, Mcrℓ_xx_net_pos, Lcrℓ_xx_net_pos = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)   

        #Needed this deepcopy here to make struct work correctly.  Otherwise 'node' just kept changing.

        local_buckling_xx_net_pos[i] = PurlinLine.ElasticBucklingData(CUFSM_local_xx_net_pos_data, Lcrℓ_xx_net_pos, Mcrℓ_xx_net_pos)

    end

    return local_buckling_xx_net_pos

end


function calculate_yielding_flexural_strength(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize a vectors that will hold all the outputs.
    yielding_flexural_strength_xx = Array{PurlinLine.YieldingFlexuralStrengthData, 1}(undef, num_purlin_segments)
    yielding_flexural_strength_xx_net = Array{PurlinLine.YieldingFlexuralStrengthData, 1}(undef, num_purlin_segments)
    yielding_flexural_strength_yy = Array{PurlinLine.YieldingFlexuralStrengthData, 1}(undef, num_purlin_segments)
    yielding_flexural_strength_free_flange_yy = Array{PurlinLine.YieldingFlexuralStrengthData, 1}(undef, num_purlin_segments)


    for i = 1:num_purlin_segments

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]
        hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][4]

        #Define the material property index associated with purlin segment i.
        purlin_material_index = intelli_frame_purlin_line.inputs.segments[i][5]

        hugger_material_index = intelli_frame_purlin_line.inputs.segments[i][6]

        ###strong axis flexure, local-global interaction
        Fy_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][3]
        Fy_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][3]
        Ixx = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.Ixx
        cy_bottom = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.yc  #distance from neutral axis to bottom outer fiber

        intelli_frame_purlin_depth = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][3] + intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[hugger_section_index][5]
        cy_top = intelli_frame_purlin_depth - cy_bottom #distance from neutral axis to top outer fiber
        Sxx_pos = Ixx/cy_top
        Sxx_neg = Ixx/cy_bottom
        My_xx_pos = Fy_intelli_frame * Sxx_pos #IntelliFrame at top fiber
        My_xx_neg = Fy_purlin * Sxx_neg  #purlin is at bottom fiber
        My_xx = minimum([My_xx_pos My_xx_neg])  #first yield criterion for AISI 

        yielding_flexural_strength_xx[i] = PurlinLine.YieldingFlexuralStrengthData(Sxx_pos, Sxx_neg, My_xx_pos, My_xx_neg, My_xx, 0.0)   #make eMy zero here since it is not used

        ###strong axis flexure, local-global interaction, net section at a punchout
        Ixx_net = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.Ixx
        cy_bottom_net = intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].section_properties.yc  #distance from neutral axis to bottom outer fiber

        cy_top_net = intelli_frame_purlin_depth - cy_bottom_net #distance from neutral axis to top outer fiber
        Sxx_pos_net = Ixx_net/cy_top_net
        Sxx_neg_net = Ixx_net/cy_bottom_net
        My_xx_pos_net = Fy_intelli_frame * Sxx_pos_net #IntelliFrame at top fiber
        My_xx_neg_net = Fy_purlin * Sxx_neg_net  #purlin is at bottom fiber
        My_xx_net = minimum([My_xx_pos_net My_xx_neg_net])  #first yield criterion for AISI 

        yielding_flexural_strength_xx_net[i] = PurlinLine.YieldingFlexuralStrengthData(Sxx_pos_net, Sxx_neg_net, My_xx_pos_net, My_xx_neg_net, My_xx_net, 0.0)   #make eMy zero here since it is not used


        ###weak axis flexure, local-global interaction
        Iyy = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.Iyy

        #distance from neutral axis to (-x or left) outer fiber
        #Positive moment is applied when this outer fiber is compressed.
        cx_minusx = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.xc - minimum(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].node_geometry[:,1])
        #distance from neutral axis to (+x or right) outer fiber
        #Negative moment is applied when this outer fiber is compressed.
        cx_plusx = maximum(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].node_geometry[:,1]) - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.xc 
 
        Syy_pos = Iyy / cx_minusx
        Syy_neg = Iyy / cx_plusx
 
        #Yield stress of whichever part owns each outer fiber (the purlin nodes come first in the combined geometry).
        num_purlin_nodes = size(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].node_geometry, 1)
        xcoords = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].node_geometry[:, 1]
        Fy_minusx = argmin(xcoords) <= num_purlin_nodes ? Fy_purlin : Fy_intelli_frame
        Fy_plusx  = argmax(xcoords) <= num_purlin_nodes ? Fy_purlin : Fy_intelli_frame

        My_yy_pos = Fy_minusx * Syy_pos
        My_yy_neg = Fy_plusx * Syy_neg
        My_yy = minimum([My_yy_pos My_yy_neg])  #first yield criterion for AISI 
 
        yielding_flexural_strength_yy[i] = PurlinLine.YieldingFlexuralStrengthData(Syy_pos, Syy_neg, My_yy_pos, My_yy_neg, My_yy, 0.0)  #set eMy=0.0 for now

        ###free flange yy-axis, local-global interaction

        #define free flange properties
        Iyyf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.Iyy

        #distance from neutral axis to (-x or left) outer fiber
        #Positive moment is applied when this outer fiber is compressed.
        cxf_minusx = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.xc - minimum(intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].node_geometry[:,1])
        #distance from neutral axis to (+x or right) outer fiber
        #Negative moment is applied when this outer fiber is compressed.
        cxf_plusx = maximum(intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].node_geometry[:,1]) - intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.xc 

        Syy_pos_free_flange = Iyyf / cxf_minusx
        Syy_neg_free_flange = Iyyf / cxf_plusx

        My_yy_pos_free_flange = Fy_purlin * Syy_pos_free_flange
        My_yy_neg_free_flange = Fy_purlin * Syy_neg_free_flange
        My_yy_free_flange = minimum([My_yy_pos_free_flange My_yy_neg_free_flange])  #first yield criterion for AISI 

        #Factored yield moment is needed for the free flange to perform AISI interaction checks.

        # if intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 ASD"
        #     ASDorLRFD = 0
        # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 LRFD"
        #     ASDorLRFD = 1
        # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 nominal"
        #     ASDorLRFD = 2
        # end

        Mcrℓ_yy_free_flange = 10.0^10 #Make this a big number so we just get back eMy
        My_yy_free_flange, eMy_yy_free_flange = AISIS100.v16.f321(My_yy_free_flange, Mcrℓ_yy_free_flange, intelli_frame_purlin_line.inputs.design_code)

        yielding_flexural_strength_free_flange_yy[i] = PurlinLine.YieldingFlexuralStrengthData(Syy_pos_free_flange, Syy_neg_free_flange, My_yy_pos_free_flange, My_yy_neg_free_flange, My_yy_free_flange, eMy_yy_free_flange)

    end

    return yielding_flexural_strength_xx, yielding_flexural_strength_xx_net, yielding_flexural_strength_yy, yielding_flexural_strength_free_flange_yy

end


function calculate_local_global_flexural_strength(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize a vectors that will hold all the outputs.
    local_global_flexural_strength_xx_no_hole = Array{PurlinLine.LocalGlobalFlexuralStrengthData, 1}(undef, num_purlin_segments)
    local_global_flexural_strength_xx_hole = Array{PurlinLine.LocalGlobalFlexuralStrengthData, 1}(undef, num_purlin_segments)
    local_global_flexural_strength_xx = Array{PurlinLine.LocalGlobalFlexuralStrengthData, 1}(undef, num_purlin_segments)
    local_global_flexural_strength_yy = Array{PurlinLine.LocalGlobalFlexuralStrengthData, 1}(undef, num_purlin_segments)
    local_global_flexural_strength_free_flange_yy = Array{PurlinLine.LocalGlobalFlexuralStrengthData, 1}(undef, num_purlin_segments)


    # if intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 ASD"
    #     ASDorLRFD = 0
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 LRFD"
    #     ASDorLRFD = 1
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 nominal"
    #     ASDorLRFD = 2
    # end

    for i = 1:num_purlin_segments

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


        # section_index = intelli_frame_purlin_line.inputs.segments[i][2]
        purlin_material_index = intelli_frame_purlin_line.inputs.segments[i][5]
        hugger_material_index = intelli_frame_purlin_line.inputs.segments[i][6]

        #Set Mne=My and handle global buckling with second order analysis.
        Mne_xx = intelli_frame_purlin_line.yielding_flexural_strength_xx[i].My  

        ###Work on positive flexure. Define Mnℓ as the mininum of [Mnℓ_no_hole, Mnℓ_hole] as suggested in AISI S100-16.
        
        #Start with section away from punchout.   Consider inelastic reserve.

        Mcrℓ_pos_no_hole = intelli_frame_purlin_line.local_buckling_xx_pos[i].Mcr

        λ_ℓ_pos_no_hole = sqrt(Mne_xx/Mcrℓ_pos_no_hole)

        if λ_ℓ_pos_no_hole < 0.776   #inelastic reserve is in play

            Sc = intelli_frame_purlin_line.yielding_flexural_strength_xx[i].S_pos
            St = intelli_frame_purlin_line.yielding_flexural_strength_xx[i].S_neg
            Z =  intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].plastic_section_properties.Z
            Fy_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][3]
            Fy_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][3]
            Fy = minimum([Fy_intelli_frame, Fy_purlin])  #take the minimum for now, can improve later
            lambda_l, Cyl, Mp, Myc, Myt3, Mnℓ_xx_pos_no_hole, eMnℓ_xx_pos_no_hole = AISIS100.v16.f323(Mne_xx, Mcrℓ_pos_no_hole, Sc, St, Z, Fy, intelli_frame_purlin_line.inputs.design_code)

        else

            Mnℓ_xx_pos_no_hole, eMnℓ_xx_pos_no_hole =  AISIS100.v16.f321(Mne_xx, Mcrℓ_pos_no_hole, intelli_frame_purlin_line.inputs.design_code)
        
        end

        #Now work on section at a punchout. Consider inelastic reserve.

        #Define Mnℓ as the mininum of [Mnℓ_no_hole, Mnℓ_hole] as suggested in AISI S100-16.
        My_net = intelli_frame_purlin_line.yielding_flexural_strength_xx_net[i].My
        Mcrℓ_pos_hole = intelli_frame_purlin_line.local_buckling_xx_net_pos[i].Mcr
    
        λ_ℓ_pos_hole = sqrt(Mne_xx/Mcrℓ_pos_hole)

        if λ_ℓ_pos_hole < 0.776   #inelastic reserve is in play

            Sc = intelli_frame_purlin_line.yielding_flexural_strength_xx_net[i].S_pos
            St = intelli_frame_purlin_line.yielding_flexural_strength_xx_net[i].S_neg
            Z =  intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data[i].plastic_section_properties.Z
            Fy_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][3]
            Fy_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][3]
            Fy = minimum([Fy_intelli_frame, Fy_purlin])  #take the minimum for now, can improve later
            lambda_l, Cyl, Mp, Myc, Myt3, Mnℓ_xx_pos_hole, eMnℓ_xx_pos_hole = AISIS100.v16.f323(My_net, Mcrℓ_pos_hole, Sc, St, Z, Fy, intelli_frame_purlin_line.inputs.design_code)

        else

            Mnℓ_xx_pos_hole, eMnℓ_xx_pos_hole =  AISIS100.v16.f322(Mne_xx, Mcrℓ_pos_hole, My_net, intelli_frame_purlin_line.inputs.design_code)
        
        end

        Mnℓ_xx_pos = minimum([Mnℓ_xx_pos_no_hole, Mnℓ_xx_pos_hole])
        eMnℓ_xx_pos = minimum([eMnℓ_xx_pos_no_hole, eMnℓ_xx_pos_hole])

        ##### Now negative flexure.

        #Define Mnℓ as the mininum of [Mnℓ_no_hole, Mnℓ_hole] as suggested in AISI S100-16.
        Mcrℓ_neg_no_hole = intelli_frame_purlin_line.local_buckling_xx_neg[i].Mcr

        λ_ℓ_neg_no_hole = sqrt(Mne_xx/Mcrℓ_neg_no_hole)

        if λ_ℓ_neg_no_hole < 0.776   #inelastic reserve is in play

            Sc = intelli_frame_purlin_line.yielding_flexural_strength_xx[i].S_neg
            St = intelli_frame_purlin_line.yielding_flexural_strength_xx[i].S_pos
            Z =  intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].plastic_section_properties.Z
            Fy_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][3]
            Fy_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][3]
            Fy = minimum([Fy_intelli_frame, Fy_purlin])  #take the minimum for now, can improve later
            lambda_l, Cyl, Mp, Myc, Myt3, Mnℓ_xx_neg_no_hole, eMnℓ_xx_neg_no_hole = AISIS100.v16.f323(Mne_xx, Mcrℓ_neg_no_hole, Sc, St, Z, Fy, intelli_frame_purlin_line.inputs.design_code)

        else

            Mnℓ_xx_neg_no_hole, eMnℓ_xx_neg_no_hole =  AISIS100.v16.f321(Mne_xx, Mcrℓ_neg_no_hole, intelli_frame_purlin_line.inputs.design_code)
        
        end
        
        #At a IntelliFrame punchout, net section yielding is the upper limit for negative flexure.  
        Mnℓ_xx_neg_hole, eMnℓ_xx_neg_hole =  AISIS100.v16.f322(Mne_xx, Mcrℓ_neg_no_hole, My_net, intelli_frame_purlin_line.inputs.design_code)

        #Find the minimum of the strengths at the punchout or away from the punchout.
        Mnℓ_xx_neg = minimum([Mnℓ_xx_neg_no_hole, Mnℓ_xx_neg_hole])
        eMnℓ_xx_neg = minimum([eMnℓ_xx_neg_no_hole, eMnℓ_xx_neg_hole])


        #Add no hole positive and negative flexural strength to data structure. 
        local_global_flexural_strength_xx_no_hole[i] = PurlinLine.LocalGlobalFlexuralStrengthData(Mne_xx, Mnℓ_xx_pos_no_hole, Mnℓ_xx_neg_no_hole, eMnℓ_xx_pos_no_hole, eMnℓ_xx_neg_no_hole)

        #Add net section positive and negative flexural strength to data structure. 
        local_global_flexural_strength_xx_hole[i] = PurlinLine.LocalGlobalFlexuralStrengthData(My_net, Mnℓ_xx_pos_hole, Mnℓ_xx_neg_hole, eMnℓ_xx_pos_hole, eMnℓ_xx_neg_hole)  

        #Add the governing (hole or no hole) positive and negative strong xx flexural strengths to the data structure.
        local_global_flexural_strength_xx[i] = PurlinLine.LocalGlobalFlexuralStrengthData(Mne_xx, Mnℓ_xx_pos, Mnℓ_xx_neg, eMnℓ_xx_pos, eMnℓ_xx_neg)

        ###weak axis flexure, local-global interaction
        Mne_yy = intelli_frame_purlin_line.yielding_flexural_strength_yy[i].My

        Mnℓ_yy_pos, eMnℓ_yy_pos = AISIS100.v16.f321(Mne_yy, intelli_frame_purlin_line.local_buckling_yy_pos[i].Mcr, intelli_frame_purlin_line.inputs.design_code)

        Mnℓ_yy_neg, eMnℓ_yy_neg = AISIS100.v16.f321(Mne_yy, intelli_frame_purlin_line.local_buckling_yy_neg[i].Mcr, intelli_frame_purlin_line.inputs.design_code)

        local_global_flexural_strength_yy[i] = PurlinLine.LocalGlobalFlexuralStrengthData(Mne_yy, Mnℓ_yy_pos, Mnℓ_yy_neg, eMnℓ_yy_pos, eMnℓ_yy_neg)


        ###free flange yy-axis, local-global interaction
        Mne_yy_free_flange = intelli_frame_purlin_line.yielding_flexural_strength_free_flange_yy[i].My 

        #Assume no local buckling for now in the free flange strength calculation.  Set Mcrℓ to Mne times a big number. 

        Mnℓ_yy_pos_free_flange, eMnℓ_yy_pos_free_flange = AISIS100.v16.f321(Mne_yy_free_flange, Mne_yy_free_flange * 1000, intelli_frame_purlin_line.inputs.design_code)

        Mnℓ_yy_neg_free_flange, eMnℓ_yy_neg_free_flange = AISIS100.v16.f321(Mne_yy_free_flange, Mne_yy_free_flange * 1000, intelli_frame_purlin_line.inputs.design_code)

        local_global_flexural_strength_free_flange_yy[i] = PurlinLine.LocalGlobalFlexuralStrengthData(Mne_yy_free_flange, Mnℓ_yy_pos_free_flange, Mnℓ_yy_neg_free_flange, eMnℓ_yy_pos_free_flange, eMnℓ_yy_neg_free_flange)

    end

    return local_global_flexural_strength_xx_no_hole, local_global_flexural_strength_xx_hole,local_global_flexural_strength_xx, local_global_flexural_strength_yy, local_global_flexural_strength_free_flange_yy

end



function define_intelli_frame_purlin_distortional_net_section(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    cross_section_data = Vector{PurlinLine.CrossSectionData}(undef, num_purlin_segments)

    	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


    for i=1:num_purlin_segments

        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]
        hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][4]
        
        hugger_punchout_index = intelli_frame_purlin_line.inputs.segments[i][7]

        #Define length of IntelliFrame punchout.
        L_hole = intelli_frame_purlin_line.inputs.intelli_frame_punch_out_dimensions[hugger_punchout_index][1]

        ##Find all cross-section nodes that are in the IntelliFrame web.
        intelli_frame_purlin_node_geometry = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].node_geometry[:,1:2]

        #Define the x range for the IntelliFrame webs.

        #Work from the purlin top flange centerline.
        center_top_flange_purlin_node =  sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[1:3]) + sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius[1:3]) + floor(Int, intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[4]/2) + 1  

        #Define the IntelliFrame bottom flange width.
        intelli_frame_bottom_flange_width = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][2]

        #Define the IntelliFrame base metal thickness.
        t_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][1]

        #Define the IntelliFrame x web coordinate.
        intelli_frame_web_x_index = sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n) + 1 + sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius) + intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[1] + intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius[1] + floor(Int, intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[2]) 

        intelli_frame_web_x = intelli_frame_purlin_node_geometry[ intelli_frame_web_x_index ,1]
        
        # intelli_frame_web_x = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[section_index].node_geometry[center_top_flange_purlin_node, 1] + intelli_frame_bottom_flange_width/2 + t_intelli_frame   #check this

        web_index = findall(x->x≈intelli_frame_web_x, intelli_frame_purlin_node_geometry[:,1])

        #Approximate the Lcrd for each cross-section.   
        Lcrd = intelli_frame_purlin_line.distortional_buckling_xx_pos[i].Lcr
        tr = AISIS100.v16.app2C2262(t_intelli_frame, L_hole, Lcrd)

        #Define element definitions.
        intelli_frame_purlin_element_definitions = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].element_definitions

        #Define the element ranges where t becomes tr.
        web_element_index = [web_index[1] - 2; web_index[1] - 1; web_index[1:(end-1)]]

        #Update the element thicknesses in the IntelliFrame.
        intelli_frame_purlin_element_definitions[web_element_index, 3] .= tr

        #Calculate section properties of section with reduced web thickness.
        section_properties = CUFSM.cutwp_prop2(intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions)

        #Add cross section information to data structure.
        cross_section_data[i] = PurlinLine.CrossSectionData(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].n, intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].n_radius, intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions, section_properties, nothing)

    end

    return cross_section_data

end




function calculate_net_section_distortional_buckling_properties(intelli_frame_purlin_line)
        
    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize vectors that will carry output.
    distortional_buckling_xx_net_pos = Array{PurlinLine.ElasticBucklingData, 1}(undef, num_purlin_segments)
    
    #Loop over all the purlin segments in the line.
    for i = 1:num_purlin_segments

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]
        hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][4]

        #Define the material property index associated with purlin segment i.
        purlin_material_index = intelli_frame_purlin_line.inputs.segments[i][5]
        # hugger_material_index = intelli_frame_purlin_line.inputs.segments[i][5]
        
        #Map section properties to CUFSM.
        A = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.A
        xcg = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.xc
        zcg = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.yc
        Ixx = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.Ixx
        Izz = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.Iyy
        Ixz = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.Ixy
        thetap = rad2deg(intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.θ)
        I11 = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.I1
        I22 = intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].section_properties.I2
        unsymm = 0  #Sets Ixz=0 if unsymm = 0

        #Define the number of cross-section nodes.
        num_cross_section_nodes = size(intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].node_geometry)[1]

        #Initialize CUFSM node matrix.
        node = zeros(Float64, (num_cross_section_nodes, 8))

        #Add node numbers to node matrix.
        node[:, 1] .= 1:num_cross_section_nodes

        #Add nodal coordinates to node matrix.
        node[:, 2:3] .= intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].node_geometry

        #Add nodal restraints to node matrix.
        node[:, 4:7] .= ones(num_cross_section_nodes,4)

        #Define number of cross-section elements.
        num_cross_section_elements = size(intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].element_definitions)[1]

        #Initialize CUFSM elem matrix.
        elem = zeros(Float64, (num_cross_section_elements, 5))

        #Add element numbers to elem matrix.
        elem[:, 1] = 1:num_cross_section_elements

        #Add element connectivity and thickness to elem matrix.
        elem[:, 2:4] .= intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data[i].element_definitions

        #Add element material reference to elem matrix.
        elem[:, 5] .= ones(num_cross_section_elements) * 100
                                
        #Find the purlin top flange centerline node.
        #lip curve bottom_flange curve web curve top_flange
        center_top_flange_purlin_node =  sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[1:3]) + sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius[1:3]) + floor(Int, intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[4]/2) + 1  #This floor command is a little dangerous.
        
        #Find the IntelliFrame top flange centerline nodes.
        num_purlin_nodes = size(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].node_geometry)[1]
        center_intelli_frame_flange_node = num_purlin_nodes + sum(intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n[1:2]) + sum(intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n_radius[1:2]) + floor(Int, intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n[3]/2) + 1
       
        #Set up springs in CUFSM.  There can be translational and rotational springs at the purlin top flange, and at each of the IntelliFrame top flanges.
        springs = [1 center_top_flange_purlin_node 0 intelli_frame_purlin_line.bracing_data[i].kx 0 0 intelli_frame_purlin_line.bracing_data[i].kϕ_dist 0 0 0
                   2 center_intelli_frame_flange_node 0 intelli_frame_purlin_line.new_deck_bracing_data[i].kx 0 0 intelli_frame_purlin_line.new_deck_bracing_data[i].kϕ_dist 0 0 0]
        
        #Constrain the IntelliFrame bottom flange to the purlin top flange in all dof (x, z, y, and q).
        intelli_frame_bottom_flange_centerline_node = num_purlin_nodes + floor(Int, intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].n[2] / 2) + 1
        
        #node#e DOFe coeff node#k DOFk
        constraints = [center_top_flange_purlin_node 1 1.0 intelli_frame_bottom_flange_centerline_node 1
                       center_top_flange_purlin_node 2 1.0 intelli_frame_bottom_flange_centerline_node 2
                       center_top_flange_purlin_node 3 1.0 intelli_frame_bottom_flange_centerline_node 3
                       center_top_flange_purlin_node 4 1.0 intelli_frame_bottom_flange_centerline_node 4]

        #Assume here that purlin and IntelliFrame have the same elastic modulus.
        E = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][1]
        ν = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][2]
        G = E / (2 *(1 + ν))
        prop = [100 E E ν ν G]

        neigs = 1  #just need the first mode 

        ###Local buckling - xx axis, positive 

        #Add reference stress to node matrix.

        #Define reference loads.  
        P = 0.0
        Mxx = 1.0  #assume centroidal moment always for now
        Mzz = 0.0
        M11 = 0.0
        M22 = 0.0

        #Define the distortional buckling half-wavelength.
        Lcrd = intelli_frame_purlin_line.distortional_buckling_xx_pos[i].Lcr 

        #Calculate the buckling load just at Lcrd.
        lengths = [Lcrd]

        CUFSM_distortional_xx_net_pos_data, Mcrd_xx_net_pos, Lcrd_xx_net_pos = PurlinLine.get_elastic_buckling(prop, deepcopy(node), elem, lengths, springs, constraints, neigs, P,Mxx,Mzz,M11,M22,A,xcg,zcg,Ixx,Izz,Ixz,thetap,I11,I22,unsymm)   

        #Needed this deepcopy here to make struct work correctly.  Otherwise 'node' just kept changing.

        distortional_buckling_xx_net_pos[i] = PurlinLine.ElasticBucklingData(CUFSM_distortional_xx_net_pos_data, Lcrd_xx_net_pos, Mcrd_xx_net_pos)

    end

    return distortional_buckling_xx_net_pos

end


function calculate_distortional_flexural_strength(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize a vectors that will hold all the outputs.
    distortional_flexural_strength_xx = Array{PurlinLine.DistortionalFlexuralStrengthData, 1}(undef, num_purlin_segments)

    # if intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 ASD"
    #     ASDorLRFD = 0
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 LRFD"
    #     ASDorLRFD = 1
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 nominal"
    #     ASDorLRFD = 2
    # end

    for i = 1:num_purlin_segments

        Mnd_xx_pos, eMnd_xx_pos = AISIS100.v16.f411(intelli_frame_purlin_line.yielding_flexural_strength_xx[i].My, intelli_frame_purlin_line.distortional_buckling_xx_net_pos[i].Mcr, intelli_frame_purlin_line.inputs.design_code)  #use Mcrd_hole always here

        Mnd_xx_neg, eMnd_xx_neg = AISIS100.v16.f411(intelli_frame_purlin_line.yielding_flexural_strength_xx[i].My, intelli_frame_purlin_line.distortional_buckling_xx_neg[i].Mcr, intelli_frame_purlin_line.inputs.design_code)  #assume holes do not affect negative bending distortional buckling for IntelliFrame + purlin

        distortional_flexural_strength_xx[i] = PurlinLine.DistortionalFlexuralStrengthData(Mnd_xx_pos, Mnd_xx_neg, eMnd_xx_pos, eMnd_xx_neg)

    end

    return distortional_flexural_strength_xx

end


function calculate_torsion_strength(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize a vector that will hold all the outputs.
    torsion_strength_purlin = Array{PurlinLine.TorsionStrengthData, 1}(undef, num_purlin_segments)
    torsion_strength_intelli_frame = Array{PurlinLine.TorsionStrengthData, 1}(undef, num_purlin_segments)
    torsion_strength = Array{PurlinLine.TorsionStrengthData, 1}(undef, num_purlin_segments)
    
    # if intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 ASD"
    #     ASDorLRFD = 0
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 LRFD"
    #     ASDorLRFD = 1
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 nominal"
    #     ASDorLRFD = 2
    # end

    for i = 1:num_purlin_segments

        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]
        hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][4]

        #Define the material property index associated with purlin segment i.
        purlin_material_index = intelli_frame_purlin_line.inputs.segments[i][5]
        hugger_material_index = intelli_frame_purlin_line.inputs.segments[i][6]
        
        Cw_purlin = intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].section_properties.Cw
        Cw_intelli_frame = intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].section_properties.Cw  

        #This is the maximum magnitude of the warping stress function.  
        Wn_purlin = maximum(abs.(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].section_properties.wn))
        Wn_intelli_frame = maximum(abs.(intelli_frame_purlin_line.intelli_frame_cross_section_data[hugger_section_index].section_properties.wn)) 

        Fy_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][3]
        Fy_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][3]
        
        Bn_purlin, eBn_purlin = AISIS100.v2024.h411(Cw_purlin, Fy_purlin, Wn_purlin, intelli_frame_purlin_line.inputs.design_code)
        
        Bn_intelli_frame, eBn_intelli_frame= AISIS100.v2024.h411(Cw_intelli_frame, Fy_intelli_frame, Wn_intelli_frame, intelli_frame_purlin_line.inputs.design_code)
        
        Bn = Bn_purlin +  Bn_intelli_frame
        eBn = eBn_purlin +  eBn_intelli_frame

        Wn = 0.0   #not needed, sum Bn_purlin and Bn_hugger

        torsion_strength_purlin[i] = PurlinLine.TorsionStrengthData(Wn_purlin, Bn_purlin, eBn_purlin)
        torsion_strength_intelli_frame[i] = PurlinLine.TorsionStrengthData(Wn_intelli_frame, Bn_intelli_frame, eBn_intelli_frame)
        torsion_strength[i] = PurlinLine.TorsionStrengthData(Wn, Bn, eBn)

    end

    return torsion_strength_purlin, torsion_strength_intelli_frame, torsion_strength

end


function calculate_shear_strength(intelli_frame_purlin_line)

    num_purlin_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Initialize a vector that will hold all the outputs.
    shear_strength_purlin = Array{PurlinLine.ShearStrengthData, 1}(undef, num_purlin_segments)
    shear_strength_intelli_frame = Array{PurlinLine.ShearStrengthData, 1}(undef, num_purlin_segments)
    shear_strength = Array{PurlinLine.ShearStrengthData, 1}(undef, num_purlin_segments)

    # if intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 ASD"
    #     ASDorLRFD = 0
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 LRFD"
    #     ASDorLRFD = 1
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 nominal"
    #     ASDorLRFD = 2
    # end

    for i = 1:num_purlin_segments

        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

    
        # #Define the section property index associated with purlin segment i.
        purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][3]
        hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][4]

        #Define the material property index associated with purlin segment i.
        purlin_material_index = intelli_frame_purlin_line.inputs.segments[i][5]
        hugger_material_index = intelli_frame_purlin_line.inputs.segments[i][6]

        #Set a, the shear stiffener spacing, to the sum of the purlin segment lengths.  This assumes that shear stiffeners are not provided.
        sum_purlin_segments = sum([intelli_frame_purlin_line.inputs.segments[i][1] for i=1:size(intelli_frame_purlin_line.inputs.segments)[1]])
        a = sum_purlin_segments

        #Assume shear strength is Vn,purlin + Vn,intelli_frame.

        #Vn, purlin

        #Define base metal thickness.
        t_purlin = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][2]

        #Define material properties.
        E_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][1]
        μ_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][2]
        Fy_purlin = intelli_frame_purlin_line.inputs.purlin_material_properties[purlin_material_index][3]

        #Depth of flat portion of web.
        full_web_depth_purlin = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][5]
        bottom_flange_web_outside_radius_purlin = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][14]
        top_flange_web_outside_radius_purlin = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][15]
        h_flat_purlin = full_web_depth_purlin - bottom_flange_web_outside_radius_purlin - top_flange_web_outside_radius_purlin

        #Calculate plate buckling coefficient.
        kv_purlin  = AISIS100.v16.g233(a, h_flat_purlin)

        #Calculate shear buckling stress.
        Fcrv_purlin = AISIS100.v16.g232(E_purlin, μ_purlin, kv_purlin, h_flat_purlin, t_purlin)
        Vcr_purlin = AISIS100.v16.g231(h_flat_purlin, t_purlin, Fcrv_purlin)

        #Calculate shear yield force.
        Aw_purlin, Vy_purlin = AISIS100.v16.g215_6(h_flat_purlin, t_purlin, Fy_purlin)

        #Calculate shear buckling strength.
        # Vn_purlin, eVn_purlin = AISIS100.v16.g21(h_flat_purlin, t_purlin, Fy_purlin, Vcr_purlin, intelli_frame_purlin_line.inputs.design_code)
        Vn_purlin, eVn_purlin = AISIS100.v16.g21_3(Vcr_purlin, Vy_purlin, intelli_frame_purlin_line.inputs.design_code)


        #Vn, IntelliFrame

        #Define base metal thickness.
        t_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][1]

        #Define material properties.
        E_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][1]
        μ_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][2]
        Fy_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[hugger_material_index][3]

        #Depth of flat portion of web.
        full_web_depth_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][3]
        bottom_flange_web_outside_radius_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][10]
        top_flange_web_outside_radius_intelli_frame = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][11]
        h_flat_intelli_frame = full_web_depth_intelli_frame - bottom_flange_web_outside_radius_intelli_frame - top_flange_web_outside_radius_intelli_frame

        #Calculate plate buckling coefficient.
        kv_intelli_frame  = AISIS100.v16.g233(a, h_flat_intelli_frame)

        #Calculate shear buckling stress.
        Fcrv_intelli_frame = AISIS100.v16.g232(E_intelli_frame, μ_intelli_frame, kv_intelli_frame, h_flat_intelli_frame, t_intelli_frame)
        Vcr_intelli_frame = AISIS100.v16.g231(h_flat_intelli_frame, t_intelli_frame, Fcrv_intelli_frame)

        #Calculate shear yield force.
        Aw_intelli_frame, Vy_intelli_frame = AISIS100.v16.g215_6(h_flat_intelli_frame, t_intelli_frame, Fy_intelli_frame)

        #Calculate shear buckling strength for one web of IntelliFrame.
        # Vn_intelli_frame, eVn_intelli_frame = AISIS100.v16.g21(h_flat_intelli_frame, t_intelli_frame, Fy_intelli_frame, Vcr_intelli_frame, intelli_frame_purlin_line.inputs.design_code)
        Vn_intelli_frame, eVn_intelli_frame = AISIS100.v16.g21_3(Vcr_intelli_frame, Vy_intelli_frame, intelli_frame_purlin_line.inputs.design_code)
 
        Vn = Vn_purlin + Vn_intelli_frame
        eVn = eVn_purlin + eVn_intelli_frame


        shear_strength_purlin[i] = PurlinLine.ShearStrengthData(h_flat_purlin, Aw_purlin, Fcrv_purlin, kv_purlin, Vcr_purlin, Vy_purlin, Vn_purlin, eVn_purlin)
        shear_strength_intelli_frame[i] = PurlinLine.ShearStrengthData(h_flat_intelli_frame, Aw_intelli_frame, Fcrv_intelli_frame, kv_intelli_frame,  Vcr_intelli_frame, Vy_intelli_frame, Vn_intelli_frame, eVn_intelli_frame)
        shear_strength[i] = PurlinLine.ShearStrengthData(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Vn, eVn)
    

    end

    return shear_strength_purlin, shear_strength_intelli_frame, shear_strength

end



function discretize_intelli_frame_purlin_line(intelli_frame_purlin_line)

    #Define the hugger+purlin segment properties.
    num_segments = size(intelli_frame_purlin_line.inputs.segments)[1]

    #Intialize data structure for ThinWalledBeam member_definitions.
    member_definitions = Vector{Tuple{Float64, Float64, Int64, Int64}}(undef, num_segments)

    #Loop over the hugger+purlin segments.
    for i=1:num_segments

        # L = intelli_frame_purlin_line.inputs.segments[i][1]

        # if L>=15.0*12.0  #only works for inches right now
        #     dL = L / 10  #Hard coded for now.
        # else
        #     dL = L/6
        # end
        
        	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


        section_id = intelli_frame_purlin_line.inputs.segments[i][3]
        material_id = intelli_frame_purlin_line.inputs.segments[i][5]  #use purlin E and ν here, should be the same as the Hugger always

        #L(1) dL(2) section_properties(3) material_properties(4) 
                             
        member_definitions[i] = (intelli_frame_purlin_line.inputs.segments[i][1], intelli_frame_purlin_line.inputs.segments[i][2], section_id, material_id)

    end

    #Add purlin line discretization to purlin_line data structure.
    dz, z, dm = Mesh.define_line_element(member_definitions)

    return member_definitions, dz, z, dm

end

function define(design_code, segments, spacing, roof_slope, purlin_cross_section_dimensions, intelli_frame_cross_section_dimensions, intelli_frame_punch_out_dimensions, purlin_material_properties, intelli_frame_material_properties, deck_details, deck_material_properties, new_deck_details, new_deck_material_properties, frame_flange_width, support_locations, purlin_frame_connections, bridging_locations)

    #Create the IntelliFrame data structure.
    intelli_frame_purlin_line = IntelliFrameObject()

    #Add IntelliFrame user inputs to data structure.
    intelli_frame_purlin_line.inputs = IntelliFrame.Inputs(design_code, segments, spacing, roof_slope, purlin_cross_section_dimensions, intelli_frame_cross_section_dimensions, intelli_frame_punch_out_dimensions, purlin_material_properties, intelli_frame_material_properties, deck_details, deck_material_properties, new_deck_details, new_deck_material_properties, frame_flange_width, support_locations, purlin_frame_connections, bridging_locations)

    #Define IntelliFrame cross-section data including nodal geometry, cross-section discretization and section properties.
    # n = [4, 6, 4, 4]
    # n_radius = [4, 4, 4]

    n = [2, 6, 2, 2]
    n_radius = [3, 3, 3]
    intelli_frame_purlin_line.intelli_frame_cross_section_data = define_intelli_frame_cross_sections(intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions, n, n_radius)

    #Create the PurlinLine data structure.
    purlin_line = PurlinLine.Model()


    	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


    num_segments = size(segments)[1]
    purlin_segments = Vector{Tuple{Float64,Float64,Int64,Int64}}(undef, num_segments)
    for i = 1:num_segments
        purlin_segments[i] = (segments[i][1], segments[i][2], segments[i][3], segments[i][5])
    end


    #Capture PurlinLine inputs.
    loading_direction = "gravity"
    purlin_line.inputs = PurlinLine.Inputs(loading_direction, design_code, purlin_segments, spacing, roof_slope, purlin_cross_section_dimensions, purlin_material_properties, deck_details, deck_material_properties, frame_flange_width, support_locations,   purlin_frame_connections, bridging_locations)

    #Define the purlin cross-section discretization and calculate section properties.
    # n = [4, 4, 5, 4, 4]
    # n_radius = [4, 4, 4, 4]

    n = [2, 2, 5, 2, 2]
    n_radius = [3, 3, 3, 3]
    intelli_frame_purlin_line.purlin_cross_section_data = PurlinLine.define_purlin_section(purlin_line.inputs.cross_section_dimensions, n, n_radius)
    purlin_line.cross_section_data = intelli_frame_purlin_line.purlin_cross_section_data

    #Define the purlin free flange cross-section discretization and calculate section properties.
    # n = [4, 4, 4]
    # n_radius = [4, 4]

    n = [2, 2, 2]
    n_radius = [3, 3]
    intelli_frame_purlin_line.free_flange_cross_section_data = PurlinLine.define_purlin_free_flange_section(purlin_line.inputs.cross_section_dimensions, n, n_radius)
    purlin_line.free_flange_cross_section_data = intelli_frame_purlin_line.free_flange_cross_section_data

    #Define the purlin cross-section discretization for calculating plastic properties.
    n = [4, 4, 5, 4, 4] .* 10
    n_radius = [4, 4, 4, 4]
    purlin_plastic_cross_section_data = PurlinLine.define_purlin_section(purlin_line.inputs.cross_section_dimensions, n, n_radius)
   
    #Define IntelliFrame cross-section discretizaton for calculating plastic properties.
    n = [4, 6, 4, 4] .* 10
    n_radius = [4, 4, 4]
    intelli_frame_plastic_cross_section_data = define_intelli_frame_cross_sections(intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions, n, n_radius)

    #Define IntelliFrame + purlin properties.
    intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data = define_intelli_frame_purlin_cross_sections(intelli_frame_purlin_line.inputs.segments, intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions, intelli_frame_purlin_line.purlin_cross_section_data, intelli_frame_purlin_line.intelli_frame_cross_section_data, purlin_plastic_cross_section_data, intelli_frame_plastic_cross_section_data)
   
    #Define IntelliFrame + purlin plastic discretization.
    intelli_frame_purlin_plastic_cross_section_data = define_intelli_frame_purlin_cross_sections(intelli_frame_purlin_line.inputs.segments, intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions, purlin_plastic_cross_section_data, intelli_frame_plastic_cross_section_data, purlin_plastic_cross_section_data, intelli_frame_plastic_cross_section_data)

    #Calculate deck bracing properties.  This is for the purlin to deck once the Huggers have been attached with closely spaced screws.   
    intelli_frame_purlin_line.bracing_data = define_existing_deck_bracing_properties(purlin_line)
    purlin_line.bracing_data = intelli_frame_purlin_line.bracing_data

    #Calculate free flange shear flow properties, including bracing stiffness from web and conversion factor from purlin line load to shear flow.
    #Assume shear flow is unchanged with addition of the IntelliFrame.
    intelli_frame_purlin_line.free_flange_data = PurlinLine.calculate_free_flange_shear_flow_properties(purlin_line)

    #Calculate bracing properties for new roof deck to IntelliFrame.
    intelli_frame_purlin_line.new_deck_bracing_data = define_new_deck_bracing_properties(intelli_frame_purlin_line)

    #Calculate elastic buckling properties for IntelliFrame and purlin as a cross-section together.
    intelli_frame_purlin_line.local_buckling_xx_pos, intelli_frame_purlin_line.local_buckling_xx_neg, intelli_frame_purlin_line.local_buckling_yy_pos, intelli_frame_purlin_line.local_buckling_yy_neg, intelli_frame_purlin_line.distortional_buckling_xx_pos, intelli_frame_purlin_line.distortional_buckling_xx_neg = IntelliFrame.calculate_elastic_buckling_properties(intelli_frame_purlin_line)

    #Calculate net section properties and add to IntelliFrame data structure.
    intelli_frame_purlin_line.intelli_frame_purlin_net_cross_section_data = define_intelli_frame_purlin_net_section(intelli_frame_purlin_line.inputs.segments, intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions, intelli_frame_purlin_line.intelli_frame_cross_section_data, intelli_frame_plastic_cross_section_data, intelli_frame_purlin_line.purlin_cross_section_data, purlin_plastic_cross_section_data,  intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data, intelli_frame_purlin_plastic_cross_section_data, intelli_frame_purlin_line.inputs.intelli_frame_punch_out_dimensions)

    #Calculate local buckling at the IntelliFrame punchout.
    intelli_frame_purlin_line.local_buckling_xx_net_pos = calculate_net_section_local_buckling_properties(intelli_frame_purlin_line)

    #Calculate distortional buckling including the influence of the IntelliFrame punchout.
    intelli_frame_purlin_line.intelli_frame_purlin_distortional_net_cross_section_data = define_intelli_frame_purlin_distortional_net_section(intelli_frame_purlin_line)

    intelli_frame_purlin_line.distortional_buckling_xx_net_pos = calculate_net_section_distortional_buckling_properties(intelli_frame_purlin_line)

    #Calculate the first yield flexural strengths for each purlin line segment.  
    intelli_frame_purlin_line.yielding_flexural_strength_xx, intelli_frame_purlin_line.yielding_flexural_strength_xx_net, intelli_frame_purlin_line.yielding_flexural_strength_yy, intelli_frame_purlin_line.yielding_flexural_strength_free_flange_yy = calculate_yielding_flexural_strength(intelli_frame_purlin_line)

    #Calculate the local-global flexural strengths for each purlin line segment.   
    intelli_frame_purlin_line.local_global_flexural_strength_xx_no_hole, intelli_frame_purlin_line.local_global_flexural_strength_xx_hole, intelli_frame_purlin_line.local_global_flexural_strength_xx, intelli_frame_purlin_line.local_global_flexural_strength_yy, intelli_frame_purlin_line.local_global_flexural_strength_free_flange_yy = calculate_local_global_flexural_strength(intelli_frame_purlin_line)

    #Calculate distortional buckling strengths for each purlin line segment.
    intelli_frame_purlin_line.distortional_flexural_strength_xx = calculate_distortional_flexural_strength(intelli_frame_purlin_line)

    #Calculate torsion strength for each purlin line segment.
    intelli_frame_purlin_line.torsion_strength_purlin, intelli_frame_purlin_line.torsion_strength_intelli_frame, intelli_frame_purlin_line.torsion_strength = calculate_torsion_strength(intelli_frame_purlin_line)

    #Calculate shear strength for each purlin line segment.
    intelli_frame_purlin_line.shear_strength_purlin, intelli_frame_purlin_line.shear_strength_intelli_frame, intelli_frame_purlin_line.shear_strength = calculate_shear_strength(intelli_frame_purlin_line)

    #Calculate web crippling strength at each support.
    #For purlin... 
    intelli_frame_purlin_line.purlin_web_crippling = PurlinLine.calculate_web_crippling_strength(purlin_line)
    #For IntelliFrame...
    intelli_frame_purlin_line.intelli_frame_web_crippling = calculate_intelli_frame_web_crippling_strength(intelli_frame_purlin_line)

    return intelli_frame_purlin_line

end



#Calculate the web crippling strength at each support location.
function calculate_intelli_frame_web_crippling_strength(intelli_frame_purlin_line)

    ###Assumptions...
    #Purlin is always fastened to a support.
    #Purlin always has stiffened or partially stiffened flanges.
    #The loading is always a one-flange loading.

    # if intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 ASD"
    #     ASDorLRFD = 0
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 LRFD"
    #     ASDorLRFD = 1
    # elseif intelli_frame_purlin_line.inputs.design_code == "AISI S100-16 nominal"
    #     ASDorLRFD = 2
    # end

    #Define the number of supports along the purlin line.
    num_supports = length(intelli_frame_purlin_line.inputs.support_locations)

    #Initialize a vector that will hold all the web crippling outputs.
    intelli_frame_web_crippling = Array{PurlinLine.WebCripplingData, 1}(undef, num_supports)

    #Define coordinates along purlin line where segment properties change.
    purlin_range = [0; cumsum([intelli_frame_purlin_line.inputs.segments[i][1] for i=1:size(intelli_frame_purlin_line.inputs.segments)[1]])]
          
    for i = 1:num_supports

        #Find purlin segment that coincides with a support.
        purlin_range_indices = findall(x-> (x < intelli_frame_purlin_line.inputs.support_locations[i]) | (x ≈ intelli_frame_purlin_line.inputs.support_locations[i]), purlin_range)
        if purlin_range_indices == [1]
            segment_index = 1
        else
            segment_index = maximum(purlin_range_indices) - 1
        end 

        #Define if support is at the end or in the interior of a purlin line.
        if (intelli_frame_purlin_line.inputs.support_locations[i] ≈ purlin_range[1]) | (intelli_frame_purlin_line.inputs.support_locations[i] ≈ purlin_range[end])
            load_location = "End"
        else
            load_location = "Interior"
        end

           	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


        #Define Hugger section and material indices to use for web crippling definitions.
        section_index = intelli_frame_purlin_line.inputs.segments[segment_index][4]
        material_index = intelli_frame_purlin_line.inputs.segments[segment_index][6]

        t = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][1]
        Fy = intelli_frame_purlin_line.inputs.intelli_frame_material_properties[material_index][3]
       
        full_web_depth = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][3]
        bottom_flange_web_outside_radius = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][10]
        top_flange_web_outside_radius = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][11]
        h_flat = full_web_depth - bottom_flange_web_outside_radius - top_flange_web_outside_radius

        θ = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][7]  #angle between web plane and surface plane 

        #Use AISI S100-16 Table G5-3 for Z-sections.
        table_g53 = AISIS100.v16.table_g53()       

        web_crippling_coeff = filter(row -> row.support_condition == "Fastened to Support", table_g53)
        web_crippling_coeff = filter(row -> row.flange_condition == "Stiffened or Partially Stiffened Flanges", web_crippling_coeff)
        web_crippling_coeff = filter(row -> row.load_case == "One-Flange Loading or Reaction", web_crippling_coeff)
        web_crippling_coeff = filter(row -> row.load_location== load_location, web_crippling_coeff)

        C = web_crippling_coeff.C[1]
        C_R = web_crippling_coeff.C_R[1]
        R = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[section_index][10] - t  #inside radius
        C_N = web_crippling_coeff.C_N[1]
        N = intelli_frame_purlin_line.inputs.frame_flange_width
        C_h = web_crippling_coeff.C_h[1]
        ϕ_w = web_crippling_coeff.LRFD[1]
        Ω_w = web_crippling_coeff.ASD[1]
        ϕ_w_LSD = web_crippling_coeff.LSD[1]

        Pn, ePn = AISIS100.v16.g51(t, h_flat, Fy, θ, C, C_R, R, C_N, N, C_h, ϕ_w, Ω_w, ϕ_w_LSD, intelli_frame_purlin_line.inputs.design_code)

        intelli_frame_web_crippling[i] = PurlinLine.WebCripplingData(web_crippling_coeff.support_condition[1], web_crippling_coeff.flange_condition[1], web_crippling_coeff.load_case[1], web_crippling_coeff.load_location[1], C, C_R, R, C_N, N, C_h, ϕ_w, Ω_w, ϕ_w_LSD, Pn, ePn)

    end

    return intelli_frame_web_crippling

end


function thin_walled_beam_interface(intelli_frame_purlin_line)

    #Discretize purlin line.
    # member_definitions, dz, z, m = discretize_intelli_frame_purlin_line(intelli_frame_purlin_line)
    member_definitions, dz, z, m = PurlinLine.discretize_purlin_line(intelli_frame_purlin_line)

    #Define ThinWalledBeam section property inputs.
    #Ix Iy Ixy J Cw

    num_nodes = length(z)
    Ix = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.Ixx * ones(Float64, num_nodes)
    Iy = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.Iyy * ones(Float64, num_nodes)
    Ixy = -intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.Ixy * ones(Float64, num_nodes)
    J = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.J * ones(Float64, num_nodes)
    Cw = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.Cw * ones(Float64, num_nodes)

    E = intelli_frame_purlin_line.inputs.purlin_material_properties[1][1] * ones(Float64, num_nodes)
    ν = intelli_frame_purlin_line.inputs.purlin_material_properties[1][2] * ones(Float64, num_nodes)
    G = E ./ (2 .* (1 .+ ν))

  

    #Define the lateral and rotational stiffness magnitudes for ThinWalledBeam.


    #There will be two sets of springs, one for the existing deck and one for the new deck.

    kx_existing_deck = intelli_frame_purlin_line.bracing_data[1].kx .* ones(Float64, num_nodes)
    kϕ_existing_deck = intelli_frame_purlin_line.bracing_data[1].kϕ .* ones(Float64, num_nodes)

    # kx = Array{Array{Float64}}(undef, 2)
    # kϕ = Array{Array{Float64}}(undef, 2)

    # #First, the existing deck.

    # num_purlin_segments = size(intelli_frame_purlin_line.bracing_data)[1]

    # kx_segments = Vector{Float64}(undef, num_purlin_segments)
    # kϕ_segments = Vector{Float64}(undef, num_purlin_segments)

    # for i=1:num_purlin_segments

    #     kx_segments[i] = intelli_frame_purlin_line.bracing_data[i].kx 
    #     kϕ_segments[i]  = intelli_frame_purlin_line.bracing_data[i].kϕ
 
    # end

    # num_nodes = length(z)
    # kx[1] = zeros(Float64, num_nodes)
    # kϕ[1] = zeros(Float64, num_nodes)
    # kx[1] .= kx_segments[m]
    # kϕ[1] .= kϕ_segments[m]

    #Define the lateral spring location for ThinWalledBeam.    

    #Calculate the y-distance from the IntelliFrame + purlin shear center to the existing deck lateral translational spring.
    # spring_location_segment = Vector{Float64}(undef, num_purlin_sections)

    # for i = 1:num_purlin_sections

        # purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][2]

           	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions

        purlin_section_index = intelli_frame_purlin_line.inputs.segments[1][3]  #keep constant for now

        # ys = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.ys  #distance from bottom fiber of purlin to shear center
        # h = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][5] 

        ys = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.ys  #distance from bottom fiber of purlin to shear center
        h = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][5] #keep constant for now

        ay_kx_existing_deck = (h - ys) .* ones(Float64, num_nodes)    

    # end

    kx_new_deck = intelli_frame_purlin_line.new_deck_bracing_data[1].kx .* ones(Float64, num_nodes)  
    kϕ_new_deck  = intelli_frame_purlin_line.new_deck_bracing_data[1].kϕ .* ones(Float64, num_nodes)  
 

    # ay_kx = Array{Array{Float64}}(undef, 2)

    # #Define location of translational spring at each node.
    # ay_kx[1] = Mesh.create_line_element_property_array(member_definitions, m, dz, spring_location_segment, 3, 1)


    #Now work on the new deck springs and spring locations.


    # kx_segments = Vector{Float64}(undef, num_purlin_segments)
    # kϕ_segments = Vector{Float64}(undef, num_purlin_segments)

    # for i=1:num_purlin_segments

    #     # kx_segments[i] = intelli_frame_purlin_line.new_deck_bracing_data[i].kx 
    #     # kϕ_segments[i]  = intelli_frame_purlin_line.new_deck_bracing_data[i].kϕ

    #     kx_segments[i] = intelli_frame_purlin_line.new_deck_bracing_data[1].kx  #keep constant for now
    #     kϕ_segments[i]  = intelli_frame_purlin_line.new_deck_bracing_data[1].kϕ
 
    # end

    # num_nodes = length(z)
    # kx[2] = zeros(Float64, num_nodes)
    # kϕ[2] = zeros(Float64, num_nodes)
    # kx[2] .= kx_segments[m]
    # kϕ[2] .= kϕ_segments[m]

    #Define the lateral spring location for ThinWalledBeam.    

    #Calculate the y-distance from the IntelliFrame + purlin shear center to the new deck lateral translational spring.
    # spring_location_segment = Vector{Float64}(undef, num_purlin_sections)

    # for i = 1:num_purlin_sections

        # purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][2]
        # hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][3]

           	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


    purlin_section_index = intelli_frame_purlin_line.inputs.segments[1][3]   #keep constant for now
    hugger_section_index = intelli_frame_purlin_line.inputs.segments[1][4]

    # ys = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.ys  #distance from bottom fiber of purlin to shear center
    ys = intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.ys  #distance from bottom fiber of purlin to shear center   #keep constant
    intelli_frame_purlin_depth = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][4] + intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][5]
    #out to out IntelliFrame + purlin height

    ay_kx_new_deck  = (intelli_frame_purlin_depth - ys) .* ones(Float64, num_nodes)   

    #With the transformation above the lateral springs are moved to the shear center.
    ay_kx = zeros(Float64, num_nodes)

    # end

     #Now combine lateral springs by transforming them to a rotational spring and adding them to other kϕs
     kϕ = kϕ_existing_deck .+ kϕ_new_deck .+ ay_kx_existing_deck .* kx_existing_deck .+ ay_kx_new_deck .* kx_new_deck

     kx = kx_existing_deck .+ kx_new_deck

     intelli_frame_purlin_line.deck_springs = DeckSprings(kx_existing_deck, kx_new_deck, ay_kx_existing_deck, ay_kx_new_deck, kϕ_existing_deck, kϕ_new_deck)


    #Define location of translational spring at each node.
    # ay_kx[2] = Mesh.create_line_element_property_array(member_definitions, m, dz, spring_location_segment, 3, 1)


    #Define purlin line support locations for ThinWalledBeam.  If there are anti-roll clips assume purlin is fixed in rotation at a frame support. If the purlins are connected to the frame just at the purlin bottom flange, assumed the purlin is free to rotate at the support.



    #If there are anti-roll clips assume purlin is fixed in rotation at a frame support. If the purlins are connected to the frame just at the purlin bottom flange, assumed the purlin is free to rotate at the support.

    #For intermediate bridging, assume lateral displacement and twist are fully restrained.
    
    supports_and_bridging = sort(unique([intelli_frame_purlin_line.inputs.support_locations; intelli_frame_purlin_line.inputs.bridging_locations]))

    num_supports = length(supports_and_bridging)

    supports = Vector{Tuple{Float64, String, String, String}}(undef, num_supports)

    for i = 1:num_supports

        if (intelli_frame_purlin_line.inputs.purlin_frame_connections == "anti-roll clip") & (supports_and_bridging[i] in intelli_frame_purlin_line.inputs.support_locations)
            
            supports[i] = (supports_and_bridging[i], "fixed", "fixed", "fixed")
        
        elseif (intelli_frame_purlin_line.inputs.purlin_frame_connections == "bottom flange connection") & (supports_and_bridging[i] in intelli_frame_purlin_line.inputs.support_locations)

            supports[i] = (supports_and_bridging[i], "fixed", "fixed", "free")

        elseif supports_and_bridging[i] in intelli_frame_purlin_line.inputs.bridging_locations  #intermediate bridging

            supports[i] = (supports_and_bridging[i], "fixed", "free", "fixed")   #lateral fixed, vertical free, rotation fixed

        end

    end



    # #####################################
    
    # num_supports = length(intelli_frame_purlin_line.inputs.support_locations)

    # supports = Vector{Tuple{Float64, String, String, String}}(undef, num_supports)

    # for i = 1:num_supports

    #     if intelli_frame_purlin_line.inputs.purlin_frame_connections == "anti-roll clip"
            
    #         supports[i] = (intelli_frame_purlin_line.inputs.support_locations[i], "fixed", "fixed", "fixed")
        
    #     elseif intelli_frame_purlin_line.inputs.purlin_frame_connections == "bottom flange connection"

    #         supports[i] = (intelli_frame_purlin_line.inputs.support_locations[i], "fixed", "fixed", "free")

    #     end

    # end

    #Define purlin line end boundary conditions for ThinWalledBeam.

    end_boundary_conditions = Array{String}(undef, 2)

    purlin_line_length = sum([intelli_frame_purlin_line.inputs.segments[i][1] for i=1:size(intelli_frame_purlin_line.inputs.segments)[1]])

    #type=1 u''=v''=ϕ''=0 (simply supported), type=2 u'=v'=ϕ'=0  (fixed), type=3 u''=v''=ϕ''=u'''=v'''=ϕ'''=0 (free end, e.g., a cantilever)

    #z=0 (left) end
    if supports[1][1] == 0.0
        end_boundary_conditions[1] = "simply-supported" #pin
    else
        end_boundary_conditions[1] = "free"  #cantilever
    end

    #z=purlin_line_length (right) end
    if supports[end][1] == purlin_line_length
        end_boundary_conditions[2] = "simply-supported"
    else
        end_boundary_conditions[2] = "free"  #cantilever
    end

    #Calculate load magnitudes from user-defined pressure for ThinWalledBeam.
    q = intelli_frame_purlin_line.applied_pressure * intelli_frame_purlin_line.inputs.spacing #go from pressure to line load

    num_nodes = length(z)

    if q<0   #uplift wind pressure
        qx = zeros(num_nodes)
        qy = q .* ones(Float64, num_nodes)
    elseif q>= 0 #gravity pressure
        qx = -q .* sin(deg2rad(intelli_frame_purlin_line.inputs.roof_slope)) .* ones(Float64, num_nodes)
        qy = q .* cos(deg2rad(intelli_frame_purlin_line.inputs.roof_slope)) .* ones(Float64, num_nodes)
    end

    # #Calculate the load locations for ThinWalledBeam, from the IntelliFrame + purlin shear center.  
    # ax_purlin_section = Vector{Float64}(undef, num_purlin_sections)
    # ay_purlin_section = Vector{Float64}(undef, num_purlin_sections)

    # for i = 1:num_purlin_sections

        # purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][2]
        # hugger_section_index = intelli_frame_purlin_line.inputs.segments[i][3]

           	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


    purlin_section_index = intelli_frame_purlin_line.inputs.segments[1][3]  #keep constant
    hugger_section_index = intelli_frame_purlin_line.inputs.segments[1][4]

    # center_top_flange_node_index = sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[1:3]) + sum(intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n_radius[1:3]) + floor(Int,intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].n[4]/2) + 1

    center_top_flange_node_index = sum(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].n) + sum(intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].n_radius) + 2 - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].n[end] - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].n_radius[end] - floor(Int,intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].n[end-1]/2)


    # ax_purlin_section[i] = intelli_frame_purlin_line.purlin_cross_section_data[purlin_section_index].node_geometry[center_top_flange_node_index, 1] - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.xs

    ax = (intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[purlin_section_index].node_geometry[center_top_flange_node_index, 1] - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.xs) * ones(Float64, num_nodes)  #keep constant


    intelli_frame_purlin_depth = intelli_frame_purlin_line.inputs.intelli_frame_cross_section_dimensions[hugger_section_index][4] + intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[purlin_section_index][5]

    #This is different since the load is now applied at the top of the IntelliFrame.
    # ay_purlin_section[i] = intelli_frame_purlin_depth - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[i].section_properties.ys

    ay = (intelli_frame_purlin_depth - intelli_frame_purlin_line.intelli_frame_purlin_cross_section_data[1].section_properties.ys) * ones(Float64, num_nodes)  #keep constant
    
    # end

    #Define the load location at each node.
    # ax = Mesh.create_line_element_property_array(member_definitions, m, dz, ax_purlin_section, 3, 1)
    # ay = Mesh.create_line_element_property_array(member_definitions, m, dz, ay_purlin_section, 3, 1)

    return z, Ix, Iy, Ixy, J, Cw, E, G, kx, kϕ, ay_kx, qx, qy, ax, ay, end_boundary_conditions, supports

end



function beam_column_interface(intelli_frame_purlin_line)

    #Discretize purlin line.
    # member_definitions, dz, z, m = discretize_intelli_frame_purlin_line(intelli_frame_purlin_line)
    member_definitions, dz, z, m = PurlinLine.discretize_purlin_line(intelli_frame_purlin_line)

    num_nodes = length(z)
    # #Define the number of purlin cross-sections.
    # num_purlin_sections = size(intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions)[1]

    # #Initialize an array of tuples to hold the free flange section properties.
    # section_properties = Vector{Tuple{Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64,}}(undef, num_purlin_sections)

    # for i = 1:num_purlin_sections

        # purlin_section_index = intelli_frame_purlin_line.inputs.segments[i][2]

           	#length, DL, purlin section_properties, Hugger section properties, purlin material_properties, Hugger material properties, Hugger punchout dimensions


    #     purlin_section_index = intelli_frame_purlin_line.inputs.segments[1][3]  #keep constant

    #     Af = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.A
    #     Ixf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.Ixx
    #     Iyf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.Iyy
    #     Jf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.J
    #     Cwf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.Cw
    #     xcf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.xc
    #     ycf = intelli_frame_purlin_line.free_flange_cross_section_data[purlin_section_index].section_properties.yc
    #     # xsf = intelli_frame_purlin_line.free_flange_cross_section_data[i].section_properties.xs
    #     # ysf = intelli_frame_purlin_line.free_flange_cross_section_data[i].section_properties.ys

    #     xsf = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.xs  #keep constant
    #     ysf = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.ys

    #     section_properties[i] = (Af, Ixf, Iyf, Jf, Cwf, xcf, ycf, xsf, ysf)

    # end

    A = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.A .* ones(Float64, num_nodes)
    Ix = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.Ixx .* ones(Float64, num_nodes)
    Iy = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.Iyy .* ones(Float64, num_nodes)
    J = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.J .* ones(Float64, num_nodes)
    Cw = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.Cw .* ones(Float64, num_nodes)
    xc = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.xc .* ones(Float64, num_nodes)
    yc = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.yc .* ones(Float64, num_nodes)
    xs = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.xs .* ones(Float64, num_nodes)
    ys = intelli_frame_purlin_line.free_flange_cross_section_data[1].section_properties.ys .* ones(Float64, num_nodes)

    xo = -(xc .- xs)
    yo = yc .- ys
 
    Io = Ix .+ Iy .+ A .* (xo.^2 + yo.^2)


    # #Define BeamColumn material property inputs.
    # num_purlin_materials = size(intelli_frame_purlin_line.inputs.purlin_material_properties)[1]

    # material_properties = Vector{Tuple{Float64, Float64}}(undef, num_purlin_materials)

    # for i = 1:num_purlin_materials

    #     material_properties[i] = (intelli_frame_purlin_line.inputs.purlin_material_properties[i][1], intelli_frame_purlin_line.inputs.purlin_material_properties[i][2])

    # end

    E = intelli_frame_purlin_line.inputs.purlin_material_properties[1][1] .* ones(Float64, num_nodes)
    ν = intelli_frame_purlin_line.inputs.purlin_material_properties[1][2] .* ones(Float64, num_nodes)
    G = E ./ (2 .* (1 .+ ν))

   
    # num_purlin_segments = size(intelli_frame_purlin_line.bracing_data)[1]

    #Define kxf along the purlin line.
    # kxf_segments = [intelli_frame_purlin_line.free_flange_data[i].kxf for i=1:num_purlin_segments]

    kx = intelli_frame_purlin_line.free_flange_data[1].kxf .* ones(Float64, num_nodes) #keep constant

    # num_nodes = length(z)
    # kxf = zeros(Float64, num_nodes)
    # kxf .= kxf_segments[m]

    #There is no kyf assumed.
    ky = zeros(Float64, num_nodes)

    #Define kϕf along the purlin line.
    # kϕf_segments = [intelli_frame_purlin_line.free_flange_data[i].kϕf for i=1:num_purlin_segments]

    kϕ = intelli_frame_purlin_line.free_flange_data[1].kϕf .* ones(Float64, num_nodes)  #keep constant

    # kϕf = zeros(Float64, num_nodes)
    # kϕf .= kϕf_segments[m]    

    #Assume the lateral spring acts at the free flange centroid.  This means hx =hy = 0.
    hx = zeros(Float64, num_nodes)
    hy = zeros(Float64, num_nodes)

    #Define shear flow force in free flange.

    #Define the purlin segment properties.
    # kH_segments = [intelli_frame_purlin_line.free_flange_data[i].kH for i=1:num_purlin_segments]

    kH = intelli_frame_purlin_line.free_flange_data[1].kH   #keep constant

    # kH = zeros(Float64, num_nodes)
    # kH .= kH_segments[m]

    #The shear flow is applied at the free flange centerline.  The distance ay in StructuresKit.BeamColumn is the distance from the shear center to the load along the centroidal y-axis.   Since the shear center for just the free flange is close to the free flange centerline, assume ay= 0.  

    ay = zeros(Float64, num_nodes)

    #There is no qyf so this can be set to zero.
    ax = zeros(Float64, num_nodes)

    #Define supports.   Combine frame supports and intermediate bridging here.
    # supports = sort(unique([intelli_frame_purlin_line.inputs.support_locations; intelli_frame_purlin_line.inputs.bridging_locations]))


    supports_and_bridging = sort(unique([intelli_frame_purlin_line.inputs.support_locations; intelli_frame_purlin_line.inputs.bridging_locations]))

    num_supports = length(supports_and_bridging)

    supports = Vector{Tuple{Float64, String, String, String}}(undef, num_supports)

    for i = 1:num_supports

        if (intelli_frame_purlin_line.inputs.purlin_frame_connections == "anti-roll clip") & (supports_and_bridging[i] in intelli_frame_purlin_line.inputs.support_locations)
            
            supports[i] = (supports_and_bridging[i], "fixed", "fixed", "fixed")
        
        elseif (intelli_frame_purlin_line.inputs.purlin_frame_connections == "bottom flange connection") & (supports_and_bridging[i] in intelli_frame_purlin_line.inputs.support_locations)

            supports[i] = (supports_and_bridging[i], "fixed", "fixed", "free")

        elseif supports_and_bridging[i] in intelli_frame_purlin_line.inputs.bridging_locations  #intermediate bridging

            supports[i] = (supports_and_bridging[i], "fixed", "free", "fixed")   #lateral fixed, vertical free, rotation fixed

        end

    end

    #Define purlin line end boundary conditions for BeamColumn.

    end_boundary_conditions = Array{String}(undef, 2)

    purlin_line_length = sum([intelli_frame_purlin_line.inputs.segments[i][1] for i=1:size(intelli_frame_purlin_line.inputs.segments)[1]])

    #type=1 u''=v''=ϕ''=0 (simply supported), type=2 u'=v'=ϕ'=0  (fixed), type=3 u''=v''=ϕ''=u'''=v'''=ϕ'''=0 (free end, e.g., a cantilever)

    #z=0 (left) end
    if supports[1] == 0.0
        end_boundary_conditions[1] = "simply-supported" #pin
    else
        end_boundary_conditions[1] = "free"  #cantilever
    end

    #z=purlin_line_length (right) end
    if supports[end] == purlin_line_length
        end_boundary_conditions[2] = "simply-supported"
    else
        end_boundary_conditions[2] = "free"  #cantilever
    end


    return z, A, Ix, Iy, Io, J, Cw, E, G, ax, ay, kx, ky, kϕ, hx, hy, kH, end_boundary_conditions, supports, xo, yo

end


function calculate_free_flange_axial_force(Mxx, intelli_frame_purlin_line)
    #this may not need to be updated, could use PurlinLine version
    # num_purlin_sections = size(intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions)[1]

    # P_unit = zeros(Float64, num_purlin_sections)

    #Loop over the purlin cross-sections in the line.
    # for i = 1:num_purlin_sections

        #Find web node at H/5.
    web_index = intelli_frame_purlin_line.purlin_cross_section_data[1].n[1] + intelli_frame_purlin_line.purlin_cross_section_data[1].n_radius[1] + intelli_frame_purlin_line.purlin_cross_section_data[1].n[2] + intelli_frame_purlin_line.purlin_cross_section_data[1].n_radius[2] + 1 + 1

    #Use the local_buckling_xx_pos node geometry and reference stress from CUFSM (Mxx = 1).
    dx = diff(intelli_frame_purlin_line.local_buckling_xx_pos[1].CUFSM_data.node[1:web_index,2])
    dy = diff(intelli_frame_purlin_line.local_buckling_xx_pos[1].CUFSM_data.node[1:web_index,3])
    ds = sqrt.(dx.^2 .+ dy.^2)
    s = [0; cumsum(ds)]   #line coordinates around free flange

    #Integrate the reference stress (Mxx = 1.0) in the free flange to find the reference axial force.   
    stress = intelli_frame_purlin_line.local_buckling_xx_pos[1].CUFSM_data.node[1:web_index,8] 
    t = intelli_frame_purlin_line.inputs.purlin_cross_section_dimensions[1][2]
    P_unit = integrate(s, stress) * t

    # end

    P = P_unit .* Mxx

    #Scale the reference axial force along the purlin line to define the axial force in the free flange.
    #The sign convention for P is + (compression), - (tension) to match StructuresKit.BeamColumn.
    # dz = diff(intelli_frame_purlin_line.model.z)
    # P = Mesh.create_line_element_property_array(member_definitions, intelli_frame_purlin_line.model.m, dz, P_unit, 3, 1) .* Mxx

    return P

end

function calculate_intelli_frame_purlin_web_crippling_demand_to_capacity(intelli_frame_purlin_line)

    num_supports = size(intelli_frame_purlin_line.inputs.support_locations)[1]

    web_crippling_demand_to_capacity = Array{Float64}(undef, num_supports)

    for i=1:num_supports  #maximum of purlin and Hugger

        web_crippling_demand_to_capacity[i] = maximum([intelli_frame_purlin_line.purlin_web_crippling_demand_to_capacity[i], intelli_frame_purlin_line.intelli_frame_web_crippling_demand_to_capacity[i]])

    end

    return web_crippling_demand_to_capacity

end

function analysis(intelli_frame_purlin_line)

    z, Ix, Iy, Ixy, J, Cw, E, G, kx, kϕ, ay_kx, qx, qy, ax, ay, end_boundary_conditions, supports = IntelliFrame.thin_walled_beam_interface(intelli_frame_purlin_line)

    #Set up ThinWalledBeam model.
    intelli_frame_purlin_line.model = ThinWalledBeam.solve(z, Ix, Iy, Ixy, J, Cw, E, G, kx, kϕ, ay_kx, qx, qy, ax, ay, end_boundary_conditions, supports)

    # #Solve ThinWalledBeam model.
    # intelli_frame_purlin_line.model = ThinWalledBeam.solve(model)

    #Calculate purlin line internal forces and moments from deformations, add them to data structure.
    Mxx, Myy, Vxx, Vyy, T, B = PurlinLine.calculate_internal_forces(z, intelli_frame_purlin_line.model.outputs.u, intelli_frame_purlin_line.model.outputs.v, intelli_frame_purlin_line.model.outputs.ϕ, E, G, Ix, Iy, J, Cw)

    num_nodes = length(intelli_frame_purlin_line.model.inputs.z)
    P = zeros(Float64, num_nodes)  #No axial force in purlin for now.  Could be added later.

    #Add internal forces to data structure.
    intelli_frame_purlin_line.internal_forces = PurlinLine.InternalForceData(P, Mxx, Myy, Vxx, Vyy, T, B)

    #Translate purlin_line design variables to BeamColumn design variables.
    z, Af, Ixf, Iyf, Iof, Jf, Cwf, E, G, axf, ayf, kxf, kyf, kϕf, hxf, hyf, kH, end_boundary_conditions, supports, xof, yof = beam_column_interface(intelli_frame_purlin_line)

    #Calculate axial force in free flange.
    Pf = calculate_free_flange_axial_force(Mxx, intelli_frame_purlin_line)

    #Apply the shear flow based on the y-direction load along the purlin line free flange model.
    qxf = qy .* kH

    #The y-direction load is assumed to be zero in the free flange model.
    num_nodes = length(z)
    qyf = zeros(Float64, num_nodes)

 
    #Solve the free flange beam-column model with PlautBeamColumnElement (Plaut & Moen 2020, Thin-Walled
    #Structures 154, 106897).  The shear center offsets xof, yof of the free flange couple its axial force to
    #bending and twist; ThinWalledBeamColumn omitted these terms.  The springs act at (hxf, hyf) from the
    #free flange centroid.
    intelli_frame_purlin_line.free_flange_model = PlautBeamColumnElement.solve(z, Af, Ixf, Iyf, Iof, Jf, Cwf, E, G, axf, ayf, kxf, kyf, kϕf, hxf, hyf, qxf, qyf, Pf, end_boundary_conditions, supports; xo = xof, yo = yof)

    #Calculate internal forces in the free flange.
    Mxxf, Myyf, Vxxf, Vyyf, Tf, Bf = PurlinLine.calculate_internal_forces(z, intelli_frame_purlin_line.free_flange_model.outputs.u, intelli_frame_purlin_line.free_flange_model.outputs.v, intelli_frame_purlin_line.free_flange_model.outputs.ϕ, E, G, Ixf, Iyf, Jf, Cwf)

    #Add free flange internal forces to data structure.
    intelli_frame_purlin_line.free_flange_internal_forces = PurlinLine.InternalForceData(Pf, Mxxf, Myyf, Vxxf, Vyyf, Tf, Bf)

    #Calculate demand-to-capacity ratios for each of the purlin line limit states.
    intelli_frame_purlin_line.flexure_torsion_demand_to_capacity, eMnℓ_xx_all, eMnℓ_yy_all, eBn_all, eMnℓ_yy_free_flange_all = PurlinLine.calculate_flexure_torsion_demand_to_capacity(intelli_frame_purlin_line)
    intelli_frame_purlin_line.distortional_demand_to_capacity, eMnd_xx_all, intelli_frame_purlin_line.Β_distortional_gradient_factor = PurlinLine.calculate_distortional_buckling_demand_to_capacity(intelli_frame_purlin_line)
    intelli_frame_purlin_line.flexure_shear_demand_to_capacity, eMnℓ_xx_all, eVn_all = PurlinLine.calculate_flexure_shear_demand_to_capacity(intelli_frame_purlin_line)        
    intelli_frame_purlin_line.biaxial_bending_demand_to_capacity, eMnℓ_xx_all, eMnℓ_yy_all = PurlinLine.calculate_biaxial_bending_demand_to_capacity(intelli_frame_purlin_line)
    
    intelli_frame_purlin_line.intelli_frame_web_crippling_demand_to_capacity = calculate_intelli_frame_web_crippling_demand_to_capacity(intelli_frame_purlin_line)
    
    #Unpack purlin web crippling strength.
    ePn = [intelli_frame_purlin_line.purlin_web_crippling[i].ePn for i = 1:length(intelli_frame_purlin_line.purlin_web_crippling)]
    intelli_frame_purlin_line.purlin_web_crippling_demand_to_capacity = PurlinLine.calculate_web_crippling_demand_to_capacity(intelli_frame_purlin_line.inputs.support_locations, intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.internal_forces.Vyy, intelli_frame_purlin_line.support_reactions.Fyy, intelli_frame_purlin_line.inputs.purlin_frame_connections, ePn)
    
    
    intelli_frame_purlin_line.web_crippling_demand_to_capacity = calculate_intelli_frame_purlin_web_crippling_demand_to_capacity(intelli_frame_purlin_line)


    #Add expected strengths along purlin line to data structure.
    intelli_frame_purlin_line.expected_strengths = PurlinLine.ExpectedStrengths(eMnℓ_xx_all, eMnℓ_yy_all, eMnℓ_yy_free_flange_all, eMnd_xx_all, eVn_all, eBn_all)

    return intelli_frame_purlin_line

end


function calculate_intelli_frame_web_crippling_demand_to_capacity(intelli_frame_purlin_line)

    num_supports = length(intelli_frame_purlin_line.inputs.support_locations)

    Fyy = PurlinLine.calculate_support_reactions(intelli_frame_purlin_line.inputs.support_locations, intelli_frame_purlin_line.model.inputs.z, intelli_frame_purlin_line.internal_forces.Vyy)

    intelli_frame_purlin_line.support_reactions = PurlinLine.Reactions(Fyy)

    DC = zeros(Float64, num_supports)

    for i = 1:num_supports

        if intelli_frame_purlin_line.support_reactions.Fyy[i] <= 0.0

            DC[i] = 0.0   #uplift, no web crippling

        else

            #DC[i] = intelli_frame_purlin_line.support_reactions.Fyy[i]/intelli_frame_purlin_line.intelli_frame_web_crippling[i].ePn

            DC[i] = 0.0  #It seems that load is spread out enough so that Hugger crippling is not a problem, according to two span test results at least.

        end

    end

    return DC

end


function capacity(intelli_frame_purlin_line; verbose = false, max_iterations = 200)

    DC_tolerance = 0.01

    if intelli_frame_purlin_line.loading_direction == "gravity"

        load_sign = 1.0

    elseif intelli_frame_purlin_line.loading_direction =="uplift"

        load_sign = -1.0

    end

    #Run a very small pressure to get the test going.
    intelli_frame_purlin_line.applied_pressure = load_sign * 10^-6
    intelli_frame_purlin_line = IntelliFrame.analysis(intelli_frame_purlin_line)
    max_DC = PurlinLine.find_max_demand_to_capacity(intelli_frame_purlin_line)

    #Define initial residual.
    residual = 1.0 - abs(max_DC)

    num_iterations = 0

    verbose && println("iter 0: applied_pressure=$(intelli_frame_purlin_line.applied_pressure), max_DC=$max_DC, residual=$residual")

    while residual > DC_tolerance

        new_pressure = intelli_frame_purlin_line.applied_pressure / max_DC
        #intelli_frame_purlin_line.applied_pressure = intelli_frame_purlin_line.applied_pressure + (new_pressure - intelli_frame_purlin_line.applied_pressure) / 2
        intelli_frame_purlin_line.applied_pressure = new_pressure


        intelli_frame_purlin_line = IntelliFrame.analysis(intelli_frame_purlin_line)
        max_DC = PurlinLine.find_max_demand_to_capacity(intelli_frame_purlin_line)

        residual = abs(1.0 - abs(max_DC))

        num_iterations += 1

        verbose && println("iter $num_iterations: applied_pressure=$(intelli_frame_purlin_line.applied_pressure), max_DC=$max_DC, residual=$residual")

        if num_iterations >= max_iterations
            error("IntelliFrame.capacity did not converge within $max_iterations iterations " *
                  "(last applied_pressure=$(intelli_frame_purlin_line.applied_pressure), max_DC=$max_DC, residual=$residual) -- " *
                  "possible oscillation between governing failure modes; pass verbose=true to see the full iteration history.")
        end

    end

    intelli_frame_purlin_line.failure_limit_state, intelli_frame_purlin_line.failure_location = PurlinLine.identify_failure_limit_state(intelli_frame_purlin_line)


    return intelli_frame_purlin_line

end

end # module
