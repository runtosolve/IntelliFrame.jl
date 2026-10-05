# IntelliFrame_cFSM.jl — elastic local buckling of the IntelliFrame RF sections with and without
# the punch-out, using the conventional finite strip signature curve (CUFSM) together with the
# constrained pure-local curve and G/D/L/O mode identification of BucklingModeIdentification.jl
# (cFSM on the actual rounded-corner geometry, elastic corners).
#
# Adapted from ESR_1538_Canada_2026/calculations/r3_only_service_hole/run_local_buckling_r3_only_service_hole.jl:
#
#   Gross model (Mcrl_no_hole):
#     the FIRST true local minimum (R[i-1] > R[i] < R[i+1]) of the signature curve inside [0.5W, 2W]
#     gives (Lcrl, Mcrl), W = widest flat element of the section; if there is none, Lcrl is the
#     minimum of the cFSM pure-local curve of the same geometry and Mcrl is the signature curve at it.
#   Net-section model (Mcrl_hole):
#     the same rule gives the "true" Lcrl of the net-section curve; then
#         Lcrl = min(true Lcrl, L_hole),     L_hole = punch-out length along the member,
#     and Mcrl is the net-section signature curve at that Lcrl (the buckle cannot be longer than
#     the punch-out it forms in -- the same assumption as calculate_net_section_local_buckling_properties).
#
# The IntelliFrame punch-out is an EDGE cut-out: it removes the bottom flange, the bottom corner and
# the web below the punch-out height (see IntelliFrame.generate_intelli_frame_net_section_purlin_geometry).
# The net section is therefore the remaining web / top flange / lip chain. The r3 zero-thickness strip
# is not used: at a free end a zero-thickness strip leaves the cut-off nodes without any stiffness.
#
# Every model is the bare IntelliFrame member (no purlin, no deck springs): cFSM's base vectors need a
# single-branched open section, and local buckling is a plate-level mode of the IntelliFrame itself.
#
# Driver entry points follow SteelDeckAPI.jl:
#     run_all_calculations(inputs_path, output_dir)   -> JSON + PNG figures in output_dir
#     export_pdf(inputs_path, output_dir)             -> compiles output_dir/Report.typ with Typst

module IntelliFrame_cFSM

using CSV, DataFrames, JSON3, Printf, LinearAlgebra
using CUFSM
using CairoMakie
import BucklingModeIdentification as BMI
import cFSM
import IntelliFrame

export run_all_calculations, export_pdf, analyze_specimen, local_buckling

include("IntelliFrame_Capacity.jl")   # submodule: allowable pressure, existing vs. retrofit, gravity and uplift


const PACKAGE_ROOT  = dirname(@__DIR__)
const DATABASE_PATH = joinpath(PACKAGE_ROOT, "database", "IntelliFrameRF.csv")
const RESULTS_FILE  = "cfsm_local_buckling.json"
const CAPACITY_FILE = "capacity_results.json"
const FIGURES_DIR   = joinpath("figures", "cfsm")   # relative to output_dir, which is where Report.typ lives


# ── Discretization, search range and sweep ─────────────────────────────────────

"FSM discretization of the IntelliFrame [bottom flange, web, top flange, lip] flats and [r1, r2, r3] corners -- finer than IntelliFrame.define's [2, 6, 2, 2] / [3, 3, 3] so the local plate modes and the punch-out cut are resolved."
const FSM_N        = [4, 12, 6, 3]
const FSM_N_RADIUS = [4, 4, 4]

const RANGE_LO = 0.5      # × W
const RANGE_HI = 2.0      # × W
const PLOT_LO  = 0.1      # × W, sweep shown in the figure
const PLOT_HI  = 8.0      # × W
const N_RANGE  = 31       # samples inside [0.5W, 2W], endpoints included
const N_DISC   = 5        # points per element for the mode-shape insets
const MIN_SEGMENT = 0.05  # × t, shortest strip kept (BucklingModeIdentification.drop_short_segments)

const L_DOMINANT = "L"   # a signature-curve trough is local only if L is its largest G/D/L/O participation


# ── cFSM base-vector fix for inclined elements ─────────────────────────────────

"""
cFSM.jl's `_base_vectors_full` builds each element's "other" (O) transverse-
extension vector with node displacements ∓½(cos α, −sin α). An extension along
an element at α = atan(dz, dx) is along (cos α, +sin α), so for every INCLINED
element (the IntelliFrame's 45° lip) that vector is perpendicular to the strip:
it duplicates a local bending direction and the true extension direction is
missing. The base is then rank-deficient and every G/D/L/O participation reads
0 / 0 / 50 / 50. Horizontal and vertical strips are unaffected, and so is
`pure_mode_curve([:L])`, which uses the L columns only.

`_cfsm_has_o_sign_bug()` probes a lipped Cee with 45° lips; when the installed
cFSM still has the bug, `_patch_cfsm!()` re-evaluates that function in cFSM with
the two z-entries' signs corrected. Once cFSM is fixed upstream the probe
passes and nothing is overridden.
"""
function _cfsm_has_o_sign_bug()
    X, Y = BMI.polyline_with_fillets([(2.18, 0.18), (2.0, 0.0), (0.0, 0.0), (0.0, 4.5), (2.0, 4.5), (2.18, 4.32)], 0.15; n_arc = 4, n_flat = 4)
    prop, node, elem = assemble_cufsm_inputs(X, Y, 0.06, 29500.0, 0.3)
    B, _ = BMI.base_vectors(BMI.base_cache(node, elem), node, elem, prop, 2.0)
    return rank(B) < size(B, 1)
end

function _patch_cfsm!()
    _cfsm_has_o_sign_bug() || return false
    @eval cFSM function _base_vectors_full(dy, a, m, elem, elprop, node_prop,
                                           nmno, ncno, nsno, ngm, ndm, nlm,
                                           Rx, Rz, Rp, Rys, DOFperm)
        nno    = size(node_prop, 1)
        nelems = size(elem, 1)
        ndof   = 4 * nno
        km     = m * π / a
        ngdm   = ngm + ndm
        neno   = nmno - ncno
        nom    = 2 * nelems
        ntotal = ngdm + nlm + nom
        b_v = zeros(ndof, ntotal)

        b_v_gd = zeros(ndof, ngdm)
        b_v_gd[1:nmno, :]                           = dy[:, 1:ngdm]
        b_v_gd[(nmno+1):(nmno+ncno), :]             = Rx * b_v_gd[1:nmno, :]
        b_v_gd[(nmno+ncno+1):(nmno+2ncno), :]       = Rz * b_v_gd[1:nmno, :]
        b_v_gd[(nmno+2ncno+1):(ndof-nsno), :]       = Rp * b_v_gd[(nmno+1):(nmno+2ncno), :]
        nsno > 0 && (b_v_gd[(ndof-nsno+1):ndof, :] = Rys * b_v_gd[1:nmno, :])
        b_v_gd[(nmno+1):(ndof-nsno), :] ./= km
        for i in 1:ngdm
            n = norm(b_v_gd[:, i]); n > 0 && (b_v_gd[:, i] ./= n)
        end
        b_v[:, 1:ngdm] = DOFperm * b_v_gd

        b_v_l = zeros(ndof, nlm)
        b_v_l[3nmno+1:4nmno, 1:nmno] = I(nmno)
        nsno > 0 && (b_v_l[4nmno+2nsno+1:4nmno+3nsno, nmno+1:nmno+nsno] = I(nsno))
        ke = 0
        for i in 1:nno
            if node_prop[i, 4] == 2
                ke += 1
                for j in 1:nelems
                    if Int(elem[j,2]) == i || Int(elem[j,3]) == i
                        alfa = elprop[j, 3]
                        b_v_l[nmno+2ncno+ke,      nmno+nsno+ke] = -sin(alfa)
                        b_v_l[nmno+2ncno+neno+ke, nmno+nsno+ke] =  cos(alfa)
                        break
                    end
                end
            end
        end
        if nsno > 0
            ks = 0
            for i in 1:nno
                if node_prop[i, 4] == 3
                    ks += 1
                    for j in 1:nelems
                        if Int(elem[j,2]) == i || Int(elem[j,3]) == i
                            alfa = elprop[j, 3]
                            b_v_l[4nmno+ks,      nmno+nsno+neno+ks] = -sin(alfa)
                            b_v_l[4nmno+nsno+ks, nmno+nsno+neno+ks] =  cos(alfa)
                            break
                        end
                    end
                end
            end
        end
        b_v[:, ngdm+1:ngdm+nlm] = DOFperm * b_v_l

        for i in 1:nelems
            alfa  = elprop[i, 3]
            nnod1 = Int(elem[i, 2])
            nnod2 = Int(elem[i, 3])
            b_v[2nnod1,   ngdm+nlm+i] =  0.5
            b_v[2nnod2,   ngdm+nlm+i] = -0.5
            # extension along the element direction (cos α, sin α) -- corrected z sign
            b_v[2nnod1-1,       ngdm+nlm+nelems+i] = -0.5*cos(alfa)
            b_v[2nnod2-1,       ngdm+nlm+nelems+i] =  0.5*cos(alfa)
            b_v[2nno+2nnod1-1,  ngdm+nlm+nelems+i] = -0.5*sin(alfa)
            b_v[2nno+2nnod2-1,  ngdm+nlm+nelems+i] =  0.5*sin(alfa)
        end
        return b_v, ngdm, nlm, nom
    end
    Base.invokelatest(_cfsm_has_o_sign_bug) && error("cFSM base is still rank-deficient after the O-vector sign fix")
    @info "IntelliFrame_cFSM: applied the cFSM O-vector sign fix for inclined elements (cFSM._base_vectors_full)"
    return true
end

function __init__()
    _patch_cfsm!()
end

const MODELS = (
    Mcrl_no_hole = (key = "Mcrl_no_hole", label = "strong-axis bending, gross section",
                    sym = "Mcrl", unit = "kip-in."),
    Mcrl_hole    = (key = "Mcrl_hole",    label = "strong-axis bending, net section at the punch-out",
                    sym = "Mcrl", unit = "kip-in."),
)


# ── Cross-section geometry ─────────────────────────────────────────────────────

"IntelliFrame dimension tuple (t, B_bottom, H, B_top, D, α1..α4, r1, r2, r3) from a database/IntelliFrameRF.csv row, the same 12 columns UI.retrofit_UI_mapper passes to IntelliFrame.define."
specimen_dimensions(row) = Tuple(Float64(row[c]) for c in (:thickness, :B_bottom, :H, :B_top, :D,
    :bottom_flange_angle, :web_angle, :top_flange_angle, :lip_angle, :r1, :r2, :r3))

"Filesystem-safe key for a section name, e.g. `2x4.5x2.5 16g` -> `2x4.5x2.5_16g`."
specimen_key(name) = replace(replace(name, "\"" => ""), r"[^A-Za-z0-9.\-]+" => "_")

"""
Centerline of the full IntelliFrame section, built with IntelliFrame's own
`define_intelli_frame_cross_sections` (bottom face at y = 0, bottom flange
centerline at x = 0) on the finer FSM discretization. Strips shorter than
`MIN_SEGMENT * t` are dropped (mesh hygiene for cFSM, see
`BucklingModeIdentification.drop_short_segments`).
"""
function gross_centerline(dims; n = FSM_N, n_radius = FSM_N_RADIUS)
    data = IntelliFrame.define_intelli_frame_cross_sections([dims], n, n_radius)[1]
    t = dims[1]
    # mirrored about x = 0 (x -> -x) so the top flange and lip point left, as the profile is drawn;
    # a mirror image has the same buckling behaviour, so Mcrℓ is unaffected
    return BMI.drop_short_segments(-data.node_geometry[:, 1], data.node_geometry[:, 2]; min_length = MIN_SEGMENT * t)
end

"""
Net section at the punch-out: the chain is cut on the web at
y = `punchout_height` (measured from the IntelliFrame bottom face, the datum
`generate_intelli_frame_net_section_purlin_geometry` uses) and everything
below the cut -- bottom flange, bottom corner and lower web -- is removed.
Returns `(Xnet, Ynet, Xremoved, Yremoved)`; the removed polyline ends at the
cut node so it joins the net section in the figures.
"""
function punchout_net_centerline(X, Y, punchout_height; t, web_angle)
    k = findfirst(i -> Y[i] < punchout_height <= Y[i+1], 1:(length(Y) - 1))
    k === nothing && error("punch-out height $punchout_height in. does not cut the IntelliFrame centerline")
    seg_angle = rad2deg(atan(Y[k+1] - Y[k], X[k+1] - X[k]))
    abs(seg_angle - web_angle) < 1.0 || error(
        "punch-out height $punchout_height in. cuts the section at a $(round(seg_angle, digits = 1))° strip, not the $(web_angle)° web -- the punch-out must end on the flat web")
    f  = (punchout_height - Y[k]) / (Y[k+1] - Y[k])
    xc = X[k] + f * (X[k+1] - X[k])
    Xnet, Ynet = BMI.drop_short_segments(vcat(xc, X[k+1:end]), vcat(punchout_height, Y[k+1:end]); min_length = MIN_SEGMENT * t)
    return Xnet, Ynet, vcat(X[1:k], xc), vcat(Y[1:k], punchout_height)
end

"""
Maximum flat (straight, unbroken) element width of the section: consecutive
collinear segments are merged into one flat run, a corner arc's changing
direction ends the run. Seeds the local buckling search range [0.5W, 2W].
"""
function max_flat_width(X, Y; tol = 1e-6)
    dx, dy = diff(X), diff(Y)
    len = hypot.(dx, dy)
    max_width = run = len[1]
    for k in 2:length(len)
        collinear = abs(dx[k-1] * dy[k] - dy[k-1] * dx[k]) < tol * len[k-1] * len[k]
        run = collinear ? run + len[k] : len[k]
        max_width = max(max_width, run)
    end
    return max_width
end

"""
Centerline section properties plus the extreme-fiber section moduli and the
first-yield moment `My = Fy * min(Sc, St)` for +Mxx (top in compression).
Extreme fibers are the centerline extremes ± t/2.
"""
function section_properties(X, Y, t, Fy)
    n  = length(X)
    sp = CUFSM.cutwp_prop2([X Y], [1:(n - 1) 2:n fill(t, n - 1)])
    Sc = sp.Ixx / (maximum(Y) + t / 2 - sp.yc)
    St = sp.Ixx / (sp.yc - (minimum(Y) - t / 2))
    return (A = sp.A, xc = sp.xc, yc = sp.yc, Ixx = sp.Ixx, Iyy = sp.Iyy, Ixy = sp.Ixy,
            Sc = Sc, St = St, My = Fy * min(Sc, St), c_top = maximum(Y) - sp.yc)
end


# ── CUFSM assembly ─────────────────────────────────────────────────────────────

"CUFSM prop/node/elem for a uniform-thickness open chain with the reference stress of unit strong-axis moment `Mxx` (restrained bending, the IntelliFrame convention `unsymm = 0`)."
function assemble_cufsm_inputs(X, Y, t, E, ν; P = 0.0, Mxx = 1.0)
    n  = length(X)
    ne = n - 1
    ends = [1:ne 2:n fill(t, ne)]
    sp = CUFSM.cutwp_prop2([X Y], ends)

    node = zeros(Float64, n, 8)
    node[:, 1]   .= 1:n
    node[:, 2]   .= X
    node[:, 3]   .= Y
    node[:, 4:7] .= 1.0

    elem = zeros(Float64, ne, 5)
    elem[:, 1]   .= 1:ne
    elem[:, 2:4] .= ends
    elem[:, 5]   .= 100.0

    prop = [100 E E ν ν E / (2 * (1 + ν))]
    node = CUFSM.stresgen(node, P, Mxx, 0.0, 0.0, 0.0, sp.A, sp.xc, sp.yc, sp.Ixx, sp.Iyy, sp.Ixy, sp.θ, sp.I1, sp.I2, 0)
    return prop, node, elem
end

"Conventional (unconstrained) finite strip run, first mode only. CUFSM.strip rounds node coordinates in place -- pass copies."
function run_cufsm_strip(prop, node, elem, lengths)
    curve, shapes = CUFSM.strip(prop, node, elem, lengths, [], [], 1)
    return CUFSM.Model(prop, node, elem, lengths, [], [], 1, curve, shapes)
end


# ── Local buckling rule ────────────────────────────────────────────────────────

"Half-wavelengths for the conventional sweep: 0.5W and 2W exactly, dense inside the range, coarser outside for the picture."
function sweep_lengths(W)
    inr = exp.(range(log(RANGE_LO * W), log(RANGE_HI * W), length = N_RANGE))
    lo  = exp.(range(log(PLOT_LO * W),  log(RANGE_LO * W), length = 12))[1:end-1]
    hi  = exp.(range(log(RANGE_HI * W), log(PLOT_HI * W),  length = 20))[2:end]
    return vcat(lo, inr, hi)
end

in_range(L, W) = RANGE_LO * W * (1 - 1e-9) <= L <= RANGE_HI * W * (1 + 1e-9)

"""
Sampled points inside [0.5W, 2W], shortest half-wavelength first, at which
the signature curve stops falling and starts rising, R[i-1] > R[i] < R[i+1]
(the neighbours may lie just outside the range). Empty when the curve only
falls (or only rises) through the whole range.
"""
troughs_in_range(L, R, W) = [i for i in 2:(length(R) - 1) if in_range(L[i], W) && R[i-1] > R[i] < R[i+1]]

dominant_class(p) = String(argmax(k -> p[k], (:G, :D, :L, :O)))

"""
First trough inside [0.5W, 2W] whose conventional mode is L-dominated (L is
the largest G/D/L/O participation -- BucklingModeIdentification's own
definition of the local minimum in `characteristic_minima`). A D-dominated
trough is the distortional mode reaching into the range (the bare IntelliFrame's
lip is short and unrestrained) and is not accepted as the local minimum.
Returns `(index, participation)`, or `(nothing, nothing)`, plus every
trough tried as `(index, participation)` for the record.
"""
function local_minimum_in_range(prop, node, elem, L, R, W)
    tried = []
    for i in troughs_in_range(L, R, W)
        p = mode_participation(prop, node, elem, L[i])
        push!(tried, (i, p))
        dominant_class(p) == L_DOMINANT && return i, p, tried
    end
    return nothing, nothing, tried
end

"Buckled shape (X, Y, ΔX, ΔY) of a CUFSM DOF vector `d`, `N_DISC` points per element."
function mode_shape(node, elem, d)
    X, Y, ΔX, ΔY = BMI.discretized_shape(node, elem, d; n_per_elem = N_DISC)
    return (; X, Y, ΔX, ΔY)
end

"G/D/L/O participation (percent) of the conventional first mode at half-wavelength `L`."
function mode_participation(prop, node, elem, L)
    r = BMI.decompose_modes(node, elem, prop, [L])
    p = r.participation[1, :]
    return (G = p[1], D = p[2], L = p[3], O = p[4])
end

"""
    local_buckling(X, Y, t, E, ν; Mxx = 1.0, hole_length = nothing)

Elastic local buckling moment of the open chain (X, Y) under unit `Mxx` by
the rule in the file header. With `hole_length` (the punch-out length along
the member) the net-section rule `Lcrl = min(true Lcrl, hole_length)` is
applied and the signature and cFSM pure-local curves are also evaluated at
L = hole_length. Returns a NamedTuple with the reported point `rep`, the
curves, the cFSM minimum, the buckled shapes for the figure and the G/D/L/O
participation at the reported half-wavelength.
"""
function local_buckling(X, Y, t, E, ν; Mxx = 1.0, hole_length = nothing)
    W  = max_flat_width(X, Y)
    Ls = sweep_lengths(W)
    prop, node, elem = assemble_cufsm_inputs(X, Y, t, E, ν; Mxx)

    # 1. conventional signature curve
    conv  = run_cufsm_strip(prop, copy(node), copy(elem), Ls)
    Rconv = CUFSM.Tools.get_load_factor(conv, 1)

    # 2. cFSM pure-local curve on the same rounded geometry, then refine its minimum
    lfL, _ = BMI.pure_mode_curve(node, elem, prop, Ls, [:L]; return_shapes = true)
    all(isnan, lfL) && error("cFSM pure-local curve has no positive load factor in the sweep")
    iL   = argmin(replace(lfL, NaN => Inf))
    Lref = exp.(range(log(Ls[max(iL - 1, 1)]), log(Ls[min(iL + 1, end)]), length = 15))
    lfLr, shLr = BMI.pure_mode_curve(node, elem, prop, Lref, [:L]; return_shapes = true)
    j = argmin(replace(lfLr, NaN => Inf))
    cfsm = (L = Lref[j], R = lfLr[j])
    cfsm_shape = mode_shape(node, elem, shLr[j])

    # signature curve exactly at the cFSM Lcrl (reported when the curve has no trough in range)
    at   = run_cufsm_strip(prop, copy(node), copy(elem), [cfsm.L])
    R_at = CUFSM.Tools.get_load_factor(at, 1)[1]

    # 3. the rule: first L-dominated trough in [0.5W, 2W], else the cFSM pure-local Lcrl
    i_abs, _, tried = local_minimum_in_range(prop, node, elem, Ls, Rconv, W)
    rejected_troughs = [(L = Ls[i], R = Rconv[i], dominant = dominant_class(p), participation = p) for (i, p) in tried if i != i_abs]
    if i_abs !== nothing
        rep = (L = Ls[i_abs], R = Rconv[i_abs])
        conv_shape = mode_shape(conv.node, conv.elem, conv.shapes[i_abs][:, 1])
        method_key = "signature"
    else
        rep = (L = cfsm.L, R = R_at)
        conv_shape = mode_shape(at.node, at.elem, at.shapes[1][:, 1])
        method_key = "cFSM-Lcrl"
    end
    true_pt, true_key = rep, method_key

    # 4. net section only: Lcrl = min(true Lcrl, L_hole); both curves at L = L_hole
    R_D, cfsm_D = NaN, NaN
    if hole_length !== nothing
        atD = run_cufsm_strip(prop, copy(node), copy(elem), [hole_length])
        R_D = CUFSM.Tools.get_load_factor(atD, 1)[1]
        cfsm_D = BMI.pure_mode_curve(node, elem, prop, [hole_length], [:L])[1]
        if hole_length < true_pt.L
            rep = (L = hole_length, R = R_D)
            conv_shape = mode_shape(atD.node, atD.elem, atD.shapes[1][:, 1])
            method_key = "hole-length"
        end
    end

    participation = mode_participation(prop, node, elem, rep.L)

    return (; W, Ls, Rconv, lfL, cfsm, R_at, rep, method_key, true_pt, true_key,
              hole_length, R_D, cfsm_D, conv_shape, cfsm_shape, participation, rejected_troughs)
end

const METHOD_DESCRIPTION = Dict(
    "signature"   => "L-dominated signature-curve local minimum (trough) inside [0.5W, 2W]",
    "cFSM-Lcrl"   => "no L-dominated local minimum inside [0.5W, 2W]: Lcrl from the cFSM pure-local minimum, value from the signature curve at that Lcrl",
    "hole-length" => "Lcrl = punch-out length < true Lcrl: value from the net-section signature curve at L = punch-out length",
)


# ── Figures ────────────────────────────────────────────────────────────────────

"Plain-number tick positions and labels (1, 2, 5 per decade) for a log axis spanning [lo, hi]."
function plain_log_ticks(lo, hi)
    vals = Float64[]
    for k in floor(Int, log10(lo)):ceil(Int, log10(hi)), f in (1, 2, 5)
        v = f * 10.0^k
        lo <= v <= hi && push!(vals, v)
    end
    labels = [v >= 1 ? string(round(Int, v)) : rstrip(rstrip(@sprintf("%.6f", v), '0'), '.') for v in vals]
    return vals, labels
end

"Scale that draws the largest in-plane displacement of `shape` at 15 % of the section's larger dimension."
function deform_scale(shape)
    span = max(maximum(shape.X) - minimum(shape.X), maximum(shape.Y) - minimum(shape.Y))
    return 0.15 * span / max(maximum(hypot.(shape.ΔX, shape.ΔY)), 1e-12)
end

"""
Mode-shape inset (undeformed dashed black, buckled solid `color`) anchored
next to the point (L, R) of a log-log axis: the box's left edge sits at
`L * edge_mult` and its bottom at `R * lift_mult` (fractions computed in
log10 space), `dy_px` stacks a further inset above. The box takes the
aspect ratio of the drawn content (fitted into `size_px`) so DataAspect()
adds no letterboxing and the outline really sits next to the point.
"""
function add_mode_shape_inset_log!(fig, ax, shape, L, R; color, edge_mult = 1.08, lift_mult = 1.28,
                                   dy_px = 0.0, size_px = (80, 125))
    s  = deform_scale(shape)
    Xd = shape.X .+ s .* shape.ΔX
    Yd = shape.Y .+ s .* shape.ΔY
    allX, allY = vcat(shape.X, Xd), vcat(shape.Y, Yd)
    data_w = max(maximum(allX) - minimum(allX), 1e-6)
    data_h = max(maximum(allY) - minimum(allY), 1e-6)
    fit = min(size_px[1] / data_w, size_px[2] / data_h)
    w, h = data_w * fit, data_h * fit
    bbox = lift(ax.finallimits, ax.scene.viewport) do lims, area
        x0, xw = lims.origin[1], lims.widths[1]
        y0, yw = lims.origin[2], lims.widths[2]
        xfrac = (log10(L * edge_mult) - log10(x0)) / (log10(x0 + xw) - log10(x0))
        yfrac = (log10(R * lift_mult) - log10(y0)) / (log10(y0 + yw) - log10(y0))
        px = area.origin[1] + xfrac * area.widths[1]
        py = area.origin[2] + yfrac * area.widths[2] + dy_px
        BBox(px, px + w, py, py + h)
    end
    ax_mode = Axis(fig, bbox = bbox, aspect = DataAspect(), backgroundcolor = :transparent)
    hidedecorations!(ax_mode); hidespines!(ax_mode)
    lines!(ax_mode, shape.X, shape.Y; color = :black, linestyle = :dash, linewidth = 1)
    lines!(ax_mode, Xd, Yd; color = color, linewidth = 2)
    xlims!(ax_mode, minimum(allX) - 0.05 * data_w, maximum(allX) + 0.05 * data_w)
    ylims!(ax_mode, minimum(allY) - 0.05 * data_h, maximum(allY) + 0.05 * data_h)
end

lhole() = rich("L", subscript("hole"))

"""
Signature curve (black) and cFSM pure-local curve (blue dashed) of one model,
with the [0.5W, 2W] search range shaded. Markers:
  • blue diamond  -- cFSM pure-local minimum, with its buckled shape in blue;
  • hollow circle -- the signature curve at that cFSM Lcrl;
  • red circle    -- the REPORTED point, with the conventional buckled shape in red.
Net-section models also show L = L_hole (punch-out length):
  • green square        -- signature curve at L = L_hole;
  • hollow green square -- cFSM pure-local curve at L = L_hole;
  • hollow red circle   -- the true Lcrl point when L_hole governs.
"""
function plot_signature_cfsm(res, m, name, savepath)
    Ls, Rconv, lfL = res.Ls, res.Rconv, res.lfL
    rep, cfsm, W   = res.rep, res.cfsm, res.W
    hole  = res.hole_length !== nothing
    by_D  = res.method_key == "hole-length"
    fin   = findall(isfinite, lfL)
    ymin  = min(minimum(Rconv), cfsm.R) / 1.6
    ymax  = maximum(Rconv) * 2.2

    fig = Figure(size = (840, 700), fontsize = 11)
    ax  = Axis(fig[1, 1];
        xlabel = "Elastic buckling half-wavelength (in.)", ylabel = rich("M", subscript("cr"), " (kip-in.)"),
        title  = "$name — $(m.key): $(m.label)", titlesize = 12,
        subtitle = "Reported value: " * METHOD_DESCRIPTION[res.method_key], subtitlesize = 9.5, subtitlecolor = :gray30,
        xscale = log10, yscale = log10,
        xticks = plain_log_ticks(minimum(Ls), maximum(Ls)), yticks = plain_log_ticks(ymin, ymax),
        xminorticksvisible = false, yminorticksvisible = false)
    ylims!(ax, ymin, ymax)
    xlims!(ax, minimum(Ls), maximum(Ls))

    vspan!(ax, RANGE_LO * W, RANGE_HI * W; color = (:gray70, 0.18))
    scatterlines!(ax, Ls, Rconv; markersize = 5, color = :black)
    lines!(ax, Ls[fin], lfL[fin]; color = :dodgerblue, linestyle = :dash, linewidth = 2)
    lines!(ax, [cfsm.L, cfsm.L], [min(cfsm.R, res.R_at), max(cfsm.R, res.R_at)]; color = (:black, 0.55), linestyle = :dot, linewidth = 1.6)
    scatter!(ax, [cfsm.L], [res.R_at]; color = :white, strokecolor = :black, strokewidth = 1.6, marker = :circle, markersize = 15)
    scatter!(ax, [cfsm.L], [cfsm.R]; color = :blue, marker = :diamond, markersize = 13)
    if hole
        isfinite(res.cfsm_D) && scatter!(ax, [res.hole_length], [res.cfsm_D]; color = :white, strokecolor = :forestgreen, strokewidth = 1.8, marker = :rect, markersize = 12)
        scatter!(ax, [res.hole_length], [res.R_D]; color = :forestgreen, marker = :rect, markersize = 11)
        by_D && scatter!(ax, [res.true_pt.L], [res.true_pt.R]; color = :white, strokecolor = :red, strokewidth = 1.8, marker = :circle, markersize = 12)
    end
    rej = res.rejected_troughs
    isempty(rej) || scatter!(ax, [r.L for r in rej], [r.R for r in rej]; color = :darkorange, marker = :xcross, markersize = 14)
    scatter!(ax, [rep.L], [rep.R]; color = :red, markersize = 9)
    text!(ax, rep.L, rep.R; text = @sprintf("%.3f %s", rep.R, m.unit), fontsize = 9.5, color = :black, align = (:center, :top), offset = (0, -11))

    # conventional shape at the reported point (red), cFSM pure-local shape at its minimum (blue);
    # stacked when the two points sit close together on the half-wavelength axis
    add_mode_shape_inset_log!(fig, ax, res.conv_shape, rep.L, rep.R; color = :red)
    close_pts = abs(log(cfsm.L / rep.L)) < log(1.8)
    add_mode_shape_inset_log!(fig, ax, res.cfsm_shape, close_pts ? rep.L : cfsm.L, close_pts ? rep.R : cfsm.R;
                              color = :blue, dy_px = close_pts ? 140.0 : 0.0)

    elems  = Any[[LineElement(color = :black, linewidth = 1.5), MarkerElement(color = :black, marker = :circle, markersize = 5)],
                 LineElement(color = :dodgerblue, linestyle = :dash, linewidth = 2),
                 PolyElement(color = (:gray70, 0.35)),
                 MarkerElement(color = :blue, marker = :diamond, markersize = 12),
                 MarkerElement(color = :white, strokecolor = :black, strokewidth = 1.6, marker = :circle, markersize = 13)]
    labels = Any["Conventional FSM signature curve (CUFSM) — actual rounded-corner geometry" * (hole ? ", net section" : ""),
                 "cFSM pure local mode (L only, BucklingModeIdentification.jl) — same geometry, elastic corners",
                 @sprintf("Search range [0.5W, 2W] = [%.3f, %.3f] in.", RANGE_LO * W, RANGE_HI * W),
                 @sprintf("cFSM pure-local minimum: %.3f %s at L = %.3f in.", cfsm.R, m.unit, cfsm.L),
                 @sprintf("Signature curve at the cFSM Lcrl: %.3f %s", res.R_at, m.unit)]
    if hole
        push!(elems, MarkerElement(color = :forestgreen, marker = :rect, markersize = 11))
        push!(labels, rich("Signature curve at L = ", lhole(), @sprintf(" = %.3f in. (punch-out length): %.3f %s", res.hole_length, res.R_D, m.unit)))
        push!(elems, MarkerElement(color = :white, strokecolor = :forestgreen, strokewidth = 1.8, marker = :rect, markersize = 11))
        push!(labels, rich("cFSM pure-local curve at L = ", lhole(), @sprintf(": %.3f %s", res.cfsm_D, m.unit)))
        if by_D
            push!(elems, MarkerElement(color = :white, strokecolor = :red, strokewidth = 1.8, marker = :circle, markersize = 12))
            push!(labels, @sprintf("True Lcrl of the net-section curve: %.3f %s at L = %.3f in. (%s)", res.true_pt.R, m.unit, res.true_pt.L,
                                   res.true_key == "signature" ? "trough" : "at the cFSM Lcrl"))
        end
    end
    for r in rej
        push!(elems, MarkerElement(color = :darkorange, marker = :xcross, markersize = 13))
        push!(labels, @sprintf("Trough rejected, %s-dominated (G/D/L/O = %.0f/%.0f/%.0f/%.0f %%): %.3f %s at L = %.3f in.",
                               r.dominant, r.participation.G, r.participation.D, r.participation.L, r.participation.O, r.R, m.unit, r.L))
    end
    push!(elems, MarkerElement(color = :red, marker = :circle, markersize = 10))
    push!(labels, @sprintf("Reported %s = %.3f %s at Lcrl = %.3f in. (G/D/L/O = %.0f/%.0f/%.0f/%.0f %%)", m.sym, rep.R, m.unit, rep.L,
                           res.participation.G, res.participation.D, res.participation.L, res.participation.O))
    push!(elems, [LineElement(color = :red, linewidth = 2), LineElement(color = :blue, linewidth = 2)])
    push!(labels, "Insets: conventional buckled shape at the reported point (red), cFSM pure-local shape (blue); undeformed dashed")
    Legend(fig[2, 1], elems, labels; orientation = :vertical, framevisible = false, labelsize = 9.5,
           halign = :left, tellwidth = false, tellheight = true, rowgap = 1, patchsize = (24, 12), padding = (8, 8, 2, 2))
    note = "Rule: W = $(@sprintf("%.3f", W)) in. is the widest flat element of the section. The true Lcrl is the first local minimum (falls, then rises) " *
           "of the signature curve inside [0.5W, 2W] whose mode is L-dominated (BucklingModeIdentification.jl G/D/L/O participation); if there is none, it is the minimum of the cFSM pure-local curve and the value is the signature curve there." *
           (hole ? @sprintf(" Net section at the punch-out (length %.3f in. along the member): Lcrl = min(true Lcrl, punch-out length); the reported value is the net-section signature curve at that Lcrl.", res.hole_length) : "")
    Label(fig[3, 1], note; fontsize = 8.5, color = :gray35, halign = :left, justification = :left, tellwidth = false, tellheight = true,
          word_wrap = true, padding = (8, 8, 0, 4))
    rowgap!(fig.layout, 6)
    save(savepath, fig)
    return savepath
end

"""
Two-panel figure of the FSM models: the full cross-section (Mcrl_no_hole) and
the net section at the punch-out (Mcrl_hole), with the removed part (bottom
flange and lower web) dashed red, the punch-out height dimensioned and each
model's centroid marked.
"""
function plot_cross_sections(name, X, Y, Xn, Yn, Xr, Yr, gross_sp, net_sp, t, punchout_height, punchout_width, savepath)
    fig = Figure(size = (1000, 620), fontsize = 12)
    pad = 0.35
    lims = (minimum(X) - pad - 0.6, maximum(X) + pad, minimum(Y) - pad, maximum(Y) + pad)

    ax1 = Axis(fig[1, 1]; title = "Full cross-section — Mcrl_no_hole", aspect = DataAspect(), limits = lims,
               xlabel = "x (in.)", ylabel = "y (in.)",
               subtitle = @sprintf("A = %.4f in.², Ixx = %.4f in.⁴, %d nodes", gross_sp.A, gross_sp.Ixx, length(X)), subtitlesize = 10)
    lines!(ax1, X, Y; color = :steelblue, linewidth = 2.5)
    scatter!(ax1, X, Y; color = :steelblue, markersize = 5)
    scatter!(ax1, [gross_sp.xc], [gross_sp.yc]; marker = :cross, color = :black, markersize = 12)
    text!(ax1, gross_sp.xc, gross_sp.yc; text = @sprintf("  centroid, y = %.3f in.", gross_sp.yc), fontsize = 10, align = (:left, :center))

    ax2 = Axis(fig[1, 2]; title = "Net section at the punch-out — Mcrl_hole", aspect = DataAspect(), limits = lims,
               xlabel = "x (in.)", ylabel = "y (in.)",
               subtitle = @sprintf("A = %.4f in.², Ixx = %.4f in.⁴, %d nodes", net_sp.A, net_sp.Ixx, length(Xn)), subtitlesize = 10)
    lines!(ax2, Xr, Yr; color = :red, linestyle = :dash, linewidth = 2.5)
    lines!(ax2, Xn, Yn; color = :steelblue, linewidth = 2.5)
    scatter!(ax2, Xn, Yn; color = :steelblue, markersize = 5)
    scatter!(ax2, [net_sp.xc], [net_sp.yc]; marker = :cross, color = :black, markersize = 12)
    text!(ax2, net_sp.xc, net_sp.yc; text = @sprintf("  centroid, y = %.3f in.", net_sp.yc), fontsize = 10, align = (:left, :center))
    hlines!(ax2, [punchout_height]; color = (:red, 0.5), linestyle = :dot, linewidth = 1.2)
    # punch-out height dimension, bottom face (y = 0) to the cut
    x_dim = minimum(X) - 0.35
    lines!(ax2, [x_dim, x_dim], [0.0, punchout_height]; color = :black, linewidth = 1.2)
    scatter!(ax2, [x_dim, x_dim], [0.0, punchout_height]; marker = [:utriangle, :dtriangle], color = :black, markersize = 9)
    lines!(ax2, [x_dim - 0.08, x_dim + 0.08], [0.0, 0.0]; color = :black, linewidth = 1.2)
    text!(ax2, x_dim - 0.08, punchout_height / 2; text = @sprintf("punch-out height %.3f in.", punchout_height),
          rotation = π / 2, align = (:center, :bottom), fontsize = 10)

    elems  = [LineElement(color = :steelblue, linewidth = 2.5), LineElement(color = :red, linestyle = :dash, linewidth = 2.5),
              MarkerElement(color = :black, marker = :cross, markersize = 12)]
    labels = ["Centerline used in the finite strip model", "Removed by the punch-out (bottom flange, bottom corner, lower web)", "Centroid of the model"]
    Legend(fig[2, 1:2], elems, labels; orientation = :horizontal, framevisible = false, labelsize = 10)
    Label(fig[3, 1:2], @sprintf("%s, t = %.3f in. Punch-out %.3f in. long (along the member) × %.3f in. high, measured from the bottom face. Coordinates are the centerline; bottom face at y = 0.",
                                name, t, punchout_width, punchout_height); fontsize = 10, color = :gray30)
    linkaxes!(ax1, ax2)
    save(savepath, fig)
    return savepath
end


# ── Specimen analysis and JSON ─────────────────────────────────────────────────

"NaN / Inf -> nothing, so the output is valid JSON for Typst."
_js(x::Real) = isfinite(x) ? Float64(x) : nothing
_js(x) = x

function model_result(res, m, sp, figure)
    p = res.participation
    return (
        model = m.key, label = m.label, unit = m.unit, figure = figure,
        Mcrl = _js(res.rep.R), Lcrl = _js(res.rep.L), Lcrl_over_W = _js(res.rep.L / res.W), W = _js(res.W),
        method = res.method_key, method_description = METHOD_DESCRIPTION[res.method_key],
        cfsm_Lcrl = _js(res.cfsm.L), cfsm_Mcrl = _js(res.cfsm.R),
        signature_at_cfsm_Lcrl = _js(res.R_at), ratio_signature_over_cfsm = _js(res.R_at / res.cfsm.R),
        true_method = res.true_key, true_Lcrl = _js(res.true_pt.L), true_Mcrl = _js(res.true_pt.R),
        L_hole = res.hole_length === nothing ? nothing : _js(res.hole_length),
        signature_at_L_hole = _js(res.R_D), cfsm_at_L_hole = _js(res.cfsm_D),
        participation = (G = _js(p.G), D = _js(p.D), L = _js(p.L), O = _js(p.O)),
        rejected_troughs = [(L = _js(r.L), M = _js(r.R), dominant = r.dominant,
                             participation = (G = _js(r.participation.G), D = _js(r.participation.D),
                                              L = _js(r.participation.L), O = _js(r.participation.O))) for r in res.rejected_troughs],
        My = _js(sp.My), Mcrl_over_My = _js(res.rep.R / sp.My), lambda_l = _js(sqrt(sp.My / res.rep.R)),
        curve = (L = _js.(res.Ls), signature = _js.(res.Rconv), cfsm_local = _js.(res.lfL)),
    )
end

section_json(sp) = (A = sp.A, xc = sp.xc, yc = sp.yc, Ixx = sp.Ixx, Iyy = sp.Iyy, Ixy = sp.Ixy, Sc = sp.Sc, St = sp.St, My = sp.My, c_top = sp.c_top)

"""
    analyze_specimen(row, E, ν, Fy; output_dir)

Gross (Mcrl_no_hole) and punch-out net-section (Mcrl_hole) local buckling of
one database/IntelliFrameRF.csv row, with its figures written to
`output_dir/figures/cfsm/<key>/`. Returns the JSON-ready NamedTuple; figure
paths in it are relative to `output_dir` (where Report.typ lives).
"""
function analyze_specimen(row, E, ν, Fy; output_dir)
    name = String(row.section_name)
    key  = specimen_key(name)
    dims = specimen_dimensions(row)
    t    = dims[1]
    (ismissing(row.punchout_height) || ismissing(row.punchout_width)) && error(
        "punch-out dimensions of \"$name\" are not filled in database/IntelliFrameRF.csv (punchout_height = $(row.punchout_height), punchout_width = $(row.punchout_width)) -- the net section (Mcrl_hole) and IntelliFrame's own retrofit model both need them")
    hp, Lh = Float64(row.punchout_height), Float64(row.punchout_width)

    X, Y = gross_centerline(dims)
    Xn, Yn, Xr, Yr = punchout_net_centerline(X, Y, hp; t, web_angle = dims[7])
    gross_sp = section_properties(X, Y, t, Fy)
    net_sp   = section_properties(Xn, Yn, t, Fy)

    res_gross = local_buckling(X, Y, t, E, ν)
    res_net   = local_buckling(Xn, Yn, t, E, ν; hole_length = Lh)

    rel_dir = joinpath(FIGURES_DIR, key)
    mkpath(joinpath(output_dir, rel_dir))
    rel(f) = replace(joinpath(rel_dir, f), "\\" => "/")   # Typst paths
    plot_cross_sections(name, X, Y, Xn, Yn, Xr, Yr, gross_sp, net_sp, t, hp, Lh, joinpath(output_dir, rel_dir, "cross_section.png"))
    plot_signature_cfsm(res_gross, MODELS.Mcrl_no_hole, name, joinpath(output_dir, rel_dir, "Mcrl_no_hole.png"))
    plot_signature_cfsm(res_net,   MODELS.Mcrl_hole,    name, joinpath(output_dir, rel_dir, "Mcrl_hole.png"))

    return (
        section_name = name, key = key,
        dimensions = (t = t, B_bottom = dims[2], H = dims[3], B_top = dims[4], D = dims[5],
                      bottom_flange_angle = dims[6], web_angle = dims[7], top_flange_angle = dims[8], lip_angle = dims[9],
                      r1 = dims[10], r2 = dims[11], r3 = dims[12]),
        punchout = (height = hp, length = Lh),
        gross_section = section_json(gross_sp), net_section = section_json(net_sp),
        figures = (cross_section = rel("cross_section.png"),),
        Mcrl_no_hole = model_result(res_gross, MODELS.Mcrl_no_hole, gross_sp, rel("Mcrl_no_hole.png")),
        Mcrl_hole    = model_result(res_net,   MODELS.Mcrl_hole,    net_sp,   rel("Mcrl_hole.png")),
        Mcrl_hole_over_no_hole = _js(res_net.rep.R / res_gross.rep.R),
    )
end


# ── Driver entry points ────────────────────────────────────────────────────────

"""
    run_all_calculations(inputs_path, output_dir; database_path = DATABASE_PATH)

Reads `inputs.json` (IntelliFrame material and the user-selected
`intelli_frame_type`), runs `analyze_specimen` for that one section of
`database_path`, and writes `output_dir/cfsm_local_buckling.json` plus its
figures under `output_dir/figures/cfsm/<key>/`. Returns the results.
"""
function run_all_calculations(inputs_path::AbstractString, output_dir::AbstractString;
                              database_path::AbstractString = DATABASE_PATH)
    inputs = open(JSON3.read, inputs_path)
    mat = inputs.intelli_frame_material
    E, ν, Fy = Float64(mat.E_ksi), Float64(mat.nu), Float64(mat.Fy_ksi)
    selected = String(inputs.intelli_frame_type)

    db = CSV.read(database_path, DataFrame)
    i = findfirst(==(selected), db.section_name)
    i === nothing && error("intelli_frame_type \"$selected\" is not in $(basename(database_path)); available: $(join(db.section_name, ", "))")
    mkpath(output_dir)

    print("  ", selected, " … "); flush(stdout)
    specimen = analyze_specimen(db[i, :], E, ν, Fy; output_dir)
    @printf("Mcrl_no_hole = %.3f kip-in. (%s), Mcrl_hole = %.3f kip-in. (%s)
",
            specimen.Mcrl_no_hole.Mcrl, specimen.Mcrl_no_hole.method, specimen.Mcrl_hole.Mcrl, specimen.Mcrl_hole.method)

    results = (
        material = (E = E, nu = ν, Fy = Fy),
        method = (range_lo_W = RANGE_LO, range_hi_W = RANGE_HI, plot_lo_W = PLOT_LO, plot_hi_W = PLOT_HI,
                  n_range = N_RANGE, fsm_n = FSM_N, fsm_n_radius = FSM_N_RADIUS, min_segment_t = MIN_SEGMENT,
                  reference_moment = "Mxx = +1 kip-in. about the centroidal x-axis (top in compression), restrained bending",
                  corner_model = "elastic", boundary_conditions = "S-S"),
        specimen = specimen,
    )
    out = joinpath(output_dir, RESULTS_FILE)
    open(out, "w") do f
        JSON3.write(f, results)
        println(f)
    end
    println("written: ", abspath(out))

    # allowable pressure of the existing line and the IntelliFrame retrofit, gravity and uplift
    # (retrofit positive Mcrℓ = min of IntelliFrame's combined model and the bare-member cFSM value)
    capacity = IntelliFrame_Capacity.run_capacity_analysis(inputs, output_dir, specimen; intelli_frame_data = db)
    out = joinpath(output_dir, CAPACITY_FILE)
    open(out, "w") do f
        JSON3.write(f, _clean(capacity))
        println(f)
    end
    println("written: ", abspath(out))
    return (local_buckling = results, capacity = capacity)
end

"Recursively replace NaN/Inf by nothing so the file is valid JSON for Typst."
_clean(x::AbstractFloat) = isfinite(x) ? x : nothing
_clean(x::NamedTuple) = map(_clean, x)
_clean(x::Tuple) = map(_clean, x)
_clean(x::AbstractVector) = map(_clean, x)
_clean(x::AbstractDict) = Dict(k => _clean(v) for (k, v) in x)
_clean(x) = x

function _find_typst()
    typst = Sys.which("typst")
    typst === nothing && error("Typst CLI not found on PATH -- install it (e.g. `winget install Typst.Typst`) to export the PDF")
    return typst
end

"""
    export_pdf(inputs_path, output_dir; root_dir = dirname(dirname(inputs_path)))

Compiles `output_dir/Report.typ` (client report) and, when present,
`output_dir/Report_detailed.typ` (full design record) to PDF with the Typst
CLI. `root_dir` must contain both `frontend_output/` and `output_dir`.
Returns the PDF paths.
"""
function export_pdf(inputs_path::AbstractString, output_dir::AbstractString;
                    root_dir::AbstractString = dirname(dirname(inputs_path)))
    typst = _find_typst()
    pdfs = String[]
    for name in ("Report", "Report_detailed")
        report_typ = joinpath(output_dir, "$name.typ")
        isfile(report_typ) || continue
        report_pdf = joinpath(output_dir, "$name.pdf")
        run(`$typst compile --root $root_dir $report_typ $report_pdf`)
        println("written: ", abspath(report_pdf))
        push!(pdfs, report_pdf)
    end
    return pdfs
end

end # module IntelliFrame_cFSM
