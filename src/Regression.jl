export RegressionModel, Link, GaussianRegression, IdentityLink,
       LogLink, LogitLink, ProbitLink, InverseLink, Loss, LSELoss, CrossEntropyLoss, fit!

# Abstract types
"""
    RegressionModel

Abstract type for GLM's, especially for SSM's.
"""
abstract type RegressionModel end

"""
    Link

Abstract type for Link functions.
"""
abstract type Link end

"""
    Loss

Abstract type for Loss functions.
"""
abstract type Loss end

# Loss Functions
"""
    LSELoss

Struct representing the least squared error loss function.
"""
struct LSELoss <: Loss end

# Compute loss for MSE
function compute_loss(::LSELoss, y_pred::Vector{Float64}, y_true::Vector{Float64})::Float64
    return sum((y_true .- y_pred).^2)
end

"""
    CrossEntropyLoss

Struct representing the cross-entropy loss function.
"""
struct CrossEntropyLoss <: Loss end

# Compute loss for CrossEntropy
function compute_loss(::CrossEntropyLoss, y_pred::Vector{Float64}, y_true::Vector{Float64})::Float64
    return -sum(y_true .* log.(y_pred) .+ (1 .- y_true) .* log.(1 .- y_pred))
end

# Link Functions
# Identity Link
"""
    IdentityLink

Struct representing the identity link function.
"""
struct IdentityLink <: Link end

# Functions for identity link with vectors
function link(::IdentityLink, μ::Vector{T})::Vector{T} where T <: Real
    return μ
end

function invlink(::IdentityLink, η::Vector{T})::Vector{T} where T <: Real
    return η
end

function derivlink(::IdentityLink, μ::Vector{T})::Vector{T} where T <: Real
    return ones(T, length(μ))
end

# Log Link
"""
    LogLink

Struct representing the log link function.
"""
struct LogLink <: Link end

# Functions for log link
function link(::LogLink, μ::Vector{T})::Vector{T} where T <: Real
    return log.(μ)
end

function invlink(::LogLink, η::Vector{T})::Vector{T} where T <: Real
    return exp.(η)
end

function derivlink(::LogLink, μ::Vector{T})::Vector{T} where T <: Real
    return inv.(μ)
end
# More link functions can be defined similarly...

# Define regression models here

# Gaussian Regression
"""
    GaussianRegression

Struct representing a Gaussian regression model.
"""
mutable struct GaussianRegression{T <: Real} <: RegressionModel
    X::Matrix{T}
    y::Vector{T}
    β::Vector{T}
    link::Link
end

# Define a constructor that only requires X and y, and uses default values for β
function GaussianRegression(X::Matrix{T}, y::Vector{T}, constant::Bool=true, link::Link=IdentityLink()) where T <: Real
    n, p = size(X)
    # add constant if specified, i.e. β₀ or the intercept term
    if constant
        X = hcat(ones(T, n), X)
        p += 1
    end
    β = zeros(p)  # initialize as zeros
    return GaussianRegression(X, y, β, link)
end

# Function to optimize the model
function fit!(model::GaussianRegression, loss::Loss=LSELoss(), max_iter::Int=1000)
    # Define objective function for optimization, this is what optim calls a "closure"
    # for details, see https://julianlsolvers.github.io/Optim.jl/
    function Objective(betas)
        return compute_loss(loss, invlink(model.link, model.X * betas), model.y)
    end
    # optimize
    result = optimize(Objective, model.β, LBFGS(), Optim.Options(iterations=max_iter))
    # update model
    model.β = Optim.minimizer(result)
end


