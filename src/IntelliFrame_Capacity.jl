# IntelliFrame_Capacity.jl — allowable roof pressure of the existing purlin line and of the IntelliFrame
# retrofit, for gravity and uplift, with the governing limit state, its location and the maximum deflection.
#
# Existing system: IntelliFrame.UI.existing_roof_UI_mapper -> PurlinLine.test (pressure iterated until the
# governing demand-to-capacity ratio along the line reaches 1.0).
# Retrofit: the steps of IntelliFrame.UI.retrofit_UI_mapper, with one addition between IntelliFrame.define and
# IntelliFrame.capacity -- the positive strong-axis local buckling moment of every segment (gross and net
# section) is replaced by the MINIMUM of IntelliFrame's combined purlin + IntelliFrame value and the bare
# IntelliFrame cFSM value (IntelliFrame_cFSM) converted to that segment's combined section through the
# critical stress at the IntelliFrame top fiber; the local-global flexural strengths are then recomputed.
# Nothing else in IntelliFrame.define depends on Mnℓ, so the rest of the model is unchanged.

module IntelliFrame_Capacity

using Printf
using CairoMakie
import PurlinLine
import IntelliFrame

export run_capacity_analysis

const KSI_TO_PSF = 144_000.0   # applied_pressure is in kip/in.²
const IMETCO_RED = RGBf(143 / 255, 26 / 255, 31 / 255)
const STEEL_GRAY = RGBf(107 / 255, 116 / 255, 128 / 255)

const LIMIT_STATE_LABELS = Dict(
    "strong axis flexure + weak axis flexure + lateral free flange deformation + torsion" => "Flexural + torsional interaction (AISI S100 H4.2)",
    "biaxial bending"       => "Flexure, biaxial bending (AISI S100 H1.2)",
    "flexure + shear"       => "Flexure + shear (AISI S100 H2.1)",
    "distortional buckling" => "Distortional buckling (AISI S100 F4)",
    "web crippling"         => "Web crippling (AISI S100 G5)",
)


# ── Inputs ─────────────────────────────────────────────────────────────────────

function line_inputs(inputs)
    m = inputs.intelli_frame_material
    return (spans = Tuple(Float64.(inputs.purlin_spans_ft)), laps = Tuple(Float64.(inputs.purlin_laps_ft)),
            assignment = Tuple(Int.(inputs.purlin_size_span_assignment)),
            types = (String(inputs.purlin_type_1), String(inputs.purlin_type_2)),
            spacing = Float64(inputs.purlin_spacing_ft), slope = Float64(inputs.roof_slope),
            existing_deck = String(inputs.existing_deck_type), new_deck = String(inputs.new_deck_type),
            frame_flange = Float64(inputs.frame_flange_width_in), connection = String(inputs.purlin_frame_connection),
            intelli_frame = String(inputs.intelli_frame_type),
            if_mat = [(Float64(m.E_ksi), Float64(m.nu), Float64(m.Fy_ksi), Float64(m.Fu_ksi))])
end

existing_model(li, db, direction) = IntelliFrame.UI.existing_roof_UI_mapper(li.spans, li.laps, li.spacing, li.slope, db.purlin_data,
    li.existing_deck, db.existing_deck_data, li.frame_flange, li.connection, li.types, li.assignment, direction)


# ── Governing (minimum) local buckling moment of the retrofit ──────────────────

"Bare IntelliFrame Mcrℓ as a moment on a combined section, via the critical stress at the IntelliFrame top fiber."
function bare_to_combined(M_bare, c_bare, I_bare, cs)
    c = maximum(cs.node_geometry[:, 2]) - cs.section_properties.yc
    f = M_bare * c_bare / I_bare
    return f * cs.section_properties.Ixx / c, f
end

"""
Replaces `local_buckling_xx_pos` / `local_buckling_xx_net_pos` of every segment by
the minimum of IntelliFrame's value and the converted bare-IntelliFrame (cFSM)
value, recomputes the local-global strengths, and returns one record per segment.
"""
function apply_governing_local_buckling!(ifl, cfsm)
    records = []
    for i in eachindex(ifl.inputs.segments)
        g_if, h_if = ifl.local_buckling_xx_pos[i], ifl.local_buckling_xx_net_pos[i]
        g_cf, f_g = bare_to_combined(cfsm.Mcrl_no_hole.Mcrl, cfsm.gross_section.c_top, cfsm.gross_section.Ixx, ifl.intelli_frame_purlin_cross_section_data[i])
        h_cf, f_h = bare_to_combined(cfsm.Mcrl_hole.Mcrl, cfsm.net_section.c_top, cfsm.net_section.Ixx, ifl.intelli_frame_purlin_net_cross_section_data[i])
        ifl.local_buckling_xx_pos[i]     = PurlinLine.ElasticBucklingData(g_if.CUFSM_data, g_if.Lcr, min(g_if.Mcr, g_cf))
        ifl.local_buckling_xx_net_pos[i] = PurlinLine.ElasticBucklingData(h_if.CUFSM_data, h_if.Lcr, min(h_if.Mcr, h_cf))
        push!(records, (segment = i, length_in = ifl.inputs.segments[i][1],
                        gross = (intelliframe = g_if.Mcr, cfsm_combined = g_cf, f_crl = f_g, governing = min(g_if.Mcr, g_cf),
                                 source = g_if.Mcr <= g_cf ? "IntelliFrame combined model" : "cFSM bare IntelliFrame"),
                        hole  = (intelliframe = h_if.Mcr, cfsm_combined = h_cf, f_crl = f_h, governing = min(h_if.Mcr, h_cf),
                                 source = h_if.Mcr <= h_cf ? "IntelliFrame combined model" : "cFSM bare IntelliFrame")))
    end
    ifl.local_global_flexural_strength_xx_no_hole, ifl.local_global_flexural_strength_xx_hole, ifl.local_global_flexural_strength_xx,
        ifl.local_global_flexural_strength_yy, ifl.local_global_flexural_strength_free_flange_yy = IntelliFrame.calculate_local_global_flexural_strength(ifl)
    return records
end

"""
`IntelliFrame.UI.retrofit_UI_mapper` with the governing local buckling moment
applied between `define` and `capacity`. `pl` is a fresh existing purlin line
(the mapper overwrites its deck details).
"""
function retrofit_model(pl, li, db, direction, cfsm)
    d = db.intelli_frame_data[findfirst(==(li.intelli_frame), db.intelli_frame_data.section_name), :]
    if_dims = [tuple([d[i] for i = 2:13]...)]
    punch_out = [(d[:punchout_width], d[:punchout_height])]
    nd = db.new_deck_data[findfirst(==(li.new_deck), db.new_deck_data.deck_name), :]
    new_deck = li.new_deck == "no deck" ? ["no deck"] :
               !ismissing(nd[3]) ? ("screw-fastened", nd[2], nd[3], nd[4], nd[5]) : ("vertical leg standing seam", nd[7])
    segments = [(s[1], s[2], s[3], 1, 1, 1, 1) for s in pl.inputs.segments]
    ed = db.existing_deck_data[findfirst(==(li.existing_deck), db.existing_deck_data.deck_name), :]
    pl.inputs.deck_details = ("screw-fastened", ed[2], 3.0, 0.212, 2.5)   # IntelliFrame screwed through the existing deck at close spacing
    ifl = IntelliFrame.define(pl.inputs.design_code, segments, pl.inputs.spacing, pl.inputs.roof_slope, pl.inputs.cross_section_dimensions,
        if_dims, punch_out, pl.inputs.material_properties, li.if_mat, pl.inputs.deck_details, pl.inputs.deck_material_properties,
        new_deck, (29500.0, 0.30, 55.0, 70.0), pl.inputs.frame_flange_width, pl.inputs.support_locations,
        pl.inputs.purlin_frame_connections, pl.inputs.bridging_locations)
    lb = apply_governing_local_buckling!(ifl, cfsm)
    ifl.loading_direction = direction
    return IntelliFrame.capacity(ifl), lb
end


# ── Results ────────────────────────────────────────────────────────────────────

"Where along the line `z` (in.) is: at a support, or in a span with its distance from the left support."
function describe_location(z, supports)
    for (k, s) in enumerate(supports)
        abs(z - s) <= 1.0 && return k == 1 || k == length(supports) ? "at end support $k" : "at interior support $k"
    end
    k = findlast(s -> s < z, supports)
    return @sprintf("in span %d, %.1f ft from support %d", k, (z - supports[k]) / 12, k)
end

span_of(z, supports) = clamp(something(findlast(s -> s <= z, supports), 1), 1, length(supports) - 1)

"Allowable pressure, governing limit state, failure location, maximum deflection and the along-line curves of one solved line."
function case_results(m, direction)
    z = m.model.inputs.z
    v = m.model.outputs.v
    supports = m.inputs.support_locations
    iv = argmax(abs.(v))
    k = span_of(z[iv], supports)
    L_span = supports[k+1] - supports[k]
    p = abs(m.applied_pressure) * KSI_TO_PSF
    DC = (flexure_torsion = m.flexure_torsion_demand_to_capacity.demand_to_capacity,
          biaxial = m.biaxial_bending_demand_to_capacity.demand_to_capacity,
          flexure_shear = m.flexure_shear_demand_to_capacity,
          distortional = replace(m.distortional_demand_to_capacity, NaN => 0.0))
    return (
        direction = direction,
        allowable_pressure_psf = p,
        allowable_line_load_plf = p * m.inputs.spacing / 12,
        limit_state = LIMIT_STATE_LABELS[m.failure_limit_state], limit_state_raw = m.failure_limit_state,
        failure_location_ft = m.failure_location / 12, failure_location = describe_location(m.failure_location, supports),
        max_deflection_in = abs(v[iv]), max_deflection_location_ft = z[iv] / 12, max_deflection_span = k,
        max_deflection_ratio = L_span / abs(v[iv]),
        curves = (z_ft = z ./ 12, v_in = v, Mxx = m.internal_forces.Mxx, eMn_xx = m.expected_strengths.eMnℓ_xx,
                  DC = DC),
        supports_ft = supports ./ 12,
    )
end


# ── Figures ────────────────────────────────────────────────────────────────────

"Thickness band (outer face to inner face) of one open branch, as a closed polygon."
function band(X, Y, t)
    cs = [[X[i], Y[i]] for i in eachindex(X)]
    nrm = IntelliFrame.UI.CrossSectionGeometry.calculate_cross_section_unit_node_normals(cs)
    o = IntelliFrame.UI.CrossSectionGeometry.get_coords_along_node_normals(cs, nrm, t / 2)
    n = IntelliFrame.UI.CrossSectionGeometry.get_coords_along_node_normals(cs, nrm, -t / 2)
    return Point2f.(vcat([p[1] for p in o], reverse([p[1] for p in n])), vcat([p[2] for p in o], reverse([p[2] for p in n])))
end

function section_axis(fig, pos, title)
    ax = Axis(fig[pos...]; title = title, aspect = DataAspect(), titlesize = 15)
    hidedecorations!(ax); hidespines!(ax)
    return ax
end

"Three profile figures: existing purlin, IntelliFrame, and the retrofit assembly (with both decks), drawn exactly as the model is analysed."
function plot_profiles(pl, ifl, li, out_dir)
    mkpath(out_dir)
    si = pl.inputs.segments[1][3]
    tp = pl.inputs.cross_section_dimensions[si][2]
    P = pl.cross_section_data[si].node_geometry
    C = ifl.intelli_frame_purlin_cross_section_data[1].node_geometry   # combined model (purlin nodes first, then the IntelliFrame as oriented on it)
    np = size(P, 1)
    figs = Dict{String, String}()

    fig = Figure(size = (520, 620), backgroundcolor = :white)
    ax = section_axis(fig, (1, 1), "Existing purlin — $(pl.inputs.cross_section_dimensions[si][1])")
    poly!(ax, band(P[:, 1], P[:, 2], tp); color = STEEL_GRAY)
    save(joinpath(out_dir, "existing_purlin.png"), fig; px_per_unit = 2); figs["existing_purlin"] = "existing_purlin.png"

    I = C[np+1:end, :]   # the IntelliFrame alone, in the orientation it takes on the purlin
    ti = ifl.inputs.intelli_frame_cross_section_dimensions[1][1]
    fig = Figure(size = (520, 420), backgroundcolor = :white)
    ax = section_axis(fig, (1, 1), "IntelliFrame — $(li.intelli_frame)")
    poly!(ax, band(I[:, 1], I[:, 2], ti); color = IMETCO_RED)
    save(joinpath(out_dir, "intelliframe.png"), fig; px_per_unit = 2); figs["intelliframe"] = "intelliframe.png"

    Pc, Ic = C[1:np, :], C[np+1:end, :]
    fig = Figure(size = (620, 760), backgroundcolor = :white)
    ax = section_axis(fig, (1, 1), "Retrofit — IntelliFrame on the existing purlin")
    xs = extrema(C[:, 1]); w = xs[2] - xs[1]
    y_old, y_new = maximum(Pc[:, 2]) + tp / 2, maximum(Ic[:, 2]) + ti / 2
    lines!(ax, [xs[1] - 0.6w, xs[2] + 0.6w], [y_old, y_old]; color = :gray55, linewidth = 3, linestyle = :dash)
    lines!(ax, [xs[1] - 0.6w, xs[2] + 0.6w], [y_new, y_new]; color = :gray25, linewidth = 3)
    poly!(ax, band(Pc[:, 1], Pc[:, 2], tp); color = STEEL_GRAY)
    poly!(ax, band(Ic[:, 1], Ic[:, 2], ti); color = IMETCO_RED)
    text!(ax, xs[2] + 0.6w, y_new; text = "new deck ($(li.new_deck))", align = (:right, :bottom), offset = (0, 4), fontsize = 12)
    text!(ax, xs[2] + 0.6w, y_old; text = "existing deck ($(li.existing_deck))", align = (:right, :bottom), offset = (0, 4), fontsize = 12, color = :gray40)
    Legend(fig[2, 1], [PolyElement(color = STEEL_GRAY), PolyElement(color = IMETCO_RED)], ["Existing purlin", "IntelliFrame"];
           orientation = :horizontal, framevisible = false)
    save(joinpath(out_dir, "retrofit_assembly.png"), fig; px_per_unit = 2); figs["retrofit_assembly"] = "retrofit_assembly.png"
    return figs
end

"Along-line figure of one case: demand-to-capacity ratios with the failure point, strong-axis moment vs. strength, and vertical deflection."
function plot_case(r, title, path)
    c = r.curves
    fig = Figure(size = (1040, 900), fontsize = 13, backgroundcolor = :white)
    Label(fig[0, 1:2], title; fontsize = 16, font = :bold, tellwidth = false)
    # legends live in their own column to the right of each panel so they never cover the curves
    axes = [Axis(fig[k, 1]; xlabel = k == 3 ? "Distance along the purlin line (ft)" : "", ylabel = yl,
                 xgridstyle = :dot, ygridstyle = :dot)
            for (k, yl) in enumerate(("Demand / capacity", "Strong-axis moment Mx (kip-in.)", "Vertical deflection (in.)"))]
    legend_kw = (framevisible = false, labelsize = 11, rowgap = 2, patchsize = (28, 12), halign = :left, valign = :center, tellheight = false)

    ax = axes[1]
    vlines!(ax, r.supports_ft; color = :gray60, linestyle = :dot, label = "Supports")
    lines!(ax, c.z_ft, c.DC.flexure_torsion; color = IMETCO_RED, linewidth = 2.5, label = "Flexural + torsional (H4.2)")
    lines!(ax, c.z_ft, c.DC.biaxial; color = :steelblue, linewidth = 2, label = "Biaxial bending (H1.2)")
    lines!(ax, c.z_ft, c.DC.flexure_shear; color = :darkorange, linewidth = 2, label = "Flexure + shear (H2.1)")
    lines!(ax, c.z_ft, c.DC.distortional; color = :seagreen, linewidth = 2, label = "Distortional buckling (F4)")
    hlines!(ax, [1.0]; color = :black, linestyle = :dash, label = "D/C = 1.0 (allowable)")
    scatter!(ax, [r.failure_location_ft], [1.0]; color = :black, marker = :star5, markersize = 20, label = "Governing location")
    ylims!(ax, 0, 1.15)
    Legend(fig[1, 2], ax; legend_kw...)

    ax = axes[2]
    vlines!(ax, r.supports_ft; color = :gray60, linestyle = :dot)
    lines!(ax, c.z_ft, c.Mxx; color = :black, linewidth = 2, label = "Mx at the allowable pressure")
    lines!(ax, c.z_ft, sign.(c.Mxx) .* c.eMn_xx; color = IMETCO_RED, linestyle = :dash, linewidth = 2,
           label = "Allowable strength Mnℓ\n(positive bending above, negative below)")
    hlines!(ax, [0.0]; color = :gray40, linewidth = 0.8)
    Legend(fig[2, 2], ax; legend_kw...)

    ax = axes[3]
    iv = argmax(abs.(c.v_in))
    vlines!(ax, r.supports_ft; color = :gray60, linestyle = :dot)
    lines!(ax, c.z_ft, c.v_in; color = :steelblue, linewidth = 2.5, label = "Deflection at the allowable pressure")
    scatter!(ax, [c.z_ft[iv]], [c.v_in[iv]]; color = :red, markersize = 12,
             label = @sprintf("Maximum: %.2f in. (L/%d)\nat %.1f ft", r.max_deflection_in, round(Int, r.max_deflection_ratio), c.z_ft[iv]))
    hlines!(ax, [0.0]; color = :gray40, linewidth = 0.8)
    Legend(fig[3, 2], ax; legend_kw...)

    linkxaxes!(axes...)
    colsize!(fig.layout, 2, Fixed(250))
    colgap!(fig.layout, 12)
    rowgap!(fig.layout, 10)
    save(path, fig; px_per_unit = 1.5)
    return path
end

"""
The combined purlin + IntelliFrame finite strip models of segment `i` exactly as
handed to CUFSM: the gross section (section properties, Mcrℓ, Mcrd) and the net
section at the punch-out (Mcrℓ,hole at L = L_hole). Nodes are the CUFSM nodes and
lines the strips (`element_definitions`); the purlin and IntelliFrame are separate
strips, tied at one node pair (IntelliFrame bottom-flange centre slaved to the
purlin top-flange centre -- gross model only, that node is removed by the
punch-out) with the deck springs at the two top-flange centre nodes.
"""
function plot_cufsm_sections(ifl, path; i = 1)
    seg = ifl.inputs.segments[i]
    pcs, hcs = ifl.purlin_cross_section_data[seg[3]], ifl.intelli_frame_cross_section_data[seg[4]]
    np = size(pcs.node_geometry, 1)
    pn, pnr, hn, hnr = pcs.n, pcs.n_radius, hcs.n, hcs.n_radius
    purlin_top   = sum(pn[1:3]) + sum(pnr[1:3]) + floor(Int, pn[4] / 2) + 1
    if_bottom    = np + floor(Int, hn[1] / 2) + 1
    if_top_gross = np + sum(hn[1:2]) + sum(hnr[1:2]) + floor(Int, hn[3] / 2) + 1
    t_if = ifl.inputs.intelli_frame_cross_section_dimensions[seg[4]][1]
    L_hole, h_hole = ifl.inputs.intelli_frame_punch_out_dimensions[seg[7]]
    gross, net = ifl.intelli_frame_purlin_cross_section_data[i], ifl.intelli_frame_purlin_net_cross_section_data[i]
    if_top_net = size(net.node_geometry, 1) - hn[end] - hnr[end] - floor(Int, hn[end-1] / 2)   # as in calculate_net_section_local_buckling_properties

    G = gross.node_geometry
    pad = 0.5
    lims = (minimum(G[:, 1]) - pad - 0.8, maximum(G[:, 1]) + pad, minimum(G[:, 2]) - pad, maximum(G[:, 2]) + pad)

    function draw!(ax, cs)
        N, E = cs.node_geometry, cs.element_definitions
        for k in 1:size(E, 1)
            a, b = Int(E[k, 1]), Int(E[k, 2])
            lines!(ax, [N[a, 1], N[b, 1]], [N[a, 2], N[b, 2]]; color = a <= np ? STEEL_GRAY : IMETCO_RED, linewidth = 2.5)
        end
        scatter!(ax, N[1:np, 1], N[1:np, 2]; color = STEEL_GRAY, markersize = 5)
        scatter!(ax, N[np+1:end, 1], N[np+1:end, 2]; color = IMETCO_RED, markersize = 5)
        sp = cs.section_properties
        scatter!(ax, [sp.xc], [sp.yc]; marker = :cross, color = :black, markersize = 14)
        text!(ax, sp.xc, sp.yc; text = @sprintf("  centroid, y = %.2f in.", sp.yc), fontsize = 10, align = (:left, :center))
    end
    spring!(ax, N, k) = scatter!(ax, [N[k, 1]], [N[k, 2]]; marker = :utriangle, color = :seagreen, markersize = 15, strokecolor = :black, strokewidth = 1)

    fig = Figure(size = (1150, 780), fontsize = 12, backgroundcolor = :white)
    ax1 = Axis(fig[1, 1]; title = "Gross section — section properties, Mcrℓ, Mcrd", aspect = DataAspect(), limits = lims,
               xlabel = "x (in.)", ylabel = "y (in.)",
               subtitle = @sprintf("A = %.3f in.², Ixx = %.2f in.⁴, %d nodes, %d strips", gross.section_properties.A, gross.section_properties.Ixx, size(G, 1), size(gross.element_definitions, 1)), subtitlesize = 10)
    draw!(ax1, gross)
    spring!(ax1, G, purlin_top); spring!(ax1, G, if_top_gross)
    scatter!(ax1, [G[if_bottom, 1]], [G[if_bottom, 2]]; marker = :diamond, color = :black, markersize = 14)

    Nn = net.node_geometry
    ax2 = Axis(fig[1, 2]; title = "Net section at the punch-out — Mcrℓ,hole at L = L_hole", aspect = DataAspect(), limits = lims,
               xlabel = "x (in.)", ylabel = "y (in.)",
               subtitle = @sprintf("A = %.3f in.², Ixx = %.2f in.⁴, %d nodes, %d strips", net.section_properties.A, net.section_properties.Ixx, size(Nn, 1), size(net.element_definitions, 1)), subtitlesize = 10)
    lines!(ax2, G[np+1:end, 1], G[np+1:end, 2]; color = (IMETCO_RED, 0.45), linestyle = :dash, linewidth = 2)   # removed part, for reference
    draw!(ax2, net)
    spring!(ax2, Nn, purlin_top); spring!(ax2, Nn, if_top_net)
    # punch-out height, measured from the IntelliFrame bottom face
    y_face = G[if_bottom, 2] - t_if / 2
    x_dim = lims[1] + 0.35
    lines!(ax2, [x_dim, x_dim], [y_face, y_face + h_hole]; color = :black, linewidth = 1.2)
    scatter!(ax2, [x_dim, x_dim], [y_face, y_face + h_hole]; marker = [:utriangle, :dtriangle], color = :black, markersize = 9)
    text!(ax2, x_dim - 0.08, y_face + h_hole / 2; text = @sprintf("punch-out %.2f in. high × %.2f in. long", h_hole, L_hole),
          rotation = π / 2, align = (:center, :bottom), fontsize = 10)
    hlines!(ax2, [y_face + h_hole]; color = (:red, 0.5), linestyle = :dot, linewidth = 1.2)

    elems = [LineElement(color = STEEL_GRAY, linewidth = 2.5), LineElement(color = IMETCO_RED, linewidth = 2.5),
             LineElement(color = (IMETCO_RED, 0.45), linestyle = :dash, linewidth = 2),
             MarkerElement(color = :black, marker = :diamond, markersize = 14),
             MarkerElement(color = :seagreen, marker = :utriangle, markersize = 15, strokecolor = :black, strokewidth = 1),
             MarkerElement(color = :black, marker = :cross, markersize = 14)]
    labels = ["Purlin strips (CUFSM nodes shown)", "IntelliFrame strips", "Removed by the punch-out",
              "Tied node pair: IntelliFrame bottom flange ↔ purlin top flange (x, y, z, θ)",
              "Deck springs kx, kϕ (existing deck on purlin, new deck on IntelliFrame)", "Centroid"]
    Legend(fig[2, 1:2], elems, labels; orientation = :horizontal, nbanks = 2, framevisible = false, labelsize = 10)
    Label(fig[3, 1:2], @sprintf("Segment %d. The two parts are separate open strips in one CUFSM model; in the net section the tie is gone with the bottom flange, so they share only the composite stress distribution.", i);
          fontsize = 10, color = :gray30)
    save(path, fig; px_per_unit = 2)
    return path
end

"""
Span configuration of the purlin line, in the style of the PurlinLine web app:
one rectangle per purlin (true purlin depth, extended past the interior supports
by the lap lengths, consecutive purlins offset vertically so the laps show), the
frame supports as I-shapes of the frame flange width, span dimensions below and
the uniform roof pressure above. `laps_ft` holds two entries per interior
support (left side, right side), as in `inputs.purlin_laps_ft`. True scale.
"""
function plot_span_configuration(spans_ft, laps_ft, frame_flange_in, purlin_depth_in, path; vex = 3.0)
    n = length(spans_ft)
    supports = vcat(0.0, cumsum(collect(Float64, spans_ft)))        # ft, true horizontal scale
    L = supports[end]
    h  = vex * purlin_depth_in / 12                                  # purlin depth, drawn with vertical exaggeration `vex`
    dy = 0.3h                                                        # vertical offset between lapped purlins
    w  = frame_flange_in / 12                                        # support flange width (true), ft
    hb = 2.0h; tf = 0.1h; tw = 0.15w                                 # support I-shape (schematic depth)
    slate = RGBf(0.118, 0.161, 0.231)
    lap_left(k)  = k == 1 ? 0.0 : Float64(laps_ft[2k - 3])            # purlin k past interior support k-1
    lap_right(k) = k == n ? 0.0 : Float64(laps_ft[2k])                # purlin k past interior support k

    y_top_support = -dy / 2 - 0.1h
    y_num   = y_top_support - hb - 0.15h                             # support numbers
    y_dim   = y_top_support - hb - 1.1h                              # span dimension line
    y_lap   = h + dy / 2 + 0.35h                                     # lap dimension line
    y_tip   = h + dy / 2 + 1.5h                                      # load arrow tips
    y_tail  = y_tip + 1.0h

    # small canvas on purpose: the figure is printed at page width, so text sizes here set the printed size (~8 pt)
    fig = Figure(size = (900, 240), fontsize = 15, backgroundcolor = :white)
    ax = Axis(fig[1, 1]; aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    rect!(x1, x2, y1, y2; kw...) = lines!(ax, [x1, x2, x2, x1, x1], [y1, y1, y2, y2, y1]; kw...)
    frect!(x1, x2, y1, y2) = poly!(ax, Point2f[(x1, y1), (x2, y1), (x2, y2), (x1, y2)]; color = slate)
    tick!(x, y, half; kw...) = lines!(ax, [x, x], [y - half, y + half]; color = slate, linewidth = 1, kw...)

    # purlins, alternating up/down so the laps are visible
    for k in 1:n
        y0 = isodd(k) ? dy / 2 : -dy / 2
        rect!(supports[k] - lap_left(k), supports[k+1] + lap_right(k), y0, y0 + h; color = slate, linewidth = 2.2)
    end
    # lap dimensions above the interior supports
    for j in 1:(n - 1)
        s = supports[j+1]; a, b = s - Float64(laps_ft[2j - 1]), s + Float64(laps_ft[2j])
        lines!(ax, [a, b], [y_lap, y_lap]; color = slate, linewidth = 1)
        tick!(a, y_lap, 0.12h); tick!(b, y_lap, 0.12h); tick!(s, y_lap, 0.12h; linestyle = :dot)
        text!(ax, s, y_lap + 0.15h; text = @sprintf("lap %.1f + %.1f ft", laps_ft[2j - 1], laps_ft[2j]), align = (:center, :bottom), fontsize = 15, color = slate)
    end
    # frame supports (I-shapes) with their numbers
    for (k, s) in enumerate(supports)
        frect!(s - w / 2, s + w / 2, y_top_support - tf, y_top_support)
        frect!(s - tw / 2, s + tw / 2, y_top_support - hb + tf, y_top_support - tf)
        frect!(s - w / 2, s + w / 2, y_top_support - hb, y_top_support - hb + tf)
        text!(ax, s, y_num; text = "Support $k", align = (:center, :top), fontsize = 15, color = slate)
    end
    # span dimensions
    for k in 1:n
        a, b = supports[k], supports[k+1]
        lines!(ax, [a, b], [y_dim, y_dim]; color = slate, linewidth = 1)
        tick!(a, y_dim, 0.2h); tick!(b, y_dim, 0.2h)
        text!(ax, (a + b) / 2, y_dim - 0.25h; text = @sprintf("%.1f ft", spans_ft[k]), align = (:center, :top), fontsize = 17, color = slate)
    end
    # uniform roof pressure
    xs = collect(range(0.0, L, length = round(Int, L / 2.5) + 1))
    lines!(ax, [0.0, L], [y_tail, y_tail]; color = slate, linewidth = 1.2)
    arrows2d!(ax, xs, fill(y_tail, length(xs)), zeros(length(xs)), fill(y_tip - y_tail, length(xs));
              color = slate, shaftwidth = 1.2, tiplength = 8, tipwidth = 7)
    text!(ax, L / 2, y_tail + 0.15h; text = "Uniform roof pressure (gravity shown; uplift acts upward)", align = (:center, :bottom), fontsize = 17, color = slate)

    xlims!(ax, -0.04L, 1.04L)
    ylims!(ax, y_dim - 1.1h, y_tail + 1.0h)
    save(path, fig; px_per_unit = 2)
    return path
end

"Summary bar chart: allowable pressure, existing vs. retrofit, for gravity and uplift."
function plot_summary(cases, path)
    fig = Figure(size = (560, 430), fontsize = 14, backgroundcolor = :white)
    ax = Axis(fig[1, 1]; ylabel = "Allowable roof pressure (psf)", xticks = (1:2, ["Gravity", "Uplift"]), xgridvisible = false)
    vals = [cases.existing_gravity.allowable_pressure_psf, cases.retrofit_gravity.allowable_pressure_psf,
            cases.existing_uplift.allowable_pressure_psf, cases.retrofit_uplift.allowable_pressure_psf]
    x = [1, 1, 2, 2]; grp = [1, 2, 1, 2]
    barplot!(ax, x, vals; dodge = grp, width = 0.5, dodge_gap = 0.06, color = [STEEL_GRAY, IMETCO_RED, STEEL_GRAY, IMETCO_RED],
             bar_labels = [@sprintf("%.1f", v) for v in vals], label_size = 13)
    ylims!(ax, 0, 1.2 * maximum(vals))
    xlims!(ax, 0.45, 2.55)
    Legend(fig[2, 1], [PolyElement(color = STEEL_GRAY), PolyElement(color = IMETCO_RED)], ["Existing", "IRF retrofit"];
           orientation = :horizontal, framevisible = false)
    save(path, fig; px_per_unit = 1.5)
    return path
end


# ── Driver ─────────────────────────────────────────────────────────────────────

# ── Design detail (for the detailed report) ────────────────────────────────────

_props(sp)  = (A = sp.A, xc = sp.xc, yc = sp.yc, Ixx = sp.Ixx, Iyy = sp.Iyy, Ixy = sp.Ixy, J = sp.J, Cw = sp.Cw, xs = sp.xs, ys = sp.ys)
_bracing(b) = (kx = b.kx, kphi = b.kϕ, kphi_dist = b.kϕ_dist, Lcrd = b.Lcrd)
_flex(f)    = (Mne = f.Mne, Mnl_pos = f.Mnℓ_pos, Mnl_neg = f.Mnℓ_neg, eMnl_pos = f.eMnℓ_pos, eMnl_neg = f.eMnℓ_neg)
_yield(y)   = (S_pos = y.S_pos, S_neg = y.S_neg, My_pos = y.My_pos, My_neg = y.My_neg, My = y.My)
_dist(d)    = (Mnd_pos = d.Mnd_pos, Mnd_neg = d.Mnd_neg, eMnd_pos = d.eMnd_pos, eMnd_neg = d.eMnd_neg)
_tors(t)    = (Wn = t.Wn, Bn = t.Bn, eBn = t.eBn)
_shear(v)   = (h_flat = v.h_flat, Vcr = v.Vcr, Vy = v.Vy, Vn = v.Vn, eVn = v.eVn)
_wc(w, k, z) = (support = k, z_ft = z / 12, load_location = w.load_location, N = w.N, ePn = w.ePn)

"Per-segment design detail of the existing purlin line (a PurlinLine.Model)."
function existing_segment_detail(pl, i)
    si = pl.inputs.segments[i][3]
    return (segment = i, length_ft = pl.inputs.segments[i][1] / 12, section_index = si,
        properties = _props(pl.cross_section_data[si].section_properties),
        bracing = _bracing(pl.bracing_data[i]),
        buckling = (Mcrl_xx_pos = pl.local_buckling_xx_pos[i].Mcr, Lcrl_xx_pos = pl.local_buckling_xx_pos[i].Lcr,
                    Mcrl_xx_neg = pl.local_buckling_xx_neg[i].Mcr, Lcrl_xx_neg = pl.local_buckling_xx_neg[i].Lcr,
                    Mcrl_yy_pos = pl.local_buckling_yy_pos[i].Mcr, Mcrl_yy_neg = pl.local_buckling_yy_neg[i].Mcr,
                    Mcrd_xx_pos = pl.distortional_buckling_xx_pos[i].Mcr, Lcrd_xx_pos = pl.distortional_buckling_xx_pos[i].Lcr,
                    Mcrd_xx_neg = pl.distortional_buckling_xx_neg[i].Mcr),
        yield = _yield(pl.yielding_flexural_strength_xx[i]), yield_yy = _yield(pl.yielding_flexural_strength_yy[i]),
        flexure_xx = _flex(pl.local_global_flexural_strength_xx[i]), flexure_yy = _flex(pl.local_global_flexural_strength_yy[i]),
        distortional = _dist(pl.distortional_flexural_strength_xx[i]), torsion = _tors(pl.torsion_strength[i]), shear = _shear(pl.shear_strength[i]))
end

"Per-segment design detail of the retrofit (an IntelliFrameObject, after the governing Mcrℓ has been applied)."
function retrofit_segment_detail(ifl, i)
    return (segment = i, length_ft = ifl.inputs.segments[i][1] / 12, section_index = ifl.inputs.segments[i][3],
        properties = _props(ifl.intelli_frame_purlin_cross_section_data[i].section_properties),
        net_properties = _props(ifl.intelli_frame_purlin_net_cross_section_data[i].section_properties),
        bracing = _bracing(ifl.bracing_data[i]), new_deck_bracing = _bracing(ifl.new_deck_bracing_data[i]),
        buckling = (Mcrl_xx_pos = ifl.local_buckling_xx_pos[i].Mcr, Lcrl_xx_pos = ifl.local_buckling_xx_pos[i].Lcr,
                    Mcrl_xx_net_pos = ifl.local_buckling_xx_net_pos[i].Mcr,
                    Mcrl_xx_neg = ifl.local_buckling_xx_neg[i].Mcr, Lcrl_xx_neg = ifl.local_buckling_xx_neg[i].Lcr,
                    Mcrl_yy_pos = ifl.local_buckling_yy_pos[i].Mcr, Mcrl_yy_neg = ifl.local_buckling_yy_neg[i].Mcr,
                    Mcrd_xx_pos = ifl.distortional_buckling_xx_pos[i].Mcr, Lcrd_xx_pos = ifl.distortional_buckling_xx_pos[i].Lcr,
                    Mcrd_xx_net_pos = ifl.distortional_buckling_xx_net_pos[i].Mcr,
                    Mcrd_xx_neg = ifl.distortional_buckling_xx_neg[i].Mcr),
        yield = _yield(ifl.yielding_flexural_strength_xx[i]), yield_net = _yield(ifl.yielding_flexural_strength_xx_net[i]),
        yield_yy = _yield(ifl.yielding_flexural_strength_yy[i]),
        flexure_xx = _flex(ifl.local_global_flexural_strength_xx[i]),
        flexure_xx_no_hole = _flex(ifl.local_global_flexural_strength_xx_no_hole[i]),
        flexure_xx_hole = _flex(ifl.local_global_flexural_strength_xx_hole[i]),
        flexure_yy = _flex(ifl.local_global_flexural_strength_yy[i]),
        distortional = _dist(ifl.distortional_flexural_strength_xx[i]), torsion = _tors(ifl.torsion_strength[i]), shear = _shear(ifl.shear_strength[i]))
end

"Everything the detailed report needs beyond the headline results: materials, decks, purlin section dimensions, and the per-segment and per-support design values of both systems."
function design_detail(pl, ifl, li)
    n_types = maximum(li.assignment)
    purlin_sections = [(index = k, role = k <= n_types ? "span" : "lap", shape = d[1], t = d[2], D_bot = d[3], B_bottom = d[4], H = d[5],
                        B_top = d[6], D_top = d[7], theta_bottom_lip = d[8], theta_bottom_flange = d[9], theta_web = d[10],
                        theta_top_flange = d[11], theta_top_lip = d[12], r1 = d[13], r2 = d[14], r3 = d[15], r4 = d[16])
                       for (k, d) in enumerate(pl.inputs.cross_section_dimensions)]
    pm, im = pl.inputs.material_properties[1], li.if_mat[1]
    sup = pl.inputs.support_locations
    return (purlin_material = (E = pm[1], nu = pm[2], Fy = pm[3], Fu = pm[4]),
            intelli_frame_material = (E = im[1], nu = im[2], Fy = im[3], Fu = im[4]),
            existing_deck = string.(collect(pl.inputs.deck_details)), new_deck = string.(collect(ifl.inputs.new_deck_details)),
            purlin_sections = purlin_sections,
            existing = [existing_segment_detail(pl, i) for i in eachindex(pl.inputs.segments)],
            retrofit = [retrofit_segment_detail(ifl, i) for i in eachindex(ifl.inputs.segments)],
            existing_web_crippling = [_wc(pl.web_crippling[k], k, sup[k]) for k in eachindex(sup)],
            retrofit_web_crippling = [_wc(ifl.purlin_web_crippling[k], k, sup[k]) for k in eachindex(sup)])
end


"""
    run_capacity_analysis(inputs, output_dir, cfsm)

Allowable pressure, governing limit state and location, and maximum deflection
of the existing and retrofitted purlin line for gravity and uplift. Figures go
to `output_dir/figures/capacity/` (paths in the result are relative to
`output_dir`).
"""
function run_capacity_analysis(inputs, output_dir, cfsm; intelli_frame_data = nothing)
    li = line_inputs(inputs)
    db = IntelliFrame.UI.load_databases()
    intelli_frame_data === nothing || (db = merge(db, (intelli_frame_data = intelli_frame_data,)))   # same table the cFSM step used
    fig_dir = joinpath(output_dir, "figures", "capacity")
    mkpath(fig_dir)
    rel(f) = "figures/capacity/" * f

    cases = Dict{Symbol, Any}()
    lb = nothing
    pl_g = ifl_g = nothing
    for dir in ("gravity", "uplift")
        println("  existing purlin line, $dir …"); flush(stdout)
        pl = existing_model(li, db, dir)
        println("  IntelliFrame retrofit, $dir …"); flush(stdout)
        ifl, lb = retrofit_model(deepcopy(pl), li, db, dir, cfsm)
        cases[Symbol("existing_", dir)] = case_results(pl, dir)
        cases[Symbol("retrofit_", dir)] = case_results(ifl, dir)
        dir == "gravity" && (pl_g = pl; ifl_g = ifl)
        @printf("    existing %.1f psf (%s)  |  retrofit %.1f psf (%s)\n",
                cases[Symbol("existing_", dir)].allowable_pressure_psf, cases[Symbol("existing_", dir)].limit_state_raw,
                cases[Symbol("retrofit_", dir)].allowable_pressure_psf, cases[Symbol("retrofit_", dir)].limit_state_raw)
    end
    cases = NamedTuple(cases)

    profiles = Dict(k => rel(v) for (k, v) in plot_profiles(pl_g, ifl_g, li, fig_dir))
    plot_cufsm_sections(ifl_g, joinpath(fig_dir, "cufsm_combined_sections.png"))
    profiles["cufsm_sections"] = rel("cufsm_combined_sections.png")
    plot_span_configuration(li.spans, li.laps, li.frame_flange, pl_g.inputs.cross_section_dimensions[pl_g.inputs.segments[1][3]][5],
                            joinpath(fig_dir, "span_configuration.png"))
    profiles["span_configuration"] = rel("span_configuration.png")
    figures = Dict{String, String}()
    for (key, title) in ((:existing_gravity, "Existing purlin line — gravity"), (:existing_uplift, "Existing purlin line — uplift"),
                         (:retrofit_gravity, "IntelliFrame retrofit — gravity"), (:retrofit_uplift, "IntelliFrame retrofit — uplift"))
        plot_case(cases[key], title, joinpath(fig_dir, "$key.png"))
        figures[String(key)] = rel("$key.png")
    end
    plot_summary(cases, joinpath(fig_dir, "summary.png"))
    figures["summary"] = rel("summary.png")

    strip(r) = Base.structdiff(r, NamedTuple{(:curves,)})   # the curves are only for the figures
    # section label per segment: the purlin name, or "A + B (lap)" for the doubled section over an interior support
    n_types = maximum(li.assignment)
    lap_types = unique(IntelliFrame.UI.define_lap_section_types(collect(li.assignment)))
    section_label(idx) = idx <= n_types ? li.types[idx] :
                         (lt = lap_types[idx - n_types]; "$(li.types[lt[1]]) + $(li.types[lt[2]]) (lap)")
    segments = [(segment = k, length_ft = s[1] / 12, section = section_label(s[3]),
                 lap = s[3] > n_types, t = pl_g.inputs.cross_section_dimensions[s[3]][2])
                for (k, s) in enumerate(pl_g.inputs.segments)]
    strengths(m, i) = (Mnx_pos = m.local_global_flexural_strength_xx[i].eMnℓ_pos, Mnx_neg = m.local_global_flexural_strength_xx[i].eMnℓ_neg)
    return (
        line = (spans_ft = collect(li.spans), laps_ft = collect(li.laps), purlin_types = collect(li.types), assignment = collect(li.assignment),
                spacing_ft = li.spacing, roof_slope = li.slope, existing_deck = li.existing_deck, new_deck = li.new_deck,
                frame_flange_width_in = li.frame_flange, purlin_frame_connection = li.connection, intelli_frame = li.intelli_frame,
                design_code = pl_g.inputs.design_code, segments = segments),
        segment_strengths = [(segment = k, existing = strengths(pl_g, k), retrofit = strengths(ifl_g, k)) for k in eachindex(segments)],
        local_buckling = lb,
        detail = design_detail(pl_g, ifl_g, li),
        existing_gravity = strip(cases.existing_gravity), existing_uplift = strip(cases.existing_uplift),
        retrofit_gravity = strip(cases.retrofit_gravity), retrofit_uplift = strip(cases.retrofit_uplift),
        profiles = profiles, figures = figures,
    )
end

end # module IntelliFrame_Capacity
