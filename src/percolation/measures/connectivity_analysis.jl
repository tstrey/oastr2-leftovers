#TO DO: in use but must be updated to recieve MST inputs.

using LightGraphs

n_nodes = 100


n_sims = 100

p_min = 0.01
p_max = 0.5
p_step = 0.01
p_range = p_min:p_step:p_max

function random_network(p)
    g = erdos_renyi(n_nodes, p)
    return g
end

function largest_component_size(g)
    components = connected_components(g)
    component_sizes = map(length, components)
    return maximum(component_sizes)
end

for p in p_range
    n_components = zeros(Int, n_sims)
    for i in 1:n_sims
        g = random_network(p)
        n_components[i] = largest_component_size(g)
    end
    avg_component_size = mean(n_components)
    println("$p $avg_component_size")
end


