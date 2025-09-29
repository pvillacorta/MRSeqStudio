"Convert a 1D vector with system paramaters into a KomaMRICore.Scanner object"
vec_to_scanner(vec) = begin
   sys = Scanner()
   sys.B0 =        vec[1]       # Main magnetic field [T]
   sys.B1 =        vec[2]       # Max RF amplitude [T]
   sys.ADC_Δt =    vec[3]       # ADC sampling time
   sys.Gmax =      vec[4]       # Max Gradient [T/m]
   sys.Smax =      vec[5]       # Max Slew-Rate

   sys
end

"Convert a 2D matrix containing sequence information into a KomaMRICore.Sequence object"
mat_to_seq(mat,sys::Scanner) = begin
   seq = Sequence()

   for i=1:size(mat)[2]

      if mat[1,i] == 1 # Excitation
         B1 = mat[6,i] + mat[7,i]im;
         duration = mat[2,i]
         Δf = mat[8,i];
         EX = PulseDesigner.RF_hard(B1, duration, sys; G = [mat[3,i] mat[4,i] mat[5,i]], Δf)
         seq += EX

         G = EX.GR.A; G = [G[1];G[2];G[3]];
         REF = [0;0;1];

         # We need to create a rotation matrix which transfomrs vector [0 0 1] into vector G
         # To do this, we can use axis-angle representation, and then calculate rotation matrix with that
         # https://en.wikipedia.org/wiki/Rotation_matrix#Conversion_from_rotation_matrix_to_axis%E2%80%93angle

         # Cross product:
         global cross_prod = LinearAlgebra.cross(REF,G);
         # Rotation axis (n = axb) Normalized cross product:
         n = normalize(cross_prod);
         # Rotation angle:
         θ = asin(norm(cross_prod)/((norm(REF))*(norm(G))));
         # Rotation matrix:
         global R = [cos(θ)+n[1]^2*(1-cos(θ))            n[1]*n[2]*(1-cos(θ))-n[3]*sin(θ)     n[1]*n[3]*(1-cos(θ))+n[2]*sin(θ);
                     n[2]*n[1]*(1-cos(θ))+n[3]*sin(θ)    cos(θ)+n[2]^2*(1-cos(θ))             n[2]*n[3]*(1-cos(θ))-n[1]*sin(θ);
                     n[3]*n[1]*(1-cos(θ))-n[2]*sin(θ)    n[3]*n[2]*(1-cos(θ))+n[1]*sin(θ)     cos(θ)+n[3]^2*(1-cos(θ))        ];


      elseif mat[1,i] == 2 # Delay
         DELAY = Delay(mat[2,i])
         seq += DELAY


      elseif ((mat[1,i] == 3) || (mat[1,i] == 4)) # Dephase or Readout
         AUX = Sequence()

         ζ = abs(sum([mat[3,i],mat[4,i],mat[5,i]])) / sys.Smax
         ϵ1 = mat[2,i]/(mat[2,i]+ζ)

         AUX.GR[1] = Grad(mat[3,i],mat[2,i],ζ)
         AUX.GR[2] = ϵ1*Grad(mat[4,i],mat[2,i],ζ)
         AUX.GR[3] = Grad(mat[5,i],mat[2,i],ζ)

         AUX.DUR = convert(Vector{Float64}, AUX.DUR)
         AUX.DUR[1] = mat[2,i] + 2*ζ

         AUX.ADC[1].N = (mat[1,i] == 3) ? 0 : trunc(Int,mat[10,i])     # No samples during Dephase interval
         AUX.ADC[1].T = mat[2,i]                                       # The duration must be explicitly stated
         AUX.ADC[1].delay = ζ

         AUX = (norm(cross_prod)>0) ? R*AUX : AUX

         if(mat[1,i]==4)
            global N_x = trunc(Int,mat[10,i])
         end

         seq += AUX


      elseif mat[1,i] == 5 # EPI
         FOV = mat[9,i]
         N = trunc(Int,mat[10,i])

         EPI = PulseDesigner.EPI(FOV, N, sys)
         EPI = (norm(cross_prod)>0) ? R*EPI : EPI
         seq += EPI

         N_x = N
      end

   end

   seq.DEF = Dict("Nx"=>N_x,"Ny"=>N_x,"Nz"=>1)

   seq
end

"Convert a json string containing sequence information into a KomaMRIBase.Sequence object"
json_to_sequence(json_seq::JSON3.Object, sys::Scanner) = begin
   vars = read_variables(json_seq["variables"])

   global seq = Sequence()
   global R = float([1 0 0; 0 1 0; 0 0 1])

   N_x = 0

   blocks = json_seq["blocks"]
   iterators = read_iterators(blocks)

   function get_gradients(block::JSON3.Object)
      gradients = block["gradients"]
      GR = reshape([Grad(0,0) for i in 1:3],(3,1))
      for grad in gradients
         axis        = grad["axis"]
         delay       = eval_string(grad["delay"], vars, iterators)
         rise        = eval_string(grad["rise"], vars, iterators)
         flatTopTime = eval_string(grad["flatTop"], vars, iterators)
         amplitude   = eval_string(grad["amplitude"], vars, iterators)

         idx = axis == "x" ? 1 :
               axis == "y" ? 2 :
               axis == "z" ? 3 : 
               -1

         if amplitude > sys.Gmax
            error("G=$(amplitude) mT/m exceeds Gmax=$(sys.Gmax) mT/m")
         elseif amplitude/rise > sys.Smax
            error("Slew rate=$(amplitude/rise) mT/m/ms exceeds Smax=$(sys.Smax) mT/m/ms")
         end

         GR[idx] = Grad(amplitude, flatTopTime, rise, delay)
      end
      return GR
   end

   function isChild(index::Int)
      for i in eachindex(blocks)
         children = blocks[i]["children"]
         for j in eachindex(children)
            if children[j].number == (index - 1)
               return true
            end
         end
      end
      return false
   end

   function addToSeq(block::JSON3.Object) 
      if block["cod"] == 0          # <------------- Group
         iterator    =  block["iterator"]
         repetitions =  eval_string(block["repetitions"], vars, iterators)
         children =     block["children"]
         for i in 0:(repetitions-1)
            for j in eachindex(children)
               addToSeq(blocks[children[j].number+1])
            end
            iterators[iterator] += 1
         end

      elseif block["cod"] == 1       # <-------------------------- Excitation
         rf     = block["rf"][1]
         shape  = rf["shape"]
         deltaf = eval_string(rf["deltaf"], vars, iterators)

         # Flip angle and duration
         if haskey(block, "duration") & haskey(rf, "flipAngle")
            duration = eval_string(block["duration"], vars, iterators)
            flipAngle = eval_string(rf["flipAngle"], vars, iterators)

            aux_amplitude = 1e-6
            # 1. Rectangle (hard)
            if shape == 0
               AUX = PulseDesigner.RF_hard(aux_amplitude, duration, sys)
            # 2. Sinc
            elseif shape == 1
               AUX = PulseDesigner.RF_sinc(aux_amplitude, duration, sys)
            end

            amplitude = aux_amplitude * (flipAngle/get_flip_angles(AUX)[1])

         # Amplitude and duration
         elseif haskey(block, "duration") & haskey(rf, "b1Module")
            duration = eval_string(block["duration"], vars, iterators)  
            amplitude = eval_string(rf["b1Module"], vars, iterators)
        
         # Flip angle and amplitude
         elseif haskey(rf, "flipAngle") & haskey(rf, "b1Module")
            flipAngle = eval_string(rf["flipAngle"], vars, iterators)
            amplitude = eval_string(rf["b1Module"], vars, iterators)

            aux_duration = 1e-3
            # 1. Rectangle (hard)
            if shape == 0
               AUX = PulseDesigner.RF_hard(amplitude, aux_duration, sys)
            # 2. Sinc
            elseif shape == 1
               AUX = PulseDesigner.RF_sinc(amplitude, aux_duration, sys)
            end

            duration = aux_duration * (flipAngle/get_flip_angles(AUX)[1])
         end

         # 1. Rectangle (hard)
         if shape == 0
            EX = PulseDesigner.RF_hard(amplitude, duration, sys; Δf=deltaf)
         # 2. Sinc
         elseif shape == 1
            EX = PulseDesigner.RF_sinc(amplitude, duration, sys; Δf=deltaf)[1]
         end

         EX.GR = get_gradients(block)

         REF = [0, 0, 1]
         G = vec(EX.GR.A)
         cross_prod = LinearAlgebra.cross(REF, G)
         n = normalize(cross_prod)
         θ = asin(norm(cross_prod)/(norm(REF)*norm(G)))
         R = norm(cross_prod) > 0 ? Un(θ, n) : R

         EX.RF[1].delay = maximum(EX.GR.rise)
         EX.DUR[1] = EX.RF[1].delay + max(maximum(EX.GR.T .+ EX.GR.fall), duration)
         seq += EX

      elseif block["cod"] == 2       # <-------------------------- Delay
         duration = eval_string(block["duration"], vars, iterators)
         DELAY = Delay(duration)
         seq += DELAY

      elseif block["cod"] in [3,4]   # <-------------------------- Dephase or Readout
         DEPHASE = Sequence(get_gradients(block))

         if block["cod"] == 4
            DEPHASE.ADC[1].N = eval_string(block["samples"], vars, iterators)
            DEPHASE.ADC[1].T = eval_string(block["duration"], vars, iterators)
            DEPHASE.ADC[1].delay = eval_string(block["adcDelay"], vars, iterators)
            DEPHASE.ADC[1].ϕ = eval_string(block["adcPhase"], vars, iterators)

            N_x = eval_string(block["samples"], vars, iterators)
         end

         seq += DEPHASE

      elseif block["cod"] == 5       # <-------------------------- EPI
         fov = eval_string(block["fov"], vars, iterators)
         lines = eval_string(block["lines"], vars, iterators)
         samples = eval_string(block["samples"], vars, iterators)

         N_x = eval_string(block["samples"], vars, iterators)

         seq += R * EPI(fov, lines, sys)

      elseif block["cod"] == 6       # <-------------------------- GRE  
         fov = eval_string(block["fov"], vars, iterators)
         lines = eval_string(block["lines"], vars, iterators)
         samples = eval_string(block["samples"], vars, iterators)

         t  = block["t"][1]
         te = eval_string(t["te"], vars, iterators)
         tr = eval_string(t["tr"], vars, iterators)

         rf    = block["rf"][1]
         α     = eval_string(rf["flipAngle"], vars, iterators)
         Δf    = eval_string(rf["deltaf"], vars, iterators)

         seq += R * GRE(fov, lines, te, tr, α, sys; Δf=Δf)
      end 
   end

   for i in eachindex(blocks)
      if !isChild(i)
         addToSeq(blocks[i])
      end
   end

   seq.DEF = Dict("Nx"=>N_x,"Ny"=>N_x,"Nz"=>1)

   display(seq)
   return seq, R
end

"Convert a json string containing scanner information into a KomaMRIBase.Scanner object"
json_to_scanner(json_scanner::JSON3.Object) = begin
   vars = read_variables(json_scanner["variables"])
   parameters = json_scanner["parameters"]

   sys = Scanner(
      B0 = eval_string(parameters["b0"], vars),
      B1 = eval_string(parameters["b1"], vars),
      Gmax = eval_string(parameters["gmax"], vars),
      Smax = eval_string(parameters["smax"], vars),
      ADC_Δt = eval_string(parameters["deltat"], vars),
   )
   
   return sys
end
"Obtain raw RM signal. Input arguments are a 2D matrix (sequence) and a 1D vector (system parameters)"
sim(obj, seq, sys, path, gpu_active; sim_params=Dict{String,Any}()) = begin
   try
      if gpu_active
         sim_params["gpu"] = true
      else
         sim_params["gpu"] = false
      end
      return simulate(obj, seq, sys; sim_params=sim_params, w=path)
   catch e
      println("Simulation failed")
      display(e)
      update_progress!(path, -2)
      return e
   end
end



"Obtain the reconstructed image from raw_signal (obtained from simulation)"
recon(raw_signal, seq, rot_matrix, path) = begin
   try
      seq_no_rot = inv(rot_matrix) * seq
      _, ktraj = get_kspace(seq_no_rot)

      recParams = Dict{Symbol,Any}(:reco=>"direct")
      Nx = seq.DEF["Nx"]
      Ny = seq.DEF["Ny"]

      recParams[:reconSize] = (Nx, Ny)
      recParams[:densityWeighting] = false

      acqData = AcquisitionData(raw_signal)
      acqData.traj[1].circular = false #Removing circular window
      acqData.traj[1].nodes = transpose(ktraj[:, 1:2]) #<----------------CAMBIO
      acqData.traj[1].nodes = acqData.traj[1].nodes[1:2,:] ./ maximum(2*abs.(acqData.traj[1].nodes[:])) #Normalize k-space to -.5 to .5 for NUFFT

      Nx, Ny = raw_signal.params["reconSize"][1:2]
      recParams[:reconSize] = (Nx, Ny)
      recParams[:densityWeighting] = true

      aux = @timed reconstruction(acqData, recParams)
      image  = reshape(aux.value.data,Nx,Ny,:)
      kspace = KomaMRI.fftc(reshape(aux.value.data,Nx,Ny,:))
      update_progress!(path, 101)
      return image, kspace
   catch e
      println("Reconstruction failed")
      display(e)
      update_progress!(path, -2)
      return e
   end
end




function read_variables(json_variables::JSON3.Array)
   variables = Dict{String,Any}()
   for variable in json_variables
      variables[variable["name"]] = variable["value"]
   end
   return variables
end

function read_iterators(json_blocks::JSON3.Array)
   iterators = Dict{String,Int}()
   for block in json_blocks
      if block["cod"] == 0 # Group
         iterators[block["iterator"]] = 0 # Initialize iterator
      end
   end
   return iterators
end

# TODO; Check security problems with this function.
"Eval a string expression and return the result"
function eval_string(expr::String, variables::Dict, iterators::Dict{String,Int}=Dict{String,Int}())
   if expr == ""
       return 0
   end

   allowed_operators = Set(["+", "-", "*", "/", "(", ")", "^"])
   number_pattern = r"^\d+\.?\d*(?:[eE][+-]?\d+)?$"
   identifier_pattern = r"^[a-zA-Z_][a-zA-Z0-9_]*$"

   tokens = eachmatch(r"[a-zA-Z_][a-zA-Z0-9_]*|\d+\.?\d*(?:[eE][+-]?\d+)?|[()+\-*/^]", expr)

   all_vars = merge(variables, iterators, Dict("pi" => pi))

   rebuilt = String[]
   for token in tokens
      val = token.match
      if val in allowed_operators || occursin(number_pattern, val)
         push!(rebuilt, val)
      elseif occursin(identifier_pattern, val) && haskey(all_vars, val)
         push!(rebuilt, string(all_vars[val]))
      else
         error("Symbol not recognized: '$val'")
      end
   end

   safe_expr = join(rebuilt, " ")
   try
      result = eval(Meta.parse(safe_expr))
      return result
   catch err
      error("Error evaluating expression: $(err)")
   end
end
