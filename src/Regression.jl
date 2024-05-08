# abstract regression type
abstract type Regression end

"""
    GaussianRegression

Args:
    β::Vector{Float64}: Coefficients of the regression model
    σ²::Float64: Variance of the regression model
    include_intercept::Bool: Whether to include an intercept term in the model
"""
mutable struct GaussianRegression <: Regression
    β::Vector{Float64}
    σ²::Float64
    include_intercept::Bool
    # Empty constructor
    GaussianRegression(; include_intercept::Bool = true) = new(Vector{Float64}(), 0.0, include_intercept)
    # Parametric Constructor
    GaussianRegression(β::Vector{Float64}, σ²::Float64, include_intercept::Bool) = new(β, σ², include_intercept)
end

function log_likelihood(model::GaussianRegression, X::Matrix{Float64}, y::Vector{Float64})
    # confirm that the model has been fit
    @assert !isempty(model.β) && model.σ² != 0.0 "Model parameters not initialized, please call fit! first."
    # calculate log likelihood
    residuals = y - X * model.β
    n = length(y)
    -0.5 * n * log(2π * model.σ²) - (0.5 / model.σ²) * sum(residuals.^2)
end

function least_squares(model::GaussianRegression, X::Matrix{Float64}, y::Vector{Float64})
    # confirm that the model has been fit
    @assert !isempty(model.β) "Model parameters not initialized, please call fit! first."
    residuals = y - X * model.β
    return sum(residuals.^2)
end

function gradient!(G::Vector{Float64}, model::GaussianRegression, X::Matrix{Float64}, y::Vector{Float64})
    # confirm that the model has been fit
    @assert !isempty(model.β) "Model parameters not initialized, please call fit! first."
    # calculate gradient
    residuals = y - X * model.β
    G .= 2 * X' * residuals
end

function update_variance!(model::GaussianRegression, X::Matrix{Float64}, y::Vector{Float64})
    # confirm that the model has been fit
    @assert !isempty(model.β) "Model parameters not initialized, please call fit! first."
    # get number of parameters
    p = length(model.β)
    residuals = y - X * model.β
    model.σ² = sum(residuals.^2) / (length(y) - p) # unbiased estimate
end

function fit!(model::GaussianRegression, X::Matrix{Float64}, y::Vector{Float64})
    # add intercept if specified
    if model.include_intercept
        X = hcat(ones(size(X, 1)), X)
    end
    # get number of parameters
    p = size(X, 2)
    # initialize parameters
    model.β = rand(p)
    model.σ² = 1.0
    # minimize objective
    objective(β) = least_squares(GaussianRegression(β, model.σ², true), X, y)
    objective_grad!(G, β) = gradient!(G, GaussianRegression(β, model.σ², true), X, y)

    result = optimize(objective, model.β, LBFGS(), Optim.Options())
    # update parameters
    model.β = result.minimizer
    update_variance!(model, X, y)
end

"""
    BernoulliRegression

Args:
    β::Vector{Float64}: Coefficients of the regression model
    include_intercept::Bool: Whether to include an intercept term in the model
"""
mutable struct BernoulliRegression <: Regression
    β::Vector{Float64}
    include_intercept::Bool
    # Empty constructor
    BernoulliRegression(; include_intercept::Bool = true) = new(Vector{Float64}(), include_intercept)
    # Parametric Constructor
    BernoulliRegression(β::Vector{Float64}, include_intercept::Bool) = new(β, include_intercept)
end

function log_likelihood(model::BernoulliRegression, X::Matrix{Float64}, y::Vector{Float64})
    # confirm that the model has been fit
    @assert !isempty(model.β) "Model parameters not initialized, please call fit! first."
    # add intercept if specified
    if model.include_intercept
        X = hcat(ones(size(X, 1)), X)
    end
    n = length(y)
    p = 1 ./ (1 .+ exp.(-X * model.β)) # use stats fun for this
    return sum(y .* log.(p) .+ (1 .- y) .* log.(1 .- p))
end