cd(@__DIR__)
using Pkg
Pkg.activate("..")
Pkg.instantiate()

using KomaMRI, MAT

# Expect phantom name as first argument (e.g., "pelvis2D", "brain2D", "brain3D")
if length(ARGS) < 1
	println("Usage: julia backend/phantom_to_mat.jl <phantom_name>")
	println("  phantom_name options: pelvis2D, brain2D, brain3D")
	exit(1)
end

# Normalize phantom name (strip extension if provided)
phantom_name = ARGS[1]

# Select the phantom object
cd(phantom_name)

obj = read_phantom(phantom_name*".phantom") |> f64

outpath = phantom_name*".mat"
file = matopen(outpath, "w")
write(file, "x", obj.x)
write(file, "y", obj.y)
write(file, "z", obj.z)
write(file, "PD", obj.ρ)
write(file, "T1", obj.T1)
write(file, "T2", obj.T2)
write(file, "dw", obj.Δw)
close(file)

println("Wrote MAT to: ", outpath)