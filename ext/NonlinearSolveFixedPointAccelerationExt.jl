module NonlinearSolveFixedPointAccelerationExt

using NonlinearSolve, FixedPointAcceleration, DiffEqBase, SciMLBase

function SciMLBase.__solve(prob::NonlinearProblem, alg::FixedPointAccelerationJL, args...;
        abstol = nothing, maxiters = 1000, alias_u0::Bool = false,
        show_trace::Val{PrintReports} = Val(false), termination_condition = nothing,
        kwargs...) where {PrintReports}
    @assert (termination_condition ===
             nothing)||(termination_condition isa AbsNormTerminationMode) "FixedPointAccelerationJL does not support termination conditions!"

    f, u0 = NonlinearSolve.__construct_f(prob; alias_u0, make_fixed_point = Val(true),
        force_oop = Val(true))

    tol = NonlinearSolve.DEFAULT_TOLERANCE(abstol, eltype(u0))

    sol = fixed_point(f, u0; Algorithm = alg.algorithm,
        ConvergenceMetricThreshold = tol, MaxIter = maxiters, MaxM = alg.m,
        ExtrapolationPeriod = alg.extrapolation_period, Dampening = alg.dampening,
        PrintReports, ReplaceInvalids = alg.replace_invalids,
        ConditionNumberThreshold = alg.condition_number_threshold, quiet_errors = true)

    if sol.FixedPoint_ === missing
        u0 = prob.u0 isa Number ? u0[1] : u0
        resid = NonlinearSolve.evaluate_f(prob, u0)
        res = u0
        converged = false
    else
        res = prob.u0 isa Number ? first(sol.FixedPoint_) :
              reshape(sol.FixedPoint_, size(prob.u0))
        resid = NonlinearSolve.evaluate_f(prob, res)
        converged = maximum(abs, resid) ≤ tol
    end
    return SciMLBase.build_solution(prob, alg, res, resid;
        retcode = converged ? ReturnCode.Success : ReturnCode.Failure,
        stats = SciMLBase.NLStats(sol.Iterations_, 0, 0, 0, sol.Iterations_),
        original = sol)
end

end
