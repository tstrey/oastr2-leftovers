#TO DO: in use but must be updated to recieve MST inputs. Only for complete_graph.

using Pkg
Pkg.add(["CSV", "DataFrames", "Cosmology", "Unitful"])
using CSV, DataFrames, Cosmology, Unitful




function write_distances(distance_data, filestream)
   for row in distance_data
       write(filestream, string(Int(row[1]), ",", Int(row[2]), ",", row[3], "\n"))
   end
end


"Calculate the distance from one point and every other point. Will write the output to filename"
function calculate_distances(data, filename, startindex, endindex)
   println("Start function with filename $filename startindex $startindex endindex $endindex")
   distances = []


   filestream = open(filename, "a")
   write(filestream, "src,dst,density\n")  # set up csv header


   for i in range(startindex, endindex)
       for j in range(i + 1, size(data)[1] - 1)
           # Find the separation in the sky
           # RA and Dec are in degrees
           deltaRA = abs(data[i, "RA"] - data[j, "RA"])
           deltaDec = abs(data[i, "DEC"] - data[j, "DEC"])
           skySep = sqrt(deltaRA^2 + deltaDec^2)
           sep_transverse = 2 * sin(deg2rad(skySep / 2)) * ((data[i, "dist"] + data[j, "dist"]) / 2)
          
           # Find density
           sep_3d = sqrt(sep_transverse^2 + (abs(data[i, "dist"] - abs(data[j, "dist"]))^2))
           density = (j - i + 1) / (4/3 * pi * sep_3d^3)


           push!(distances, [i, j, density])
       end


       write_distances(distances, filestream)
       distances = []
   end


   write_distances(distances, filestream)
   println(string("Done with range ", startindex, " to ", endindex))
   close(filestream)
end




"Add dist values to the dataset"
function add_dist!(data)
   c = cosmology(h=0.7, OmegaM=0.3, OmegaR=0)


   data.dist = comoving_radial_dist.(Ref(c), data.Z_HELIO)
end




"Does the same thing as the function calculate_distnaces however it is multithreaded and writes to multiple different output files"
function calculate_distances_multithreaded(data)
   startindex = 1
   jump = size(data)[1] / (Threads.nthreads() + 1)
   endindex = jump


   for i in 1:Threads.nthreads()
       println("Spawning thread with startindex $startindex and endindex $endindex, i = $i")
       @Threads.spawn calculate_distances(data, string("output", i, ".csv"), Int(ceil(startindex)), Int(ceil(endindex)))


       sleep(0.1)


       startindex += jump
       endindex += jump
   end
end




function main()
   println("Loading data")
   data = CSV.read("GAMA_CZ5Unj.csv", DataFrame)


   println("Calculating radial distance")
   add_dist!(data)


   println("Calculating data groups")
   G02 = data[((data[!, "RA"] .< 38.8) .& (data[!, "RA"].>30.2) .& (data[!, "DEC"].<-3.72) .& (data[!, "DEC"].>-10.25)),:]
   G09 = data[((data[!, "RA"].<141.0) .& (data[!, "RA"].>129.0) .& (data[!, "DEC"].<3.0) .& (data[!, "DEC"].>-2.0)),:]
   G12 = data[((data[!, "RA"].<186.0) .& (data[!, "RA"].>174.0) .& (data[!, "DEC"].<2.0) .& (data[!, "DEC"].>-3.0)),:]
   G15 = data[((data[!, "RA"].<223.5) .& (data[!, "RA"].>211.5) .& (data[!, "DEC"].<3.0) .& (data[!, "DEC"].>-2.0)),:]
   G23 = data[((data[!, "RA"].<351.9) .& (data[!, "RA"].>338.1) .& (data[!, "DEC"].<-30.0) .& (data[!, "DEC"].> -35.0)),:]


   println("Calculating distance matrix")
   calculate_distances_multithreaded(G15)
  
   println("Done")
end




main()
