#=
Finds the 10 most optimal number of clusters for the dataset for a human to review.
This program utilizes multithreading, so when the program is calculating the most optimal
clusters, the console output will be unintelligible.
=#

import Pkg
Pkg.add(["Clustering", "Cosmology", "DataFrames", "CSV", "Unitful", "PlotlyJS", "JLD", "Distances", "Plots"])

using Clustering, Cosmology, DataFrames, Distances, CSV, JLD, Statistics, Unitful, PlotlyJS, Dates
import Plots

"Add radial distance values to the dataset"
function add_dist!(c, data)
    data.dist = ustrip(comoving_radial_dist.(Ref(c), data.Z_HELIO))
end


"Adds absolute x, y, and z coordinates"
function add_xyz!(data)
    X = Vector{Float64}()
    Y = Vector{Float64}()
    Z = Vector{Float64}()

    println("Converting spherical coordinates to rectangular coordinates...")
    for n in eachindex(data.dist)
        val_x = data.dist[n] * sin(deg2rad(90 - data[!, "DEC"][n])) * cos(deg2rad(data[!, "RA"][n]))
        val_y = data.dist[n] * sin(deg2rad(90 - data[!, "DEC"][n])) * sin(deg2rad(data[!, "RA"][n]))
        val_z = data.dist[n] * cos(deg2rad(90 - data[!, "DEC"][n]))

        append!(X, val_x)
        append!(Y, val_y)
        append!(Z, val_z)
    end

    data.X = X
    data.Y = Y
    data.Z = Z
end


"Loads the distance matrix if the filepath exists. If not, it creates a distance matrix and writes to the filepath."
function load_dist_matrix(filepath::String)
    if !(isfile(filepath))
        println("Creating distance matrix...")
        P = pairwise(Euclidean(), data_matrix, dims=2)
        println("Saving distance matrix to '", filepath, "' for future use...")
        save(filepath, "data", P)
    else
        println(string("Loading distance matrix from '", filepath, "'..."))
        P = load(filepath, "data")
    end

    return P
end


"Generates a plot using the given data"
function generate_plot(data, output_file_path, n_clusters, name)
    p = plot(
        data,
        x=:X,
        y=:Y, 
        z=:Z,
        color=:assignments,
        type="scatter3d", 
        mode="markers",
        Layout(
            title=string("Galaxies Plotted in 3D Space (", n_clusters, " clusters): ", name), 
            scene = attr(
                # aspectmode="cube",
                # aspectratio=attr(x=1, y=1, z=1),
                xaxis_title="x: Distance (Mpc)",
                yaxis_title="y: Distance (Mpc)",
                zaxis_title="z: Distance (Mpc)",
                xaxis=attr(
                    range=[0,7000]
                ),
                yaxis=attr(
                    range=[0, 7000]
                ),
                zaxis=attr(
                    range=[-7000, 0]
                )
            ),
            font=attr(
                family="Courier New",
                size=18,
            )
        )
    )

    open(output_file_path, "w") do io
        PlotlyBase.to_html(io, p.plot)
    end
end


function generate_silhouette_plot(sub_counts, sub_averages, n_clusters)
    y = Vector{Float64}()
    for (key, val) in sub_averages
        append!(y, val)
    end
    p = Plots.bar(sub_counts, y, xlabel="# in subcluster", ylabel="avg silhouette score")
    Plots.savefig(p, string(pwd(), "/output/", n_clusters, "-subcluster-averages.png"))
end


"Returns the silhouette score of n clusters in the data"
function calc_silhouette_scores(P, n_clusters::Int)::NamedTuple
    R = kmedoids(P, n_clusters; maxiter=200, display=:iter)
    println(string("# of clusters: ", n_clusters))
    println(string("# in each cluster: ", counts(R)))
    
    println("Calculating silhouette scores...")
    S = silhouettes(R, P)
    
    subclusters = Dict{Integer, Vector}()
    for n in 1:n_clusters
        subclusters[n] = Vector{Float64}()
    end
    
    for n in eachindex(S)
        append!(subclusters[assignments(R)[n]], S[n])
    end
    
    sub_averages = Dict{Integer, Float64}()
    for (group_num, value) in subclusters
        sub_averages[group_num] = mean(value)
    end  
    
    return (total_average = mean(S), sub_averages = sub_averages, counts = counts(R))
end

"Generate list of top 10 global silhouette scores"
function generate_top10_global_scores(silhouette_means, silhouettes)
    str_output = ""
    
    for (i, (n_clusters, val)) in enumerate(sort(silhouette_means; byvalue=true))
        if i > 10
            break
        end
        
        silhouette_data = silhouettes[n_clusters]
        str_output *= string(n_clusters, " (", string(silhouette_means[n_clusters]), ")") * ": " * string(silhouette_data.sub_averages) * "\n"
    end

    open(string(pwd(), "/output/silhouette_scores.txt"), "a") do io
        write(io, str_output)
    end
end

"Generates the silhouette score histogram"
function generate_silhouette_score_histogram(name, silhouette_means, min_clusters, max_clusters)
    avg_scores = Float64[]
    for (i, val) in silhouette_means
        append!(avg_scores, val)
    end

    p = Plots.plot(min_clusters:max_clusters, avg_scores, xlabel="Number of clusters (k)", ylabel="Silhouette score", legend=false)
    Plots.savefig(p, string(pwd(), "/output/", name, "-global-silhouette-averages.png"))
end

function time_log(msg)
    open(string(pwd(), "/output/time_log.txt"), "a") do io
        write(io, string(now(), ": $msg\n"))
    end
end

"Generate the outputs given the silhouette means and the silhouettes"
function generate_output(name, silhouettes, silhouette_means, min_clusters, max_clusters) 
    generate_top10_global_scores(silhouette_means, silhouettes)
    generate_silhouette_score_histogram(name, silhouette_means, min_clusters, max_clusters)
end

function find_optimal_clusters(P, min_clusters::Int, max_clusters::Int)   
    silhouettes = Dict()      # Key: silhouette ID, Value: silhouette data
    silhouette_means = Dict()  # Key: silhouette ID, Value: silhouette mean

    Threads.@threads for i in min_clusters:max_clusters
        time_log("Beginning calculations for $i clusters")
        println("Calculating for $i clusters...")
        silhouette_data = calc_silhouette_scores(P, i)

        silhouettes[i] = silhouette_data
        silhouette_means[i] = silhouette_data.total_average
    end

    return silhouettes, silhouette_means
end

function main()
    #define cosmological model. For this example I will use the Planck 2015 
    #cosmological parameters but this can be easily modified. 

    data = CSV.read(string(pwd(), "/data/GAMA_CZ5Unj.csv"), DataFrame)

    println("Calculating radial distance...")
    add_dist!(cosmology(h=0.7, OmegaM=0.3, OmegaR=0), data)
    println("Adding coordinates...")
    add_xyz!(data)

    println("Calculating data groups...")
    G02 = data[((data[!, "RA"].<38.8) .& (data[!, "RA"].>30.2) .& (data[!, "DEC"].<-3.72) .& (data[!, "DEC"].>-10.25)),:]
    G09 = data[((data[!, "RA"].<141.0) .& (data[!, "RA"].>129.0) .& (data[!, "DEC"].<3.0) .& (data[!, "DEC"].>-2.0)),:]
    G12 = data[((data[!, "RA"].<186.0) .& (data[!, "RA"].>174.0) .& (data[!, "DEC"].<2.0) .& (data[!, "DEC"].>-3.0)),:]
    G15 = data[((data[!, "RA"].<223.5) .& (data[!, "RA"].>211.5) .& (data[!, "DEC"].<3.0) .& (data[!, "DEC"].>-2.0)),:]
    G23 = data[((data[!, "RA"].<351.9) .& (data[!, "RA"].>338.1) .& (data[!, "DEC"].<-30.0) .& (data[!, "DEC"].> -35.0)),:]

    println(string("Logging start time: ", now()))
    time_log("Program begins")

    println("Finding the optimal # of clusters...")
    
    name = "G02"
    min_clusters = 20
    max_clusters = 100

    silhouettes, silhouette_means = find_optimal_clusters(
        load_dist_matrix(string(pwd(), "/data/G02-distance-matrix.jld")), 
        min_clusters, max_clusters
    )

    println("Generating output")
    generate_output(name, silhouettes, silhouette_means, min_clusters, max_clusters)
    
    println(string("Logging end time: ", now()))
    time_log("Program ends")
    println("\nProgram complete.")
end


main()


# println(now())

# min_clusters = 10
# max_clusters = 12

# avg_scores = [0.567, 0.63287, 0.89723]
# p = Plots.plot(min_clusters:max_clusters, avg_scores, xlabel="Number of clusters (k)", ylabel="Silhouette score", legend=false)
# Plots.savefig(p, string(pwd(), "/output/test-cluster-averages.png"))


# n_clusters = 5
# name = "test"
# output_file_path = string(pwd(), "/output/", name, "-", n_clusters, ".html")

# data = DataFrame(X=1:5, Y=26:30, Z=[1, 5, 20, 50, 600], assignments=1:5)

# p = plot(
#     data,
#     x=:X,
#     y=:Y, 
#     z=:Z,
#     color=:assignments,
#     type="scatter3d", 
#     mode="markers",
#     Layout(
#         title=string("Galaxies Plotted in 3D Space (", n_clusters, " clusters): ", name), 
#         scene = attr(
#             aspectmode="manual",
#             aspectratio=attr(x=1, y=1, z=1),
#             xaxis_title="x: Distance (Mpc)",
#             yaxis_title="y: Distance (Mpc)",
#             zaxis_title="z: Distance (Mpc)",
#         ),
#         font=attr(
#             family="Courier New",
#             size=18
#         ),
#         # xaxis=attr(scaleanchor="y"),
#         # yaxis=attr(scaleanchor="z"),
#         # zaxis=attr(scaleanchor="x")
#     )
# )

# open(output_file_path, "w") do io
#     PlotlyBase.to_html(io, p.plot)
# end