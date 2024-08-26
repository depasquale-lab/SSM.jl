export Emission, getproperty, setproperty!
export GaussianEmission, validate_data, emission_sample, emission_loglikelihood, emission_fit!


"""
Every emission model must implement the following functions:

- emission_sample(model::EmissionModel, data...; observation_sequence)
    The point of this function is to iteratively sample from the emission model through repeated calls of the form:
    `
    observation_sequence = emission_sample(model, data...)
    observation_sequence = emission_sample(model, data..., observation_sequence=observation_sequence)
    observation_sequence = emission_sample(model, data..., observation_sequence=observation_sequence)
    observation_sequence = emission_sample(model, data..., observation_sequence=observation_sequence)
    `
    Et cetera.

    NOTE: The observation_sequence argument is optional, and when it is not passed in, the function should return a NEW observation sequence with one observation.
- emission_loglikelihood(model::EmissionModel, data...)
    This function should return a vector of loglikelihoods for each observation in the data.
- emission_fit!(model::EmissionModel, data..., weights)
    This function should fit the model to the data, with weights for each observation.

Make sure to add any new emission models to the Emission function at the end of this file!!
"""


"""
Gaussian Emission
"""

mutable struct GaussianEmission <: EmissionModel
    inner_model:: Gaussian
end


function emission_sample(model::GaussianEmission; observation_sequence::Matrix{<:Real}=Matrix{Float64}(undef, 0, model.output_dim))
    validate_model(model)

    raw_samples = rand(MvNormal(model.μ, model.Σ), 1)    

    return vcat(observation_sequence, Matrix(raw_samples'))
end

function emission_loglikelihood(model::GaussianEmission, Y::Matrix{<:Real})
    validate_model(model)
    validate_data(model, Y)

    # calculate inverse of covariance matrix
    Σ_inv = inv(model.Σ)

    # calculate log likelihood
    residuals = broadcast(-, Y, model.μ')
    observation_wise_loglikelihood = zeros(size(Y, 1))

    # calculate observation wise loglikelihood (a vector of loglikelihoods for each observation)
    @threads for i in 1:size(Y, 1)
        observation_wise_loglikelihood[i] = -0.5 * size(Y, 2) * log(2π) - 0.5 * logdet(model.Σ) - 0.5 * sum(residuals[i, :] .* (Σ_inv * residuals[i, :]))
    end

    return observation_wise_loglikelihood
end

function emission_fit!(model::GaussianEmission, Y::Matrix{<:Real}, w::Vector{Float64}=ones(size(Y, 1)))
    fit!(model.inner_model, Y, w)
end

function GaussianHMM(; K::Int, output_dim::Int, A::Matrix{<:Real}=initialize_transition_matrix(K), πₖ::Vector{Float64}=initialize_state_distribution(K))
    # Create emission models
    emissions = [Gaussian(output_dim=output_dim) for _ in 1:K]
    # Return constructed GaussianHMM
    return HiddenMarkovModel(K=K, B=emissions, A=A, πₖ=πₖ)
end



"""
Gaussian Regression
"""

mutable struct GaussianRegressionEmission <: EmissionModel
    inner_model:: GaussianRegression
end

# custom sampling function for the HMM. Returns observation_sequence with new observation appended to bottom.
function emission_sample(model::GaussianRegressionEmission, Φ::Matrix{<:Real}; observation_sequence::Matrix{<:Real}=Matrix{Float64}(undef, 0, model.output_dim))
    validate_model(model)
    validate_data(model, Φ)

    # find the number of observations in the observation sequence
    t = size(observation_sequence, 1) + 1
    # get the n+1th observation
    new_observation = sample(model.inner_model, Φ[t:t, :], n=1)

    return vcat(observation_sequence, new_observation)
end


function emission_loglikelihood(model::GaussianRegressionEmission, Φ::Matrix{<:Real}, Y::Matrix{<:Real})
    validate_model(model)
    validate_data(model, Φ, Y)

    # calculate observation wise likelihoods for all states
    observation_wise_loglikelihood = zeros(size(Y, 1))

    # calculate observation wise loglikelihood (a vector of loglikelihoods for each observation)
    @threads for i in 1:size(Y, 1)
        observation_wise_loglikelihood[i] = loglikelihood(model.inner_model, Φ[i:i, :], Y[i:i, :])
    end

    return observation_wise_loglikelihood
end

function emission_fit!(model::GaussianRegressionEmission, Φ::Matrix{<:Real}, Y::Matrix{<:Real}, w::Vector{Float64}=ones(size(Y, 1)))
    fit!(model.inner_model, Φ, Y, w)
end


function SwitchingGaussianRegression(; 
    K::Int,
    input_dim::Int,
    output_dim::Int,
    include_intercept::Bool = true,
    β::Matrix{<:Real} = if include_intercept
        zeros(input_dim + 1, output_dim)
    else
        zeros(input_dim, output_dim)
    end,
    Σ::Matrix{<:Real} = Matrix{Float64}(I, output_dim, output_dim),
    λ::Float64 = 0.0,
    A::Matrix{<:Real} = initialize_transition_matrix(K),
    πₖ::Vector{Float64} = initialize_state_distribution(K)
)
    # Create emission models
    emissions = [GaussianRegression(input_dim=input_dim, output_dim=output_dim, include_intercept=include_intercept, β=β, Σ=Σ, λ=λ) for _ in 1:K]

    # Return the HiddenMarkovModel
    return HiddenMarkovModel(K=K, B=emissions, A=A, πₖ=πₖ)
end

"""
Bernoulli Regression
"""

mutable struct BernoulliRegressionEmission <: EmissionModel
    inner_model:: BernoulliRegression
end

function emission_sample(model::BernoulliRegressionEmission, Φ::Matrix{<:Real}; observation_sequence::Matrix{<:Real} = Matrix{Float64}(undef, 0, 1))
    # find the number of observations in the observation sequence
    t = size(observation_sequence, 1) + 1
    # get the n+1th observation
    new_observation = sample(model.inner_model, Φ[t:t, :], n=1)

    return vcat(observation_sequence, new_observation)
end

function emission_loglikelihood(model::BernoulliRegressionEmission, Φ::Matrix{<:Real}, Y::Matrix{<:Real}, w::Vector{Float64}=ones(size(Y, 1)))
    # confirm that the model has valid parameters
    validate_model(model)
    validate_data(model, Φ, Y, w)

    # add intercept if specified and not already included
    if model.include_intercept && size(Φ, 2) == length(model.β) - 1 
        Φ = hcat(ones(size(Φ, 1)), Φ)
    end

    # calculate log likelihood
    p = logistic.(Φ * model.β)

    obs_wise_loglikelihood = w .* (Y .* log.(p) .+ (1 .- Y) .* log.(1 .- p))


    return obs_wise_loglikelihood
end

function emission_fit!(model::BernoulliRegressionEmission, Φ::Matrix{<:Real}, Y::Matrix{<:Real}, w::Vector{Float64}=ones(size(Y, 1)))
    fit!(model.inner_model, Φ, Y, w)
end

function SwitchingBernoulliRegression(; 
    K::Int,
    input_dim::Int,
    include_intercept::Bool=true,
    β::Vector{<:Real} = if include_intercept zeros(input_dim + 1) else zeros(input_dim) end,
    λ::Float64 = 0.0,
    A::Matrix{<:Real} = initialize_transition_matrix(K),
    πₖ::Vector{Float64} = initialize_state_distribution(K)
)
    # Create emission models
    emissions = [BernoulliRegression(input_dim=input_dim, include_intercept=include_intercept, β=β, λ=λ) for _ in 1:K]
    # Return the HiddenMarkovModel
    return HiddenMarkovModel(K=K, B=emissions, A=A, πₖ=πₖ)
end


"""
AutoRegression
"""

mutable struct AutoRegressionEmission <: EmissionModel
    inner_model:: AutoRegression
end

function emission_sample(model::AutoRegressionEmission, Y_prev::Matrix{<:Real}; observation_sequence::Matrix{<:Real}=Matrix{Float64}(undef, 0, model.output_dim))

    full_sequence = vcat(Y_prev, observation_sequence)

    # get the n+1th observation
    new_observation = sample(model.inner_model, full_sequence[end-model.order+1:end, :], n=1)

    return vcat(observation_sequence, new_observation)
end

function emission_loglikelihood(model::AutoRegressionEmission, Y_prev::Matrix{<:Real}, Y::Matrix{<:Real})
    # confirm that the model has valid parameters
    validate_model(model)
    validate_data(model, Y_prev, Y)

    Φ_gaussian = AR_to_Gaussian_data(Y_prev, Y)

    # extract inner gaussian regression and wrap it with a GaussianEmission
    innerGaussianRegression_emission = GaussianRegressionEmission(model.inner_model.innerGaussianRegression)

    return emission_loglikelihood(innerGaussianRegression_emission, Φ_gaussian, Y)
end

function emission_fit!(model::AutoRegressionEmission, Y_prev::Matrix{<:Real}, Y::Matrix{<:Real}, w::Vector{Float64}=ones(size(Y, 1)))
    fit!(model.inner_model, Y_prev, Y, w)
end

function SwitchingAutoRegression(; 
    K::Int,
    output_dim::Int, 
    order::Int, 
    include_intercept::Bool = true, 
    β::Matrix{<:Real} = if include_intercept zeros(output_dim * order + 1, output_dim) else zeros(output_dim * order, output_dim) end,
    Σ::Matrix{<:Real} = Matrix{Float64}(I, output_dim, output_dim),
    λ::Float64=0.0,
    A::Matrix{<:Real} = initialize_transition_matrix(K),
    πₖ::Vector{Float64} = initialize_state_distribution(K)
)
    # Create the emissions
    emissions = [AutoRegression(output_dim=output_dim, order=order, include_intercept=include_intercept, β=β, Σ=Σ, λ=λ) for _ in 1:K]
    # Return the HiddenMarkovModel
    return HiddenMarkovModel(K=K, B=emissions, A=A, πₖ=πₖ)
end


"""
Composite Model
"""

mutable struct CompositeModelEmission <: EmissionModel
    inner_model:: CompositeModel
end

function validate_model(model::CompositeModelEmission)
    validate_model(model.inner_model)

    # check that all components are valid emission models
    for component in model.components
        if !(component isa EmissionModel)
            throw(ArgumentError("The model $(typeof(component)) is not a valid emission model."))
        end
    end
end

function emission_sample(model::CompositeModelEmission, input_data::Vector{}; observation_sequence::Vector{}=Vector())
    validate_model(model)

    if isempty(observation_sequence)
        for i in 1:length(model.components)
            push!(observation_sequence, (emission_sample(model.components[i], input_data[i]...),))
        end 
    else
        for i in 1:length(model.components)
            observation_sequence[i] = (emission_sample(model.components[i], input_data[i]...; observation_sequence=observation_sequence[i][1]),)
        end 
    end

    return observation_sequence
end

function emission_loglikelihood(model::CompositeModelEmission, input_data::Vector{}, output_data::Vector{})
    validate_model(model)
    validate_data(model, input_data, output_data)

    loglikelihoods = Vector{}(undef, length(model.components))


    for i in 1:length(model.components)
        loglikelihoods[i] = emission_loglikelihood(model.components[i], input_data[i]..., output_data[i]...)
    end
    return sum(loglikelihoods, dims=1)[1]
end

function emission_fit!(model::CompositeModelEmission, input_data::Vector{}, output_data::Vector{}, w::Vector{Float64}=Vector{Float64}())
    for i in 1:length(model.components)
        emission_fit!(model.components[i], input_data[i]..., output_data[i]..., w)
    end
end

"""
Validation Functions
"""

function validate_model(model::EmissionModel)
    validate_model(model.inner_model)
end


function validate_data(model::EmissionModel, data...)
    validate_data(model.inner_model, data...)
end


"""
Emission handler
"""
function Emission(model::Model)
    if model isa Gaussian
        return GaussianEmission(model)
    elseif model isa GaussianRegression
        return GaussianRegressionEmission(model)
    elseif model isa BernoulliRegression
        return BernoulliRegressionEmission(model)
    elseif model isa AutoRegression
        return AutoRegressionEmission(model)
    elseif model isa CompositeModel
        emission_components = Emission.(model.components)
        new_composite = CompositeModel(emission_components)
        return CompositeModelEmission(new_composite)
    else
        # throw an error if the model is not a valid emission model
        throw(ArgumentError("The model is not a valid emission model."))
    end
end 

