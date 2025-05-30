# Linesearch from Algorithm 851: CG_DESCENT
# (Hager & Zhang, ACM Transactions on Mathematical Software, Vol 32 (2006))
abstract type AbstractLineSearch end

struct LineSearchPoint{T<:Real,X,G}
    α::T # step length
    ϕ::T # local function value
    dϕ::T # local directional derivative of cost function: dϕ/dα
    x::X
    f::T # equal to ϕ
    ∇f::G # gradient in point
    ξ::G # local tangent at linesearch path: dϕ = inner(x, ξ, ∇f)
end

function checkapproxwolfe(x::LineSearchPoint, x₀::LineSearchPoint, c₁, c₂, ϵ)
    return (x.ϕ <= x₀.ϕ + ϵ) && ((2 * c₁ - 1) * x₀.dϕ >= x.dϕ >= c₂ * x₀.dϕ)
end
function checkexactwolfe(x::LineSearchPoint, x₀::LineSearchPoint, c₁, c₂)
    return (x.ϕ <= x₀.ϕ + c₁ * x.α * x₀.dϕ) && (x.dϕ > c₂ * x₀.dϕ)
end

# Hager-Zhang Line Search Algorithm
# Algorithm 851: CG_DESCENT
# (Hager & Zhang, ACM Transactions on Mathematical Software, Vol 32 (2006))

struct HagerZhangLineSearch{T<:Real} <: AbstractLineSearch
    c₁::T # parameter for the (approximate) first Wolfe condition (Armijo rule), controlling sufficient decay of function value: c₁ < 1/2 < c₂
    c₂::T # parameter for the second Wolfe condition (curvature contition), controlling sufficient decay of slope: c₁ < 1/2 < c₂
    ϵ::T # parameter for expected accuracy of objective function, controlling maximal allowed increase in function value
    θ::T # parameter regulating the bisection step
    γ::T # parameter triggering the bisection step, namely if bracket reduction rate is slower than `γ`
    ρ::T # parameter controlling the initial bracket expansion rate
    maxiter::Int # hard limit on the number of iterations
    maxfg::Int # soft limit on the number of function evaluations
    verbosity::Int # verbosity level
end

"""
    struct HagerZhangLineSearch{T<:Real} <: AbstractLineSearch
    HagerZhangLineSearch(; c₁::Real = 1//10, c₂::Real = 9//10, ϵ::Real = 1//10^6,
                        θ::Real = 1//2, γ::Real = 2//3, ρ::Real = 5//1)

Constructs a Hager-Zhang line search object with the specified parameters.

## Arguments:
- `c₁::Real`: Parameter for the (approximate) first Wolfe condition (Armijo rule), controlling sufficient decay of function value: c₁ < 1/2 < c₂. Default is `1//10`.
- `c₂::Real`: Parameter for the second Wolfe condition (curvature contition), controlling sufficient decay of slope: c₁ < 1/2 < c₂. Default is `9//10`.
- `ϵ::Real`: Parameter for expected accuracy of objective function, controlling maximal allowed increase in function value. Default is `1//10^6`.
- `θ::Real`: Parameter regulating the bisection step. Default is `1//2` (should probably not be changed).
- `γ::Real`: Parameter triggering the bisection step, namely if bracket reduction rate is slower than `γ`. Default is `2//3`.
- `ρ::Real`: Parameter controlling the initial bracket expansion rate. Default is `5//1`.

## Returns:
This method returns a `HagerZhangLineSearch` object `ls`, that can then be can be applied as `ls(fg, x₀, η₀; kwargs...)`
to perform a line search for function `fg` that computes the objective function and its gradient at a given point, starting
from `x₀` in direction `η₀`.
"""
function HagerZhangLineSearch(; c₁::Real=1 // 10,
                              c₂::Real=9 // 10,
                              ϵ::Real=1 // 10^6,
                              θ::Real=1 // 2,
                              γ::Real=2 // 3,
                              ρ::Real=5 // 1,
                              maxiter::Int=LS_MAXITER[],
                              maxfg::Int=LS_MAXFG[],
                              verbosity::Int=LS_VERBOSITY[])
    return HagerZhangLineSearch(promote(c₁, c₂, ϵ, θ, γ, ρ)..., maxiter, maxfg, verbosity)
end

# implementation as function
"""
    (ls::HagerZhangLineSearch)(fg, x₀, η₀, fg₀ = fg(x₀);
                    retract = _retract, inner = _inner,
                    initialguess = one(fg₀[1]), acceptfirst = false,
                    maxiter = ls.maxiter, maxfg = lsmaxfg, verbosity = ls.verbosity)

Perform a Hager-Zhang line search to find a step length that satisfies the (approximate) Wolfe conditions.

## Arguments:
- `ls::HagerZhangLineSearch`: The HagerZhangLineSearch object.
- `fg`: Function that computes the objective function and its gradient.
- `x₀`: Starting point.
- `η₀`: Search direction.
- `fg₀`: Objective function and gradient evaluated at `x₀`. Defaults to `fg(x₀)`, but can be supplied if this information has already been calculated.

## Keyword Arguments:
- `retract`: Function that performs the retraction step, i.e. the generalisation of `x₀ + α * η₀`. Defaults to `_retract`.
- `inner`: Function that computes the inner product between search direction and gradient. Defaults to `_inner`.
- `initialguess::Real`: Initial guess for the step length. Defaults to `one(fg₀[1])`.
- `acceptfirst::Bool`: Parameter that controls whether the initial guess can be accepted if it satisfies the strong Wolfe conditions. Defaults to `false`, thus requiring 
  at least one line search iteration and one extra function evaluation.
- `maxiter::Int`: Hard limit on the number of iterations. Default is `50`.
- `maxfg::Int`: Soft limit on the number of function evaluations. Default is `100`.
- `verbosity::Int`: The verbosity level (see below). Default is `0`.

### Verbosity Levels
- `0`: No output.
- `1`: Single output about convergence when the linesearch has terminated.
- `2`: Output after the start and every individual iteration step of the Hager-Zhang linesearch.
- `3`: Additional output about the initial bracketing and further bracket update and bisection steps.
- `4`: Output after every function evaluation in the bracketing, updating, and bisection steps.

## Returns:
- `x`: The point `retract(x₀, η₀, α)` where the (approximate) Wolfe conditions are satisfied.
- `f`: Function value at `x`.
- `g`: Gradient at `x`.
- `ξ`: Tangent at `x` to the line search path.
- `α`: Step length that satisfies the (approximate) Wolfe conditions.
- `numfg`: Number of function evaluations performed.
"""
function (ls::HagerZhangLineSearch)(fg, x₀, η₀, fg₀=fg(x₀);
                                    retract=_retract, inner=_inner,
                                    initialguess::Real=one(fg₀[1]),
                                    acceptfirst::Bool=false,
                                    maxiter::Int=ls.maxiter,
                                    maxfg::Int=ls.maxfg,
                                    verbosity::Int=ls.verbosity)
    (f₀, g₀) = fg₀
    ϕ₀ = f₀
    dϕ₀ = inner(x₀, g₀, η₀)
    if dϕ₀ >= zero(dϕ₀)
        @warn "Linesearch was not given a descent direction: returning zero step length"
        return x₀, f₀, g₀, η₀, zero(one(f₀)), 0
    end

    p₀ = LineSearchPoint(zero(ϕ₀), ϕ₀, dϕ₀, x₀, f₀, g₀, η₀)
    iter = HagerZhangLineSearchIterator(fg, retract, inner, p₀, η₀, initialguess,
                                        acceptfirst, verbosity, ls)
    verbosity >= 2 &&
        @info @sprintf("Linesearch start: dϕ₀ = %.2e, ϕ₀ = %.2e", dϕ₀, ϕ₀)
    next = iterate(iter)
    @assert next !== nothing

    k = 1
    while true
        (x, f, g, ξ, α, dϕ), state = next
        a, b, numfg, done = state
        verbosity >= 3 &&
            @info @sprintf("Linesearch iteration step %d, function evaluation count %d:\n[a,b] = [%.2e, %.2e], dϕᵃ = %.2e, dϕᵇ = %.2e, ϕᵃ - ϕ₀ = %.2e, ϕᵇ - ϕ₀ = %.2e",
                           k, numfg, a.α, b.α, a.dϕ, b.dϕ, a.ϕ - ϕ₀, b.ϕ - ϕ₀)
        if done
            verbosity >= 2 &&
                @info @sprintf("Linesearch converged after %d iterations and %d function evaluations:\nα = %.2e, dϕ = %.2e, ϕ - ϕ₀ = %.2e",
                               k, numfg, α, dϕ, f - ϕ₀)
            return x, f, g, ξ, α, numfg
        elseif k >= maxiter || numfg >= maxfg
            verbosity >= 1 &&
                @warn @sprintf("Linesearch not converged after %d iterations and %d function evaluations:\nα = %.2e, dϕ = %.2e, ϕ - ϕ₀ = %.2e",
                               k, numfg, α, dϕ, f - ϕ₀)
            return x, f, g, ξ, α, numfg
        else
            next = iterate(iter, state)
            @assert next !== nothing
            k += 1
        end
    end
end

# Hager-Zhang Line Search Algorithm implemented as iterator
struct HagerZhangLineSearchIterator{T₁<:Real,F₁,F₂,F₃,X,G,T₂<:Real}
    fdf::F₁ # computes function value and gradient for a given x, i.e. f, g = f(x)
    retract::F₂ # function used to step in direction η₀ with step size α, i.e. x, ξ = retract(x₀, η₀, α) where x = Rₓ₀(α*η₀) is the new position and ξ = D Rₓ₀(α*η₀)[η₀] is the derivative or tangent of x to α at the position x
    inner::F₃ # function used to compute inner product between gradient and direction, i.e. dϕ = inner(x, g, d); can depend on x (i.e. metric on a manifold)
    p₀::LineSearchPoint{T₁,X,G} # initial position, containing x₀, f₀, g₀
    η₀::G # search direction
    α₀::T₁ # initial guess for step size
    acceptfirst::Bool # whether or not the initial guess can be accepted (e.g. LBFGS)
    verbosity::Int # verbosity level
    parameters::HagerZhangLineSearch{T₂}
end

function Base.iterate(iter::HagerZhangLineSearchIterator)
    c₁ = iter.parameters.c₁
    c₂ = iter.parameters.c₂
    ϵ = iter.parameters.ϵ
    verbosity = iter.verbosity
    p₀ = iter.p₀

    # L0 in the Line Search Algorithm: take initial step
    c = takestep(iter, iter.α₀)
    numfg = 1
    if iter.acceptfirst
        ewolfe = checkexactwolfe(c, p₀, c₁, c₂)
        awolfe = checkapproxwolfe(c, p₀, c₁, c₂, ϵ)
        verbosity >= 4 &&
            @info @sprintf("  Linesearch initial step: c = %.2e, dϕᶜ = %.2e, ϕᶜ - ϕ₀ = %.2e, exact wolfe = %d, approx wolfe = %d",
                           c.α, c.dϕ, c.ϕ - p₀.ϕ, ewolfe, awolfe)
        if ewolfe || awolfe
            return (c.x, c.f, c.∇f, c.ξ, c.α, c.dϕ), (c, c, numfg, true)
        end
    else
        verbosity >= 4 &&
            @info @sprintf("  Linesearch initial step (cannot be accepted): c = %.2e, dϕᶜ = %.2e, ϕᶜ - ϕ₀ = %.2e",
                           c.α, c.dϕ, c.ϕ - p₀.ϕ)
    end

    # L0 in the Line Search Algorithm: find initial bracketing interval
    a, b, nfg = bracket(iter, c)
    verbosity >= 4 &&
        @info @sprintf("  Linesearch initial bracket: [a,b] = [%.2e, %.2e], dϕᵃ = %.2e, dϕᵇ = %.2e, ϕᵃ - ϕ₀ = %.2e, ϕᵇ - ϕ₀ = %.2e",
                       a.α, b.α, a.dϕ, b.dϕ, a.ϕ - p₀.ϕ, b.ϕ - p₀.ϕ)

    numfg += nfg
    if a.α == b.α
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, true)
    elseif (b.α - a.α) < eps(one(a.α))
        verbosity >= 1 &&
            @warn @sprintf("  Linesearch bracket converged to a point without satisfying Wolfe conditions: [a,b] = [%.2e, %.2e], dϕᵃ = %.2e, dϕᵇ = %.2e, ϕᵃ - ϕ₀ = %.2e, ϕᵇ - ϕ₀ = %.2e",
                           a.α, b.α, a.dϕ, b.dϕ, a.ϕ - p₀.ϕ, b.ϕ - p₀.ϕ)
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, true)
    else
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, false)
    end
end

function Base.iterate(iter::HagerZhangLineSearchIterator,
                      state::Tuple{LineSearchPoint,LineSearchPoint,Int,Bool})
    c₁ = iter.parameters.c₁
    c₂ = iter.parameters.c₂
    ϵ = iter.parameters.ϵ
    verbosity = iter.verbosity
    p₀ = iter.p₀

    a, b, numfg, done = state
    if done
        return nothing
    end
    dα = b.α - a.α

    # L1 in the Line Search Algorithm: secant2 step
    αc = secant(a.α, b.α, a.dϕ, b.dϕ)
    A, B, nfg = update(iter, a, b, αc)
    numfg += nfg
    if A.α == B.α
        return (A.x, A.f, A.∇f, A.ξ, A.α, A.dϕ), (A, B, numfg, true)
    end
    if αc == B.α
        αc = secant(b.α, B.α, b.dϕ, B.dϕ)
        a, b, nfg = update(iter, A, B, αc)
        numfg += nfg
    elseif αc == A.α
        αc = secant(a.α, A.α, a.dϕ, A.dϕ)
        a, b, nfg = update(iter, A, B, αc)
        numfg += nfg
    else
        a, b = A, B
    end
    verbosity >= 4 &&
        @info @sprintf("  Linesearch updated bracket (secant2): [a,b] = [%.2e, %.2e], dϕᵃ = %.2e, dϕᵇ = %.2e, ϕᵃ - ϕ₀ = %.2e, ϕᵇ - ϕ₀ = %.2e",
                       a.α, b.α, a.dϕ, b.dϕ, a.ϕ - p₀.ϕ, b.ϕ - p₀.ϕ)
    if a.α == b.α
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, true)
    end

    # L2 in the Line Search Algorithm: bisection step if secant2 convergence too slow
    if b.α - a.α > iter.parameters.γ * dα
        a, b, nfg = update(iter, a, b, (a.α + b.α) / 2)
        numfg += nfg
        verbosity >= 4 &&
            @info @sprintf("  Linesearch updated bracket (bisection): [a,b] = [%.2e, %.2e], dϕᵃ = %.2e, dϕᵇ = %.2e, ϕᵃ - ϕ₀ = %.2e, ϕᵇ - ϕ₀ = %.2e",
                           a.α, b.α, a.dϕ, b.dϕ, a.ϕ - p₀.ϕ, b.ϕ - p₀.ϕ)
    end
    if a.α == b.α
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, true)
    elseif (b.α - a.α) < eps(one(a.α))
        verbosity >= 1 &&
            @warn @sprintf("  Linesearch bracket converged to a point without satisfying Wolfe conditions: [a,b] = [%.2e, %.2e], dϕᵃ = %.2e, dϕᵇ = %.2e, ϕᵃ - ϕ₀ = %.2e, ϕᵇ - ϕ₀ = %.2e",
                           a.α, b.α, a.dϕ, b.dϕ, a.ϕ - p₀.ϕ, b.ϕ - p₀.ϕ)
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, true)
    else
        return (a.x, a.f, a.∇f, a.ξ, a.α, a.dϕ), (a, b, numfg, false)
    end
end

# auxiliary methods

# main function for taking a step and computing the necessary line search quantities
function takestep(iter, α)
    x, ξ = iter.retract(iter.p₀.x, iter.η₀, α)
    f, ∇f = iter.fdf(x)
    ϕ = f
    dϕ = iter.inner(x, ∇f, ξ)
    return LineSearchPoint(α, ϕ, dϕ, x, f, ∇f, ξ)
end

# secant method for finding the next guess
secant(a, b, fa, fb) = (a * fb - b * fa) / (fb - fa)

# update bracketing interval: interval has (a.dϕ < 0, a.ϕ <= f₀+ϵ), (b.dϕ >= 0)
# the bisection step is separtely implemented in the bisect function
function update(iter::HagerZhangLineSearchIterator, a::LineSearchPoint, b::LineSearchPoint,
                αc)
    p₀ = iter.p₀
    c₁ = iter.parameters.c₁
    c₂ = iter.parameters.c₂
    ϵ = iter.parameters.ϵ
    verbosity = iter.verbosity
    ϕ₀ = iter.p₀.f
    fmax = ϕ₀ + iter.parameters.ϵ

    !(a.α < αc < b.α) && return a, b, 0 # line U0: secant point not in interval, rely on L2

    # take step
    c = takestep(iter, αc) # try secant point
    !isfinite(c.ϕ) &&
        error("Linesearch bracket update: invalid function value for step length $αc")

    ewolfe = checkexactwolfe(c, p₀, c₁, c₂)
    awolfe = checkapproxwolfe(c, p₀, c₁, c₂, ϵ)
    verbosity >= 4 &&
        @info @sprintf("  Linesearch update step (U1-U2): c = %.2e, dϕᶜ = %.2e, ϕᶜ - ϕ₀ = %.2e, exact wolfe = %d, approx wolfe = %d",
                       c.α, c.dϕ, c.ϕ - ϕ₀, ewolfe, awolfe)
    if ewolfe || awolfe
        return c, c, 1
    end
    if c.dϕ >= zero(c.dϕ) # U1
        return a, c, 1
    elseif c.dϕ < zero(c.dϕ) && c.ϕ <= fmax # U2
        return c, b, 1
    else # U3
        a, b, nfg = bisect(iter, a, c)
        return a, b, nfg + 1
    end
end
function bisect(iter::HagerZhangLineSearchIterator, a::LineSearchPoint, b::LineSearchPoint)
    # applied when (a.dϕ < 0, a.ϕ <= f₀+ϵ), (b.dϕ < 0, b.ϕ > f₀+ϵ)
    θ = iter.parameters.θ
    p₀ = iter.p₀
    c₁ = iter.parameters.c₁
    c₂ = iter.parameters.c₂
    ϵ = iter.parameters.ϵ
    maxfg = iter.parameters.maxfg
    verbosity = iter.verbosity
    fmax = p₀.f + ϵ
    numfg = 0
    while true
        if numfg >= maxfg || (b.α - a.α) <= eps(one(a.α))
            if verbosity >= 1
                @warn @sprintf("  Linesearch bisection failure: [a, b] = [%.2e, %.2e], b-a = %.2e, dϕᵃ = %.2e, dϕᵇ = %.2e, (ϕᵇ - ϕᵃ)/(b-a) = %.2e",
                               a.α, b.α, b.α - a.α, a.dϕ, b.dϕ, (b.ϕ - a.ϕ) / (b.α - a.α))
            end
            return a, b, numfg
        end
        αd = (1 - θ) * a.α + θ * b.α
        d = takestep(iter, αd)
        numfg += 1
        ewolfe = checkexactwolfe(d, p₀, c₁, c₂)
        awolfe = checkapproxwolfe(d, p₀, c₁, c₂, ϵ)
        verbosity >= 4 &&
            @info @sprintf("  Linesearch bisection update (U3): d = %.2e, dϕᵈ = %.2e, ϕᵈ - ϕ₀ = %.2e, exact wolfe = %d, approx wolfe = %d",
                           d.α, d.dϕ, d.ϕ - p₀.ϕ, ewolfe, awolfe)
        if ewolfe || awolfe
            return d, d, numfg
        end
        if d.dϕ >= 0 # Line U3.a
            return a, d, numfg
        elseif d.ϕ <= fmax # Line U3.b
            a = d
        else # Line U3.c
            b = d
        end
    end
end

# bracket function for finding an initial bracketing interval from a given initial step
function bracket(iter::HagerZhangLineSearchIterator{T}, c::LineSearchPoint) where {T}
    numfg = 0
    p₀ = iter.p₀
    c₁ = iter.parameters.c₁
    c₂ = iter.parameters.c₂
    ϵ = iter.parameters.ϵ
    maxfg = iter.parameters.maxfg
    verbosity = iter.verbosity
    a = p₀
    fmax = a.f + ϵ

    α = c.α
    while true
        while numfg < maxfg && !(isfinite(c.ϕ) && isfinite(c.dϕ))
            α = (a.α + α) / 2
            c = takestep(iter, α)
            numfg += 1
            verbosity >= 4 &&
                @info @sprintf("  Linesearch bracket step: c = %.2e, dϕᶜ = %.2e, ϕᶜ - ϕ₀ = %.2e",
                               c.α, c.dϕ, c.ϕ - p₀.ϕ)
        end
        c.dϕ >= 0 && return a, c, numfg# B1
        # from here: c.dϕ < 0
        if c.ϕ > fmax # B2
            a, b, nfg = bisect(iter, iter.p₀, c)
            return a, b, numfg + nfg
        else# B3
            a = c
            α *= iter.parameters.ρ
            c = takestep(iter, α)
            numfg += 1
            verbosity >= 4 &&
                @info @sprintf("  Linesearch bracket step: c = %.2e, dϕᶜ = %.2e, ϕᶜ - ϕ₀ = %.2e",
                               c.α, c.dϕ, c.ϕ - p₀.ϕ)
            if checkexactwolfe(c, p₀, c₁, c₂) || checkapproxwolfe(c, p₀, c₁, c₂, ϵ)
                return c, c, numfg
            end
        end
    end
end

# Backtracking attempt by Lander (@leburgel)
# ------------------------------------------

# shamelessly copied from
# https://github.com/JuliaNLSolvers/LineSearches.jl/blob/master/src/backtracking.jl

struct BackTrackingLineSearch{T<:Real} <: AbstractLineSearch
    c₁::T
    ρ_hi::T
    ρ_lo::T
    maxstep::T
    order::Int
    maxiter::Int
    maxfg::Int
    verbosity::Int
end
function BackTrackingLineSearch(;
                                c₁::Real=1e-4,
                                ρ_hi::Real=0.5,
                                ρ_lo::Real=0.1,
                                maxstep::Real=Inf,
                                order::Int=3,
                                maxiter::Int=LS_MAXITER[],
                                maxfg::Int=LS_MAXFG[],
                                verbosity::Int=LS_VERBOSITY[])
    return BackTrackingLineSearch(promote(c₁, ρ_hi, ρ_lo, maxstep)..., order, maxiter,
                                  maxfg, verbosity)
end

function (ls::BackTrackingLineSearch)(fg, x₀, η₀, fg₀=fg(x₀);
                                      retract=_retract, inner=_inner,
                                      initialguess::Real=one(fg₀[1]),
                                      acceptfirst::Bool=false,
                                      maxiter::Int=ls.maxiter,
                                      maxfg::Int=ls.maxfg,
                                      verbosity::Int=ls.verbosity)

    # initialize
    (f₀, g₀) = fg₀
    ϕ₀ = f₀
    dϕ₀ = inner(x₀, g₀, η₀)

    # translate
    αinitial = initialguess
    ϕ_0 = ϕ₀
    dϕ_0 = dϕ₀
    Tα = typeof(αinitial)
    c_1 = ls.c₁
    ρ_hi = ls.ρ_hi
    ρ_lo = ls.ρ_lo
    iterations = maxiter
    order = ls.order

    iterfinitemax = -log2(eps(real(Tα)))

    @assert order in (2, 3)

    # Count the total number of iterations and function applications
    iteration = 0
    numfg = 0

    # Wrap retraction and function evaluation
    function move(α)
        numfg += 1
        x, ξ = retract(x₀, η₀, α)
        f, g = fg(x)
        return x, f, g, ξ
    end

    ϕx_0, ϕx_1 = ϕ_0, ϕ_0

    α_1, α_2 = αinitial, αinitial

    # Evaluate f(x) at proposed position
    x, ϕx_1, g, ξ = move(α_1)

    # Hard-coded backtrack until we find a finite function value
    iterfinite = 0
    while !isfinite(ϕx_1) && iterfinite < iterfinitemax
        iterfinite += 1
        α_1 = α_2
        α_2 = α_1 / 2

        x, ϕx_1, g, ξ = move(α_2)
    end

    # Backtrack until we satisfy sufficient decrease condition
    cancel = false
    while ϕx_1 > ϕ_0 + c_1 * α_2 * dϕ_0
        # Increment the number of steps we've had to perform
        iteration += 1

        # Ensure termination
        if iteration > iterations || numfg >= maxfg
            verbosity >= 1 &&
                @warn "Linesearch not converged after $iterations iterations and $numfg function evaluations; α = $(α_2)"
            cancel = true
            break
        end

        # Shrink proposed step-size:
        if order == 2 || iteration == 1
            α_tmp = -(dϕ_0 * α_2^2) / (2 * (ϕx_1 - ϕ_0 - dϕ_0 * α_2))
        else
            div = one(Tα) / (α_1^2 * α_2^2 * (α_2 - α_1))
            a = (α_1^2 * (ϕx_1 - ϕ_0 - dϕ_0 * α_2) - α_2^2 * (ϕx_0 - ϕ_0 - dϕ_0 * α_1)) *
                div
            b = (-α_1^3 * (ϕx_1 - ϕ_0 - dϕ_0 * α_2) + α_2^3 * (ϕx_0 - ϕ_0 - dϕ_0 * α_1)) *
                div

            if isapprox(a, zero(a); atol=eps(real(Tα)))
                α_tmp = dϕ_0 / (2 * b)
            else
                # discriminant
                d = max(b^2 - 3 * a * dϕ_0, Tα(0))
                # quadratic equation root
                α_tmp = (-b + sqrt(d)) / (3 * a)
            end
        end

        α_1 = α_2

        α_tmp = NaNMath.min(α_tmp, α_2 * ρ_hi) # avoid too small reductions
        α_2 = NaNMath.max(α_tmp, α_2 * ρ_lo) # avoid too big reductions

        # Evaluate f(x) at proposed position
        x, f, g, ξ = move(α_2)

        # Shift
        ϕx_0, ϕx_1 = ϕx_1, f
    end

    if cancel
        # take forced step
        α_2 /= 2 # but be very careful...
        x, ϕx_1, g, ξ = move(α_2)
    end

    return x, ϕx_1, g, ξ, α_2, numfg
end
