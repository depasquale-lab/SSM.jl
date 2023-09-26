export  GMM, fit!, log_likelihood

mutable struct GMM
    k_means::Int
    μ_k::Matrix{Float64}
    Σ_k::Array{Matrix{Float64}, 1}
    π_k::Vector{Float64}
end

function isposdef(mat::Matrix{Float64})
    return all(eigvals(mat) .> 0)
end

function GMM(k_means::Int, data_dim::Int, data::Matrix{Float64})
    μ = kmeanspp_initialization(data, k_means)
    Σ = [I(data_dim) for _ = 1:k_means]
    πs = ones(k_means) ./ k_means
    return GMM(k_means, μ, Σ, πs)
end

function euclidean_distance(a::Vector{Float64}, b::Vector{Float64})
    return sqrt(sum((a .- b).^2))
end

function kmeanspp_initialization(data::Matrix{Float64}, k_means::Int)
    N, D = size(data)
    centroids = zeros(D, k_means)
    rand_idx = rand(1:N)
    centroids[:, 1] = data[rand_idx, :]

    for k in 2:k_means
        dists = zeros(N)
        for i in 1:N
            dists[i] = minimum([euclidean_distance(data[i, :], centroids[:, j]) for j in 1:(k-1)])
        end
        probs = dists .^ 2
        probs ./= sum(probs)
        next_idx = sample(1:N, Weights(probs))
        centroids[:, k] = data[next_idx, :]
    end
    return centroids
end

function EStep!(gmm::GMM, data::Matrix{Float64})
    N, K = size(data, 1), gmm.k_means
    log_γ = zeros(N, K)
    γ = zeros(N, K)  # Separate variable to hold γ
    
    for n in 1:N
        for k in 1:K
            log_density = logpdf(MvNormal(gmm.μ_k[:, k], gmm.Σ_k[k]), data[n, :])
            log_γ[n, k] = log(gmm.π_k[k]) + log_density
        end
    end
    println("Debug EStep: max(log_γ) = ", maximum(log_γ), ", min(log_γ) = ", minimum(log_γ))
    # Numerically stabilize the computation of γ
    for n in 1:N
        max_log_γ = maximum(log_γ[n, :])
        γ[n, :] = exp.(log_γ[n, :] .- max_log_γ)  # Take the exponential of (log_γ - max_log_γ)
        γ[n, :] ./= sum(γ[n, :])  # Normalize to sum to 1
    end
    return γ  # Return the γ
end

function MStep!(gmm::GMM, data::Matrix{Float64}, γ::Matrix{Float64})
    N, D = size(data)
    K = gmm.k_means

    # Initializing the variables to zero
    N_k = zeros(K)
    μ_k = zeros(D, K)
    Σ_k = zeros(D, D, K)

    # Easier to perform element-wise multiplication with data if it's transposed once
    data_t = data'

    for k in 1:K
        N_k[k] = sum(γ[:, k])
        println("Debug MStep: N_k for cluster $k = ", N_k[k])
        μ_k[:, k] = sum(data_t .* γ[:, k]', dims=2) ./ N_k[k]
        Σ_k[:,:,k] = zeros(D, D)
    end

    for n in 1:N
        for k in 1:K
            x_n = data[n, :] .- μ_k[:, k]'
            Σ_k[:,:,k] += (γ[n, k] .* (x_n' * x_n))
        end
    end
    
    for k in 1:K
        Σ_k[:,:,k] ./= N_k[k]
        if !isposdef(gmm.Σ_k[k])
            println("Debug: Covariance matrix Σ_$k is not positive definite!")
        end
        gmm.π_k[k] = N_k[k] / N
    end
    
    gmm.μ_k = μ_k
    gmm.Σ_k = [Σ_k[:,:,k] for k in 1:K]
end

function log_likelihood(gmm::GMM, data::Matrix{Float64})
    N, K = size(data, 1), gmm.k_means
    ll = 0.0
    for n in 1:N
        log_probabilities = [log(gmm.π_k[k]) + logpdf(MvNormal(gmm.μ_k[:, k], gmm.Σ_k[k]), data[n, :]) for k in 1:K]
        max_log_prob = maximum(log_probabilities)
        ll_n = max_log_prob + log(sum(exp(log_prob - max_log_prob) for log_prob in log_probabilities))
        ll += ll_n
    end
    return ll
end

function fit!(gmm::GMM, data::Matrix{Float64}; maxiter::Int=50, tol::Float64=1e-3)
    prev_ll = -Inf  # Initialize to negative infinity
    for i = 1:maxiter
        # E-Step
        γ_s = EStep!(gmm, data)
        # M-Step
        MStep!(gmm, data, γ_s)
        # Calculate current log-likelihood
        curr_ll = log_likelihood(gmm, data)
        # Debug: Output log-likelihood
        println("Iteration: $i, Log-likelihood: $curr_ll")
        # Check for convergence
        if abs(curr_ll - prev_ll) < tol
            println("Convergence reached at iteration $i")
            break
        end
        prev_ll = curr_ll
    end
end
