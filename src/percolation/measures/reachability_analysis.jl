#TO DO: in use but must be updated to recieve MST inputs.

using LightGraphs
using Random
using StatsBase

# Define the number of nodes in the network
n_nodes = 1000

# Define the number of simulations
n_sims = 100

p_min = 0.01
p_max = 0.5
p_step = 0.01
p_range = p_min:p_step:p_max


function random_network(p)
    g = DiGraph(n_nodes)
    for i in 1:n_nodes, j in i+1:n_nodes
        if rand() < p
            add_edge!(g, i, j)
        end
    end
    return g
end

function largest_strongly_connected_component_size(g)
    components = kosaraju_strongly_connected_components(g)
    component_sizes = map(length, components)
    return maximum(component_sizes)
end

for p in p_range
    n_components = zeros(Int, n_sims)
    for i in 1:n_sims
        g = random_network(p)
        n_components[i] = largest_strongly_connected_component_size(g)
    end
    avg_component_size = mean(n_components)
    std_component_size = std(n_components)
    println("$p $avg_component_size $std_component_size")
end
