using Flux
using Statistics

include("prunelayers.jl")


abstract type FineTuner end

struct TuneByEpochs{T<:Integer} <: FineTuner
    value::T
end

struct TuneByAbsoluteLoss{T<:Number} <: FineTuner
    value::T
end

struct TuneByLossDifference{T<:Number} <: FineTuner
    value::T
end
struct TuneByAccuracyDifference{T<:Number} <: FineTuner
    value::T
end


const PruningSchedule = Vector{<:Tuple{<:PruningMethod, <:FineTuner}}

function scheduledpruning(model::Any, schedule::PruningSchedule, losstype::Function, optimiser::Flux.Optimise.AbstractOptimiser, data::Any; verbose::Bool=false)
    for (pruningmethod, strategy) ∈ schedule
        verbose && println("Applying ", typeof(pruningmethod))
        verbose && println("Old sparsity: ", sparsity(model))

        model = prunelayer(model, pruningmethod)

        verbose && println("Current sparsity: ", sparsity(model))

        parameters = Flux.params(model)

        loss(x, y) = losstype(model(x), y)

        finetune(strategy, loss, parameters, optimiser, data, verbose=verbose)
    end

    return model
end

function datasetloss(data::Any, loss::Function)
    losssum = 0.0
    numsamples = 0

    for (x, y) in data
        losssum += loss(x, y)
        numsamples += size(x)[end]
    end

    return (losssum / numsamples)
end

function trainandgetloss!(loss::Function, parameters::Any, data::Any, optimiser::Flux.Optimise.AbstractOptimiser)
    losssum = 0.0
    numsamples = 0

    for (x, y) in data
        gradients = gradient(() -> loss(x,y), parameters)
        Flux.Optimise.update!(optimiser, parameters, gradients)

        losssum += loss(x, y)
        numsamples += size(x)[end]
    end

    return (losssum / numsamples)
end

function trainandgetlossandaccuracy!(loss::Function, parameters::Any, data::Any, optimiser::Flux.Optimise.AbstractOptimiser)
    losssum = 0.0
    accuracysum = 0.0
    numsamples = 0

    for (x, y) in data
        gradients = gradient(() -> loss(x,y), parameters)
        Flux.Optimise.update!(optimiser, parameters, gradients)

        losssum += loss(x, y)
        accuracysum += sum(Flux.onecold(model(x)) .== Flux.onecold(y))
        numsamples += size(x)[end]
    end

    return (losssum / numsamples), (accuracysum / numsamples)
end

function finetune(strategy::TuneByEpochs, loss::Function, parameters::Any, optimiser::Flux.Optimise.AbstractOptimiser, data::Any; verbose::Bool=false)
    for epoch ∈ 1:strategy.value
        lossvalue = trainandgetloss!(loss, parameters, data, optimiser)
        verbose && println("epoch: $epoch - train loss: $lossvalue")
    end
end

function finetune(strategy::TuneByAbsoluteLoss, loss::Function, parameters::Any, optimiser::Flux.Optimise.AbstractOptimiser, data::Any; maxepochs::Integer=100, verbose::Bool=false)
    lossvalue = strategy.value + one(strategy.value)

    epoch = 0

    while (lossvalue > strategy.value) && (epoch < maxepochs)
        lossvalue = trainandgetloss!(loss, parameters, data, optimiser)

        epoch += 1
        verbose && println("epoch: $epoch - train loss: $(lossvalue)")
    end
end

function finetune(strategy::TuneByLossDifference, loss::Function, parameters::Any, optimiser::Flux.Optimise.AbstractOptimiser, data::Any; maxepochs::Integer=100, verbose::Bool=false)
    lossdiff = strategy.value + one(strategy.value)

    oldloss = 0.0
    epoch = 0

    while (lossdiff > strategy.value) && (epoch < maxepochs)
        lossvalue = trainandgetloss!(loss, parameters,data, optimiser)

        lossdiff = abs(oldloss - lossvalue)
        oldloss = lossvalue

        epoch += 1
        verbose && println("epoch: $epoch - train loss: $(oldloss)")
    end
end

function finetune(strategy::TuneByAccuracyDifference, loss::Function, parameters::Any, optimiser::Flux.Optimise.AbstractOptimiser, data::Any; maxepochs::Integer=100, verbose::Bool=false)
    accuracydiff = strategy.value + one(strategy.value)

    oldaccuracy = 0.0
    epoch = 0

    while (accuracydiff > strategy.value) && (epoch < maxepochs)
        lossvalue, accuracyvalue = trainandgetlossandaccuracy!(loss, parameters,data, optimiser)

        accuracydiff = accuracyvalue - oldaccuracy
        oldaccuracy = accuracyvalue

        epoch += 1
        verbose && println("epoch: $epoch - train accuracy: $(accuracyvalue) - train loss: $(lossvalue)")
    end
end
