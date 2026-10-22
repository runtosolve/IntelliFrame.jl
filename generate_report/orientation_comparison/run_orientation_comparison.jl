# Orientation comparison of the IntelliFrame on the existing purlin -- data + figures for Orientation_Comparison.typ.
#   A: IntelliFrame top flange points the same way as the purlin bottom flange (current IntelliFrame.define)
#   B: IntelliFrame top flange points the same way as the purlin top flange (previous arrangement; reproduced here by
#      replacing combine_intelli_frame_purlin_geometry with its pre-c1d30f5 version in this Julia session only)
# Everything else identical: frontend_output/inputs.json, decks, governing (minimum) Mcrl rule, gravity and uplift.
# In both, the line analysis uses the connected-section warping constant and shear centre (see retrofit_connected).
# Run from the repository root:  julia --project=. generate_report/orientation_comparison/run_orientation_comparison.jl

const ROOT = dirname(dirname(@__DIR__))
const OUT  = @__DIR__
include(joinpath(ROOT, "src", "IntelliFrame_cFSM.jl"))
using JSON3, Printf, CairoMakie, CUFSM
import IntelliFrame
C = IntelliFrame_cFSM.IntelliFrame_Capacity

inputs = JSON3.read(read(joinpath(ROOT, "frontend_output", "inputs.json"), String))
cfsm   = JSON3.read(read(joinpath(ROOT, "generate_report", "cfsm_local_buckling.json"), String)).specimen
li = C.line_inputs(inputs)
db = IntelliFrame.UI.load_databases()

# combine_intelli_frame_purlin_geometry before commit c1d30f5 (no mirroring) -- arrangement B
const COMBINE_B = """
function combine_intelli_frame_purlin_geometry(purlin_cross_section_dimensions, purlin_cross_section_data, intelli_frame_cross_section_data)
    purlin_top_flange_centerline_index = sum(purlin_cross_section_data.n[1:3]) + floor(Int,purlin_cross_section_data.n[4]/2) + sum(purlin_cross_section_data.n_radius[1:3]) + 1
    purlin_top_flange_centerline_geometry = purlin_cross_section_data.node_geometry[purlin_top_flange_centerline_index, :]
    intelli_frame_node_geometry = deepcopy(intelli_frame_cross_section_data.node_geometry)
    purlin_t = purlin_cross_section_dimensions[2]
    intelli_frame_node_geometry[:, 1] = intelli_frame_node_geometry[:, 1] .+ purlin_top_flange_centerline_geometry[1]
    intelli_frame_node_geometry[:, 2] = intelli_frame_node_geometry[:, 2] .+ purlin_top_flange_centerline_geometry[2] .+ purlin_t/2
    num_purlin_nodes = size(purlin_cross_section_data.node_geometry)[1]
    intelli_frame_element_definitions = deepcopy(intelli_frame_cross_section_data.element_definitions)
    intelli_frame_element_definitions[:,1:2] = intelli_frame_element_definitions[:,1:2] .+ num_purlin_nodes
    intelli_frame_purlin_node_geometry = [purlin_cross_section_data.node_geometry; intelli_frame_node_geometry]
    intelli_frame_purlin_element_definitions = [purlin_cross_section_data.element_definitions; intelli_frame_element_definitions]
    return intelli_frame_purlin_node_geometry, intelli_frame_purlin_element_definitions
end
"""

# ── torsion: connected-section properties, capacities and demands ──────────────
"Central-difference derivative on a (possibly non-uniform) grid."
function deriv(z, f)
    d = similar(f)
    d[1] = (f[2] - f[1]) / (z[2] - z[1]); d[end] = (f[end] - f[end-1]) / (z[end] - z[end-1])
    for i in 2:length(f)-1
        d[i] = (f[i+1] - f[i-1]) / (z[i+1] - z[i-1])
    end
    return d
end

"""
Purlin + IntelliFrame as ONE connected (branched) section: the IntelliFrame bottom flange and corner are merged into
the purlin top flange (flange thickness doubled over the overlap) and the IntelliFrame web starts at a node inserted
on the purlin top flange at the web's x position. Returns nodes, elements (i, j, t), number of purlin nodes, join node.
"""
function connected_section(m; i = 1)
    pcs = m.purlin_cross_section_data[m.inputs.segments[i][3]]
    hcs = m.intelli_frame_cross_section_data[m.inputs.segments[i][4]]
    G = m.intelli_frame_purlin_cross_section_data[i].node_geometry
    np = size(pcs.node_geometry, 1)
    tp = m.inputs.purlin_cross_section_dimensions[m.inputs.segments[i][3]][2]
    ti = m.inputs.intelli_frame_cross_section_dimensions[1][1]
    P = G[1:np, :]; H = G[np+1:end, :]
    k_web = hcs.n[1] + hcs.n_radius[1] + 1
    x_web = H[k_web, 1]                               # IntelliFrame web line
    x_free = H[1, 1]                                  # free edge of the IntelliFrame bottom flange
    ytop = maximum(P[:, 2])
    nodes = [P[i, :] for i in 1:np]
    elems = [(i, i + 1, tp) for i in 1:np-1]
    # flat part of the purlin top flange (both element nodes at the top)
    is_top(e) = abs(nodes[e[1]][2] - ytop) < 1e-3 && abs(nodes[e[2]][2] - ytop) < 1e-3
    xs_top = [nodes[k][1] for k in 1:np if abs(nodes[k][2] - ytop) < 1e-3]
    flat_lo, flat_hi = extrema(xs_top)
    "Insert a node on the purlin top flange at x (clamped to the flat part); return its index."
    function insert_top_node!(x)
        x = clamp(x, flat_lo, flat_hi)
        k = findfirst(i -> abs(nodes[i][2] - ytop) < 1e-3 && abs(nodes[i][1] - x) < 1e-6, eachindex(nodes))
        k !== nothing && return k
        j = findfirst(e -> is_top(e) && (nodes[e[1]][1] - x) * (nodes[e[2]][1] - x) < 0, elems)
        j === nothing && error("no purlin top-flange element at x = $x")
        a, b, t = elems[j]
        push!(nodes, [x, ytop]); n = length(nodes)
        deleteat!(elems, j); push!(elems, (a, n, t), (n, b, t))
        return n
    end
    nj = insert_top_node!(x_web)                      # the IntelliFrame web joins the purlin top flange here
    insert_top_node!(x_free)
    # the overlap -- IntelliFrame bottom flange on the purlin top flange -- is one flange of thickness tp + ti
    lo, hi = minmax(clamp(x_web, flat_lo, flat_hi), clamp(x_free, flat_lo, flat_hi))
    elems = [(a, b, (is_top((a, b)) && min(nodes[a][1], nodes[b][1]) >= lo - 1e-6 && max(nodes[a][1], nodes[b][1]) <= hi + 1e-6) ? t + ti : t)
             for (a, b, t) in elems]
    n_if0 = length(nodes) + 1                         # first IntelliFrame node of the connected model
    prev = nj
    for k in k_web:size(H, 1)
        push!(nodes, H[k, :]); push!(elems, (prev, length(nodes), ti)); prev = length(nodes)
    end
    X = reduce(vcat, [n' for n in nodes])
    E = [Float64(e[i]) for e in elems, i in 1:3]
    return X, E, np, nj, n_if0
end

"""
IntelliFrame retrofit as in IntelliFrame_Capacity.retrofit_model, with the warping constant and shear centre that
the line analysis uses (combined section, every segment) taken from the CONNECTED section instead of the two
separate strips -- the two-strip values are not meaningful (for A, Cw comes out about 28 times too high). J stays
the sum of the two sheets. Applied identically to A and B.
"""
function retrofit_connected(pl, dir)
    pl = deepcopy(pl)
    d = db.intelli_frame_data[findfirst(==(li.intelli_frame), db.intelli_frame_data.section_name), :]
    nd = db.new_deck_data[findfirst(==(li.new_deck), db.new_deck_data.deck_name), :]
    new_deck = li.new_deck == "no deck" ? ["no deck"] :
               !ismissing(nd[3]) ? ("screw-fastened", nd[2], nd[3], nd[4], nd[5]) : ("vertical leg standing seam", nd[7])
    ed = db.existing_deck_data[findfirst(==(li.existing_deck), db.existing_deck_data.deck_name), :]
    pl.inputs.deck_details = ("screw-fastened", ed[2], 3.0, 0.212, 2.5)
    ifl = IntelliFrame.define(pl.inputs.design_code, [(s[1], s[2], s[3], 1, 1, 1, 1) for s in pl.inputs.segments], pl.inputs.spacing,
        pl.inputs.roof_slope, pl.inputs.cross_section_dimensions, [tuple([d[k] for k = 2:13]...)], [(d[:punchout_width], d[:punchout_height])],
        pl.inputs.material_properties, li.if_mat, pl.inputs.deck_details, pl.inputs.deck_material_properties, new_deck,
        (29500.0, 0.30, 55.0, 70.0), pl.inputs.frame_flange_width, pl.inputs.support_locations, pl.inputs.purlin_frame_connections,
        pl.inputs.bridging_locations)
    C.apply_governing_local_buckling!(ifl, cfsm)
    for i in eachindex(ifl.inputs.segments)
        X, E, _ = connected_section(ifl; i = i)
        sp = CUFSM.cutwp_prop2(X, E)
        spo = ifl.intelli_frame_purlin_cross_section_data[i].section_properties
        spo.Cw, spo.xs, spo.ys = sp.Cw, sp.xs, sp.ys
    end
    ifl.loading_direction = dir
    return IntelliFrame.capacity(ifl)
end

"Retrofit gravity + uplift for the orientation currently defined in IntelliFrame (line analysis with connected-section Cw, shear centre)."
function run_orientation(label)
    res = Dict{String, Any}()
    for dir in ("gravity", "uplift")
        pl = C.existing_model(li, db, dir)
        ifl = retrofit_connected(pl, dir)
        res[dir] = (r = C.case_results(ifl, dir), ifl = ifl, pl = pl)
        @printf("  %s %-7s %6.2f psf  %s
", label, dir, res[dir].r.allowable_pressure_psf, res[dir].r.limit_state)
    end
    return res
end

println("A: top flange with purlin bottom flange")
A = run_orientation("A")
Base.include_string(IntelliFrame, COMBINE_B)
println("B: top flange with purlin top flange")
B = run_orientation("B")

# ── section, strength and capacity data ────────────────────────────────────────
"Principal-axis angle (deg, counter-clockwise from x to axis 1) and principal moments."
function principal(sp)
    θ = 0.5 * atan(-2 * sp.Ixy, sp.Ixx - sp.Iyy)
    c, s = cos(θ), sin(θ)
    I1 = sp.Ixx * c^2 + sp.Iyy * s^2 - 2 * sp.Ixy * s * c
    I2 = sp.Ixx * s^2 + sp.Iyy * c^2 + 2 * sp.Ixy * s * c
    return rad2deg(θ), I1, I2
end

function section_data(m)
    cs = m.intelli_frame_purlin_cross_section_data[1]
    sp = cs.section_properties
    N = cs.node_geometry
    np = size(m.purlin_cross_section_data[m.inputs.segments[1][3]].node_geometry, 1)
    θ, I1, I2 = principal(sp)
    owner(i) = i <= np ? "purlin" : "IntelliFrame"
    return (A = sp.A, xc = sp.xc, yc = sp.yc, Ixx = sp.Ixx, Iyy = sp.Iyy, Ixy = sp.Ixy, theta_p = θ, I1 = I1, I2 = I2,
            x_min = minimum(N[:, 1]), x_max = maximum(N[:, 1]), width = maximum(N[:, 1]) - minimum(N[:, 1]),
            fibre_minus_x = owner(argmin(N[:, 1])), fibre_plus_x = owner(argmax(N[:, 1])),
            Sy_pos = m.yielding_flexural_strength_yy[1].S_pos, Sy_neg = m.yielding_flexural_strength_yy[1].S_neg,
            My_y = m.yielding_flexural_strength_yy[1].My)
end

strengths(m) = (Mcrl_pos = m.local_buckling_xx_pos[1].Mcr, Mcrl_pos_hole = m.local_buckling_xx_net_pos[1].Mcr, Mcrl_neg = m.local_buckling_xx_neg[1].Mcr,
                Mcrd_pos = m.distortional_buckling_xx_pos[1].Mcr, Mcrd_neg = m.distortional_buckling_xx_neg[1].Mcr,
                My_x = m.yielding_flexural_strength_xx[1].My,
                Mnx_pos = m.local_global_flexural_strength_xx[1].eMnℓ_pos, Mnx_neg = m.local_global_flexural_strength_xx[1].eMnℓ_neg,
                Mny_pos = m.local_global_flexural_strength_yy[1].eMnℓ_pos, Mny_neg = m.local_global_flexural_strength_yy[1].eMnℓ_neg,
                Mnd_pos = m.distortional_flexural_strength_xx[1].eMnd_pos, Mnd_neg = m.distortional_flexural_strength_xx[1].eMnd_neg,
                Vn = m.shear_strength[1].eVn, Bn = m.torsion_strength[1].eBn)

case(r) = (pressure_psf = r.allowable_pressure_psf, limit_state = r.limit_state, location = r.failure_location,
           deflection_in = r.max_deflection_in, deflection_ratio = r.max_deflection_ratio)

"Weak-axis share of the governing check at the failure location: My / Mny there, and Mx / Mnx."
function demand_split(m)
    z = m.model.inputs.z
    i = argmin(abs.(z .- m.failure_location))
    Mx, My = m.internal_forces.Mxx[i], m.internal_forces.Myy[i]
    return (z_ft = z[i] / 12, Mx = Mx, My = My, Mx_over_Mnx = abs(Mx) / m.expected_strengths.eMnℓ_xx[i],
            My_over_Mny = abs(My) / m.expected_strengths.eMnℓ_yy[i])
end

"Torsional properties, capacities (allowable, ASD) and the load point of one solved retrofit model."
function torsion_section(m)
    X, E, np, nj, n_if0 = connected_section(m)
    sp = CUFSM.cutwp_prop2(X, E)
    old = m.intelli_frame_purlin_cross_section_data[1].section_properties
    hcs = m.intelli_frame_cross_section_data[1]
    n_if_top = size(m.purlin_cross_section_data[m.inputs.segments[1][3]].node_geometry, 1) + sum(hcs.n[1:2]) + sum(hcs.n_radius[1:2]) + floor(Int, hcs.n[3] / 2) + 1
    G = m.intelli_frame_purlin_cross_section_data[1].node_geometry
    x_load = G[n_if_top, 1]
    Fy = min(m.inputs.purlin_material_properties[1][3], m.inputs.intelli_frame_material_properties[1][3])
    # St. Venant torsion: the overlapping flanges are two separate sheets, so J is the sum of the parts (old.J) and the
    # shear stress is G t phi' with the single-sheet thickness
    t_sheet = max(m.inputs.purlin_cross_section_dimensions[m.inputs.segments[1][3]][2], m.inputs.intelli_frame_cross_section_dimensions[1][1])
    Ω_b, Ω_v = 1.67, 1.60
    # shear-centre position from the edges of the section (centerline extents) and from the purlin web centerline
    pcs = m.purlin_cross_section_data[m.inputs.segments[1][3]]
    pweb = sum(pcs.n[1:2]) + sum(pcs.n_radius[1:2]) + floor(Int, pcs.n[3] / 2) + 1
    x_web = G[pweb, 1]
    x_min, x_max = extrema(G[:, 1]); y_min, y_max = extrema(G[:, 2])
    return (J_model = old.J, Cw_model = old.Cw, xs_model = old.xs, ys_model = old.ys,
            J = sp.J, Cw = sp.Cw, xs = sp.xs, ys = sp.ys, x_load = x_load, e = x_load - sp.xs,
            x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max, x_web = x_web,
            sc_from_left = sp.xs - x_min, sc_from_right = x_max - sp.xs, sc_from_bottom = sp.ys - y_min, sc_from_top = y_max - sp.ys,
            sc_from_web = sp.xs - x_web, load_from_web = x_load - x_web,
            Bn_purlin = m.torsion_strength_purlin[1].eBn, Bn_if = m.torsion_strength_intelli_frame[1].eBn, Bn = m.torsion_strength[1].eBn,
            Bn_connected = Fy * sp.Cw / maximum(abs.(sp.wn)) / Ω_b,
            T_sv_yield = 0.6 * Fy * old.J / t_sheet / Ω_v, Fy = Fy, t_sheet = t_sheet, nodes = X, elems = E, np = np, nj = nj, n_if0 = n_if0)
end

"Torsion demand along the line of one solved model at its allowable pressure."
function torsion_demand(m)
    z = m.model.inputs.z; ϕ = m.model.outputs.ϕ
    Gm, J = m.model.inputs.G, m.model.inputs.J
    dϕ = deriv(z, ϕ)
    seg_end = cumsum([s[1] for s in m.inputs.segments])
    tp = [m.inputs.purlin_cross_section_dimensions[m.inputs.segments[min(searchsortedfirst(seg_end, zi - 1e-6), length(seg_end))][3]][2] for zi in z]
    T, B = m.internal_forces.T, m.internal_forces.B
    i = argmin(abs.(z .- m.failure_location))
    iB = argmax(abs.(B))
    return (phi_max = maximum(abs.(ϕ)), T_max = maximum(abs.(T)), z_T = z[argmax(abs.(T))] / 12,
            T_sv_max = maximum(abs.(Gm .* J .* dϕ)), tau_sv_max = maximum(Gm .* tp .* abs.(dϕ)),
            B_max = abs(B[iB]), z_B = z[iB] / 12, B_over_Bn_max = abs(B[iB]) / m.expected_strengths.eBn[iB],
            B_gov = abs(B[i]), B_over_Bn_gov = abs(B[i]) / m.expected_strengths.eBn[i])
end

tA, tB = torsion_section(A["gravity"].ifl), torsion_section(B["gravity"].ifl)
strip_geom(t) = Base.structdiff(t, NamedTuple{(:nodes, :elems, :np, :nj, :n_if0)})

data = Dict(
    "torsion" => (A = (section = strip_geom(tA), gravity = torsion_demand(A["gravity"].ifl), uplift = torsion_demand(A["uplift"].ifl)),
                  B = (section = strip_geom(tB), gravity = torsion_demand(B["gravity"].ifl), uplift = torsion_demand(B["uplift"].ifl))),
    "purlin" => li.types[1], "intelli_frame" => li.intelli_frame,
    "existing" => (gravity = case(C.case_results(A["gravity"].pl, "gravity")), uplift = case(C.case_results(A["uplift"].pl, "uplift"))),
    "A" => (label = "IntelliFrame top flange points the same way as the purlin bottom flange",
            section = section_data(A["gravity"].ifl), strengths = strengths(A["gravity"].ifl),
            gravity = case(A["gravity"].r), uplift = case(A["uplift"].r),
            split_gravity = demand_split(A["gravity"].ifl), split_uplift = demand_split(A["uplift"].ifl)),
    "B" => (label = "IntelliFrame top flange points the same way as the purlin top flange",
            section = section_data(B["gravity"].ifl), strengths = strengths(B["gravity"].ifl),
            gravity = case(B["gravity"].r), uplift = case(B["uplift"].r),
            split_gravity = demand_split(B["gravity"].ifl), split_uplift = demand_split(B["uplift"].ifl)),
)
open(joinpath(OUT, "orientation_comparison.json"), "w") do f
    JSON3.write(f, data); println(f)
end

# ── figure: both arrangements with centroidal (x, y) and principal (1, 2) axes ───
models = (("A", A["gravity"].ifl), ("B", B["gravity"].ifl))
allN = vcat([m.intelli_frame_purlin_cross_section_data[1].node_geometry for (_, m) in models]...)
pad = 1.0
xl = (minimum(allN[:, 1]) - pad, maximum(allN[:, 1]) + pad)
yl = (minimum(allN[:, 2]) - 0.6, maximum(allN[:, 2]) + 0.8)
ink = RGBf(0.12, 0.16, 0.23)

fig = Figure(size = (1250, 820), backgroundcolor = :white, fontsize = 14)
for (j, (key, m)) in enumerate(models)
    cs = m.intelli_frame_purlin_cross_section_data[1]
    sp = cs.section_properties
    np = size(m.purlin_cross_section_data[m.inputs.segments[1][3]].node_geometry, 1)
    N, E = cs.node_geometry, cs.element_definitions
    θ, _, _ = principal(sp)
    ax = Axis(fig[1, j]; aspect = DataAspect(), limits = (xl, yl), xlabel = "x (in.)", ylabel = "y (in.)",
              title = key == "A" ? "A — IntelliFrame top flange with purlin bottom flange" : "B — IntelliFrame top flange with purlin top flange",
              subtitle = @sprintf("Iyy = %.2f in.⁴   Ixy = %.2f in.⁴   principal axis 1 at %.1f°", sp.Iyy, sp.Ixy, θ), titlesize = 15)
    # strips
    for k in 1:size(E, 1)
        a, b = Int(E[k, 1]), Int(E[k, 2])
        lines!(ax, [N[a, 1], N[b, 1]], [N[a, 2], N[b, 2]]; color = a <= np ? C.STEEL_GRAY : C.IMETCO_RED, linewidth = 3.5)
    end
    # centroidal x and y axes
    L = 2.2
    arrows2d!(ax, [sp.xc, sp.xc], [sp.yc, sp.yc], [L, 0.0], [0.0, L]; color = ink, shaftwidth = 1.6, tiplength = 12, tipwidth = 10)
    lines!(ax, [sp.xc - L, sp.xc], [sp.yc, sp.yc]; color = ink, linewidth = 1, linestyle = :dot)
    lines!(ax, [sp.xc, sp.xc], [sp.yc - L, sp.yc]; color = ink, linewidth = 1, linestyle = :dot)
    text!(ax, sp.xc + L, sp.yc; text = "x", align = (:left, :center), offset = (6, 0), fontsize = 16, font = :bold, color = ink)
    text!(ax, sp.xc, sp.yc + L; text = "y", align = (:center, :bottom), offset = (0, 4), fontsize = 16, font = :bold, color = ink)
    # principal axes
    c, s = cosd(θ), sind(θ); P = 3.2
    lines!(ax, [sp.xc - P * c, sp.xc + P * c], [sp.yc - P * s, sp.yc + P * s]; color = :darkorange, linewidth = 1.6, linestyle = :dash)
    lines!(ax, [sp.xc + P * s, sp.xc - P * s], [sp.yc - P * c, sp.yc + P * c]; color = :darkorange, linewidth = 1.6, linestyle = :dash)
    text!(ax, sp.xc + P * c, sp.yc + P * s; text = "1", align = (:left, :center), offset = (4, 0), fontsize = 14, color = :darkorange)
    text!(ax, sp.xc - P * s, sp.yc + P * c; text = "2", align = (:center, :bottom), offset = (0, 3), fontsize = 14, color = :darkorange)
    scatter!(ax, [sp.xc], [sp.yc]; marker = :circle, color = :white, strokecolor = ink, strokewidth = 2, markersize = 12)
    # shear centre of the connected section
    t = key == "A" ? tA : tB
    scatter!(ax, [t.xs], [t.ys]; marker = :diamond, color = :steelblue, strokecolor = ink, strokewidth = 1, markersize = 14)
    text!(ax, t.xs, t.ys; text = "SC", align = (:left, :top), offset = (6, -4), fontsize = 12, color = :steelblue)
    # overall width of the section
    yd = yl[1] + 0.25
    xmin, xmax = minimum(N[:, 1]), maximum(N[:, 1])
    lines!(ax, [xmin, xmax], [yd, yd]; color = ink, linewidth = 1)
    lines!(ax, [xmin, xmin], [yd - 0.12, yd + 0.12]; color = ink, linewidth = 1)
    lines!(ax, [xmax, xmax], [yd - 0.12, yd + 0.12]; color = ink, linewidth = 1)
    text!(ax, (xmin + xmax) / 2, yd; text = @sprintf("overall width %.2f in.", xmax - xmin), align = (:center, :bottom), offset = (0, 3), fontsize = 12, color = ink)
end
Legend(fig[2, 1:2], [LineElement(color = C.STEEL_GRAY, linewidth = 3.5), LineElement(color = C.IMETCO_RED, linewidth = 3.5),
                     MarkerElement(marker = :circle, color = :white, strokecolor = ink, strokewidth = 2, markersize = 12),
                     MarkerElement(marker = :diamond, color = :steelblue, strokecolor = ink, strokewidth = 1, markersize = 14),
                     LineElement(color = ink, linewidth = 1.6), LineElement(color = :darkorange, linewidth = 1.6, linestyle = :dash)],
       ["Existing purlin ($(li.types[1]))", "IntelliFrame ($(li.intelli_frame))", "Centroid of the combined section",
        "Shear centre SC (connected section)",
        "Centroidal axes: x horizontal (strong-axis bending, Mx), y vertical (weak-axis bending, My)", "Principal axes 1, 2"];
       orientation = :horizontal, nbanks = 2, framevisible = false, labelsize = 12)
save(joinpath(OUT, "orientation_sections.png"), fig; px_per_unit = 2)

# ── figure: strengths and capacities, A vs B ─────────────────────────────────────
sA, sB = data["A"].strengths, data["B"].strengths
groups = [("Mnℓx⁺", sA.Mnx_pos, sB.Mnx_pos), ("Mnℓx⁻", sA.Mnx_neg, sB.Mnx_neg), ("Mnd⁺", sA.Mnd_pos, sB.Mnd_pos), ("Mnd⁻", sA.Mnd_neg, sB.Mnd_neg),
          ("Mnℓy⁺", sA.Mny_pos, sB.Mny_pos), ("Mnℓy⁻", sA.Mny_neg, sB.Mny_neg)]
fig = Figure(size = (1250, 430), backgroundcolor = :white, fontsize = 14)
ax1 = Axis(fig[1, 1]; ylabel = "Allowable strength (kip-in.)", xticks = (1:length(groups), first.(groups)),
           title = "Section strengths, span segment", xgridvisible = false)
xs = repeat(1:length(groups), inner = 2); g = repeat([1, 2], length(groups))
vals = vcat([[a, b] for (_, a, b) in groups]...)
barplot!(ax1, xs, vals; dodge = g, width = 0.6, dodge_gap = 0.06, color = repeat([C.IMETCO_RED, RGBf(0.85, 0.6, 0.6)], length(groups)),
         bar_labels = [@sprintf("%.1f", v) for v in vals], label_size = 11)
ylims!(ax1, 0, 1.18 * maximum(vals))
vlines!(ax1, [4.5]; color = :gray60, linestyle = :dot)
text!(ax1, 2.5, 1.12 * maximum(vals); text = "strong axis (x)", align = (:center, :center), fontsize = 12, color = :gray35)
text!(ax1, 5.5, 1.12 * maximum(vals); text = "weak axis (y)", align = (:center, :center), fontsize = 12, color = :gray35)
pv = [data["A"].gravity.pressure_psf, data["B"].gravity.pressure_psf, data["A"].uplift.pressure_psf, data["B"].uplift.pressure_psf]
ax2 = Axis(fig[1, 2]; ylabel = "Allowable roof pressure (psf)", xticks = (1:2, ["Gravity", "Uplift"]), title = "Retrofitted purlin line", xgridvisible = false)
barplot!(ax2, [1, 1, 2, 2], pv; dodge = [1, 2, 1, 2], width = 0.5, dodge_gap = 0.06, color = [C.IMETCO_RED, RGBf(0.85, 0.6, 0.6), C.IMETCO_RED, RGBf(0.85, 0.6, 0.6)],
         bar_labels = [@sprintf("%.2f", v) for v in pv], label_size = 11)
ylims!(ax2, 0, 1.2 * maximum(pv))
colsize!(fig.layout, 2, Relative(0.32))
Legend(fig[2, 1:2], [PolyElement(color = C.IMETCO_RED), PolyElement(color = RGBf(0.85, 0.6, 0.6))],
       ["A — top flange with purlin bottom flange", "B — top flange with purlin top flange"]; orientation = :horizontal, framevisible = false)
save(joinpath(OUT, "orientation_strengths.png"), fig; px_per_unit = 2)

# ── figure: connected sections, shear centre and load eccentricity ──────────────
fig = Figure(size = (1200, 700), backgroundcolor = :white, fontsize = 13)
for (j, (key, t, m)) in enumerate((("A", tA, A["gravity"].ifl), ("B", tB, B["gravity"].ifl)))
    X, E = t.nodes, t.elems
    G = m.intelli_frame_purlin_cross_section_data[1].node_geometry
    y_load = maximum(G[:, 2])
    ax = Axis(fig[1, j]; aspect = DataAspect(), xlabel = "x (in.)", ylabel = "y (in.)", limits = (-6, 6.5, -0.8, 14.8),
              title = key == "A" ? "A — top flange with purlin bottom flange" : "B — top flange with purlin top flange",
              subtitle = @sprintf("J = %.5f in.⁴ (sum of sheets), Cw = %.1f in.⁶ (connected), load eccentricity e = %.2f in.", t.J_model, t.Cw, abs(t.e)))
    # connected model: purlin (incl. the overlap, drawn thicker) and the IntelliFrame web / top flange / lip
    n_if_start = t.n_if0
    for r in eachrow(E)
        a, b = Int(r[1]), Int(r[2])
        is_if = max(a, b) >= n_if_start
        lines!(ax, [X[a, 1], X[b, 1]], [X[a, 2], X[b, 2]]; color = is_if ? C.IMETCO_RED : C.STEEL_GRAY, linewidth = r[3] > 0.07 ? 6 : 3)
    end
    # IntelliFrame bottom flange and corner as built, sitting on the purlin top flange (merged into the overlap in the model)
    np_m = size(m.purlin_cross_section_data[m.inputs.segments[1][3]].node_geometry, 1)
    hcs = m.intelli_frame_cross_section_data[1]
    k_web = hcs.n[1] + hcs.n_radius[1] + 1
    Hb = G[np_m+1:np_m+k_web, :]
    lines!(ax, Hb[:, 1], Hb[:, 2]; color = C.IMETCO_RED, linewidth = 3)
    scatter!(ax, [t.xs], [t.ys]; marker = :diamond, color = :steelblue, strokecolor = ink, strokewidth = 1, markersize = 15)
    text!(ax, t.xs, t.ys; text = "SC", align = (:center, :bottom), offset = (0, 8), fontsize = 12, font = :bold, color = :steelblue)
    # line of action of the load and its eccentricity e from the shear centre
    arrows2d!(ax, [t.x_load], [y_load + 1.8], [0.0], [-1.6]; color = :steelblue, shaftwidth = 2, tiplength = 12, tipwidth = 10)
    lines!(ax, [t.x_load, t.x_load], [t.ys, y_load]; color = (:steelblue, 0.5), linestyle = :dot, linewidth = 1.5)
    lines!(ax, [t.xs, t.x_load], [t.ys, t.ys]; color = :steelblue, linestyle = :dash, linewidth = 1.5)
    text!(ax, (t.xs + t.x_load) / 2, t.ys; text = @sprintf("e = %.2f in.", abs(t.e)), align = (:center, :top), offset = (0, -4), color = :steelblue, font = :bold)
    # dimensions of the shear centre from the section edges (centerline extents)
    dim(x1, x2, y; lab, pos = :bottom) = begin
        lines!(ax, [x1, x2], [y, y]; color = ink, linewidth = 1)
        lines!(ax, [x1, x1], [y - 0.15, y + 0.15]; color = ink, linewidth = 1)
        lines!(ax, [x2, x2], [y - 0.15, y + 0.15]; color = ink, linewidth = 1)
        text!(ax, (x1 + x2) / 2, y; text = lab, align = (:center, pos == :bottom ? :top : :bottom), offset = (0, pos == :bottom ? -3 : 3), fontsize = 11, color = ink)
    end
    yd = t.ys - 1.3
    lines!(ax, [t.xs, t.xs], [yd - 0.15, t.ys]; color = (ink, 0.35), linestyle = :dot)
    lines!(ax, [t.x_min, t.x_min], [yd - 0.15, t.y_min + 0.9]; color = (ink, 0.35), linestyle = :dot)
    lines!(ax, [t.x_max, t.x_max], [yd - 0.15, t.y_max - 0.2]; color = (ink, 0.35), linestyle = :dot)
    dim(t.x_min, t.xs, yd; lab = @sprintf("%.2f", t.sc_from_left))
    dim(t.xs, t.x_max, yd; lab = @sprintf("%.2f", t.sc_from_right))
    xv = t.x_min - 0.6
    lines!(ax, [xv, xv], [t.y_min, t.ys]; color = ink, linewidth = 1)
    lines!(ax, [xv - 0.15, xv + 0.15], [t.y_min, t.y_min]; color = ink, linewidth = 1)
    lines!(ax, [xv - 0.15, xv + 0.15], [t.ys, t.ys]; color = ink, linewidth = 1)
    lines!(ax, [xv, t.xs], [t.ys, t.ys]; color = (ink, 0.35), linestyle = :dot)
    text!(ax, xv, (t.y_min + t.ys) / 2; text = @sprintf("%.2f", t.sc_from_bottom), rotation = π / 2, align = (:center, :bottom), offset = (0, 3), fontsize = 11, color = ink)
end
Legend(fig[2, 1:2], [LineElement(color = C.STEEL_GRAY, linewidth = 3), LineElement(color = C.IMETCO_RED, linewidth = 3),
                     MarkerElement(marker = :diamond, color = :steelblue, strokecolor = ink, strokewidth = 1, markersize = 15),
                     LineElement(color = :steelblue, linewidth = 2), LineElement(color = ink, linewidth = 1)],
       ["Purlin (thick: overlap, one flange tp + ti)", "IntelliFrame", "Shear centre SC (connected section)",
        "Roof load: line of action, eccentricity e from SC", "SC from left / right edge, bottom (in.)"];
       orientation = :horizontal, nbanks = 3, framevisible = false, labelsize = 12)
save(joinpath(OUT, "orientation_torsion.png"), fig; px_per_unit = 2)

println("written: ", joinpath(OUT, "orientation_comparison.json"), ", orientation_sections.png, orientation_strengths.png, orientation_torsion.png")
