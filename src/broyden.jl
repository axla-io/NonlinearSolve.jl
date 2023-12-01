# Sadly `Broyden` is taken up by SimpleNonlinearSolve.jl
"""
    GeneralBroyden(; max_resets = 3, linesearch = nothing, reset_tolerance = nothing)

An implementation of `Broyden` with resetting and line search.

## Arguments

  - `max_resets`: the maximum number of resets to perform. Defaults to `3`.
  - `reset_tolerance`: the tolerance for the reset check. Defaults to
    `sqrt(eps(real(eltype(u))))`.
  - `linesearch`: the line search algorithm to use. Defaults to [`LineSearch()`](@ref),
    which means that no line search is performed. Algorithms from `LineSearches.jl` can be
    used here directly, and they will be converted to the correct `LineSearch`. It is
    recommended to use [LiFukushimaLineSearch](@ref) -- a derivative free linesearch
    specifically designed for Broyden's method.
"""
@concrete struct GeneralBroyden <: AbstractNewtonAlgorithm{false, Nothing}
    max_resets::Int
    reset_tolerance
    linesearch
end

function GeneralBroyden(; max_resets = 3, linesearch = nothing,
        reset_tolerance = nothing)
    linesearch = linesearch isa LineSearch ? linesearch : LineSearch(; method = linesearch)
    return GeneralBroyden(max_resets, reset_tolerance, linesearch)
end

@concrete mutable struct GeneralBroydenCache{iip} <: AbstractNonlinearSolveCache{iip}
    f
    alg
    u
    u_cache
    du
    fu
    fu_cache
    dfu
    p
    J⁻¹
    J⁻¹dfu
    force_stop::Bool
    resets::Int
    max_resets::Int
    maxiters::Int
    internalnorm
    retcode::ReturnCode.T
    abstol
    reltol
    reset_tolerance
    reset_check
    prob
    stats::NLStats
    ls_cache
    tc_cache
    trace
end

function SciMLBase.__init(prob::NonlinearProblem{uType, iip}, alg::GeneralBroyden, args...;
        alias_u0 = false, maxiters = 1000, abstol = nothing, reltol = nothing,
        termination_condition = nothing, internalnorm::F = DEFAULT_NORM,
        kwargs...) where {uType, iip, F}
    @unpack f, u0, p = prob
    u = __maybe_unaliased(u0, alias_u0)
    fu = evaluate_f(prob, u)
    @bb du = copy(u)
    J⁻¹ = __init_identity_jacobian(u, fu)
    reset_tolerance = alg.reset_tolerance === nothing ? sqrt(eps(real(eltype(u)))) :
                      alg.reset_tolerance
    reset_check = x -> abs(x) ≤ reset_tolerance

    @bb u_cache = copy(u)
    @bb fu_cache = copy(fu)
    @bb dfu = similar(fu)
    @bb J⁻¹dfu = similar(u)

    abstol, reltol, tc_cache = init_termination_cache(abstol, reltol, fu, u,
        termination_condition)
    trace = init_nonlinearsolve_trace(alg, u, fu, J⁻¹, du; uses_jac_inverse = Val(true),
        kwargs...)

    return GeneralBroydenCache{iip}(f, alg, u, u_cache, du, fu, fu_cache, dfu, p,
        J⁻¹, J⁻¹dfu, false, 0, alg.max_resets, maxiters, internalnorm, ReturnCode.Default,
        abstol, reltol, reset_tolerance, reset_check, prob, NLStats(1, 0, 0, 0, 0),
        init_linesearch_cache(alg.linesearch, f, u, p, fu, Val(iip)), tc_cache, trace)
end

function perform_step!(cache::GeneralBroydenCache{iip}) where {iip}
    T = eltype(cache.u)

    @bb cache.du = cache.J⁻¹ × vec(cache.fu)
    α = perform_linesearch!(cache.ls_cache, cache.u, cache.du)
    @bb axpy!(-α, cache.du, cache.u)

    evaluate_f(cache, cache.u, cache.p)

    update_trace!(cache, α)
    check_and_update!(cache, cache.fu, cache.u, cache.u_cache)

    cache.force_stop && return nothing

    # Update the inverse jacobian
    @bb @. cache.dfu = cache.fu - cache.fu_cache

    if all(cache.reset_check, cache.du) || all(cache.reset_check, cache.dfu)
        if cache.resets ≥ cache.max_resets
            cache.retcode = ReturnCode.ConvergenceFailure
            cache.force_stop = true
            return nothing
        end
        cache.J⁻¹ = __reinit_identity_jacobian!!(cache.J⁻¹)
        cache.resets += 1
    else
        @bb cache.du .*= -1
        @bb cache.J⁻¹dfu = cache.J⁻¹ × vec(cache.dfu)
        @bb cache.u_cache = transpose(cache.J⁻¹) × vec(cache.du)
        denom = dot(cache.du, cache.J⁻¹dfu)
        @bb @. cache.du = (cache.du - cache.J⁻¹dfu) / ifelse(iszero(denom), T(1e-5), denom)
        @bb cache.J⁻¹ += vec(cache.du) × transpose(cache.u_cache)
    end

    @bb copyto!(cache.fu_cache, cache.fu)
    @bb copyto!(cache.u_cache, cache.u)

    return nothing
end

function __reinit_internal!(cache::GeneralBroydenCache; kwargs...)
    cache.J⁻¹ = __reinit_identity_jacobian!!(cache.J⁻¹)
    cache.resets = 0
    return nothing
end
