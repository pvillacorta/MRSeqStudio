using Distributed

if nprocs() == 1
   addprocs(5)
end

@everywhere begin
   cd(@__DIR__)
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
end

using Oxygen
using HTTP
using TOML
using MySQL
using DBInterface
using SwaggerMarkdown
using SHA
using JWTs, MbedTLS
using Serialization

using StatsBase, FFTW
using StructTypes

@everywhere begin
   using KomaMRI
   using LinearAlgebra
   using JSON3
   using Dates
   using CUDA
end

dynamic_files_path = string(@__DIR__, "/../frontend/dist")
public_files_path  = string(@__DIR__, "/../public")

dynamicfiles(dynamic_files_path, "/") 
staticfiles(public_files_path, "/public")

const PUBLIC_URLS = ["/login", "/login.js", "/login.js.map", 
                     "/register", "/", "/admin"]
const PRIVATE_URLS = ["/simulate", "/plot", "/plot_sequence", "/plot_phantom"]

global simID = 1
global SIM_PROGRESSES  = Dict{Int, Int}()
global RECON_PROGRESSES = Dict{Int, Int}()
global STATUS_FILES    = Dict{Int, String}()

# Additional state to support new plotting features
global RAW_RESULTS      = Dict{String, Any}()
global RECON_RESULTS    = Dict{String, Any}()
global PHANTOMS         = Dict{String, Phantom}()   
global SEQUENCES        = Dict{String, Sequence}()   
global SCANNERS         = Dict{String, Scanner}()
global ROT_MATRICES     = Dict{String, Matrix}() 

global SIM_RESULTS     = Dict{Int, Any}()
global SIM_METADATA    = Dict{Int, Any}()
global ACTIVE_SESSIONS  = Dict{String, Int}()
# ---------------------------- GLOBAL VARIABLES --------------------------------
# Estas no harán falta una vez esté la tabla simulación-proceso implementada

# global statusFile = ""
# global simProgress = -1
# global result = nothing

# ------------------------------ FUNCTIONS ------------------------------------

@everywhere begin
   ##No cambiar los includes de orden
   include("db_core.jl")
   include("auth_core.jl")
   include("users_core.jl")
   include("sequences_core.jl")
   include("api_utils.jl")
   include("mri_utils.jl")
   include("admin_db.jl")
   
   """Updates simulation progress and writes it in a file."""
   function KomaMRICore.update_blink_window_progress!(w::String, block, Nblocks)
      io = open(w,"w") # "w" mode overwrites last status value, even if it was not read yet
      progress = trunc(Int, block / Nblocks * 100)
      write(io,progress)
      close(io)
      return nothing
   end

   function update_progress!(w::String, progress::Int)
      io = open(w,"w")
      write(io,progress)
      close(io)
   end
end

# Función auxiliar para normalizar claves de diccionarios y objetos JSON3
function normalize_keys(obj)
    # Convertir JSON3.Object a Dict si es necesario
    if obj isa JSON3.Object
        dict = Dict(pairs(obj))
    else
        dict = obj
    end
    
    # Verificar que sea un diccionario
    if !(dict isa Dict)
        return obj  # Si no es Dict ni JSON3.Object, devolver sin cambios
    end
    
    # Convertir símbolos a strings (siempre)
    return Dict(String(k) => (v isa Dict || v isa JSON3.Object ? normalize_keys(v) : v) 
               for (k, v) in pairs(dict))
end

## AUTHENTICATION
function AuthMiddleware(handler)
   return function(req::HTTP.Request)
      println("Auth middleware")

      path = String(req.target)

      jwt1 = get_jwt_from_cookie(HTTP.header(req, "Cookie"))
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))

      ipaddr = string(HTTP.header(req, "X-Forwarded-For", "127.0.0.1"))

      # Caso especial para /admin - siempre permitir acceso directo al endpoint
      if path == "/admin"
         return handler(req)  # Permite que el endpoint /admin maneje su propia autenticación
      
      elseif (path in PUBLIC_URLS) 
      # Public resource. This does not requires cookie
         return check_jwt(jwt1, ipaddr, 1) ? HTTP.Response(303, ["Location" => "/"]) : handler(req)

      elseif any(base -> startswith(path, base), PRIVATE_URLS) 
      # Private resource. This requires both the cookie and the Authorization header
         return (check_jwt(jwt1, ipaddr, 1) && check_jwt(jwt2, ipaddr, 2)) ? handler(req) : HTTP.Response(303, ["Location" => "/login"])

      else 
      # Private dashboard. This only requires the cookie
         return check_jwt(jwt1, ipaddr, 1) ? handler(req) : HTTP.Response(303, ["Location" => "/login"])
      end
   end
end

# ---------------------------- API METHODS ---------------------------------
@get "/login" function(req::HTTP.Request) 
   return render_html(dynamic_files_path * "/login.html")
end

@post "/login" function(req::HTTP.Request) 
   input_data = normalize_keys(json(req))
   ipaddr     = string(HTTP.header(req, "X-Forwarded-For", "127.0.0.1"))
   return authenticate(input_data["username"], input_data["password"], ipaddr)
end

@get "/register" function(req::HTTP.Request) 
   return render_html(dynamic_files_path * "/register.html")
end

@post "/register" function(req::HTTP.Request) 
   input_data = normalize_keys(json(req))
   return create_user(input_data["username"], input_data["password"], input_data["email"])
end

@get "/logout" function(req::HTTP.Request) 
   jwt1 = get_jwt_from_cookie(HTTP.header(req, "Cookie"))
   username = claims(jwt1)["username"]
   delete!(ACTIVE_SESSIONS, username)

   expires = now()
   expires_str = Dates.format(expires, dateformat"e, dd u yyyy HH:MM:SS") * " GMT"
   delete!(ACTIVE_SESSIONS, username)
   return HTTP.Response(200, ["Set-Cookie" => "token=null; SameSite=Lax; Expires=$(expires_str)"])
end

@swagger """
/:
   get:
      tags:
      - web
      summary: Redirect to the app
      description: Redirect to the app
      responses:
         '301':
            description: Redirect to /app
            headers:
              Location:
                description: URL with the app
                schema:
                  type: string
                  format: uri
         default:
            description: Always returns a 301 redirect to /app
            headers:
              Location:
                schema:
                  type: string
                  example: "/app"
"""
@get "/" function(req::HTTP.Request)
   return HTTP.Response(301, ["Location" => "/app"])
end

@swagger """
/app:
   get:
      tags:
      - web
      summary: Get the app and the web content
      description: Get the app and the web content
      responses:
         '200':
            description: App and web content
            content:
              text/html:
                schema:
                  format: html
         '404':
            description: Not found
         '500':
            description: Internal server error
"""
@get "/app" function(req::HTTP.Request)
   return render_html(dynamic_files_path * "/index.html")
end

## SIMULATION
@swagger """
/simulate:
   post:
      tags:
      - simulation
      summary: Add a new simulation request
      description: Add a new simulation request
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     phantom:
                        type: string
                     sequence:
                        type: object
                     scanner:
                        type: object
               example:
                  phantom: "Brain 2D"
                  sequence: {
                     "blocks": [
                        {
                              "children": [],
                              "cod": 1,
                              "duration": 1e-3,
                              "gradients": [
                                 {
                                    "amplitude": 1e-3,
                                    "axis": "x",
                                    "delay": 0,
                                    "flatTop": 1e-3,
                                    "rise": 5e-4
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "y",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "z",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 }
                              ],
                              "name": "",
                              "ngroups": 0,
                              "rf": [
                                 {
                                    "deltaf": 0,
                                    "flipAngle": 10,
                                    "shape": 0
                                 }
                              ]
                        },
                        {
                           "adcDelay": 0,
                           "children": [],
                           "cod": 4,
                           "duration": 1e-3,
                           "gradients": [
                              {
                                 "amplitude": 1e-3,
                                 "axis": "x",
                                 "delay": 0,
                                 "flatTop": 1e-3,
                                 "rise": 5e-4
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "y",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "z",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              }
                           ],
                           "name": "",
                           "ngroups": 0,
                           "samples": 64
                        }
                     ],
                     "description": "Simple RF pulse and ADC sequence",
                  }
                  scanner: {
                     "parameters": {
                        "b0": 1.5,
                        "b1": 10e-6,
                        "deltat": 2e-6,
                        "gmax": 60e-3,
                        "smax": 500
                     },
                  }
      responses:
         '202':
            description: Accepted operation
            headers:
              Location:
                description: URL with the simulation ID, to check the status of the simulation
                schema:
                  type: string
                  format: uri
         '400':
            description: Invalid input
         '500':
            description: Internal server error
"""
@post "/simulate" function(req::HTTP.Request)
    println("[Simulate/")
   # Obtener información del usuario
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   
   # Verificar si el usuario puede ejecutar más secuencias hoy
   if !user_can_run_more_sequences(uname)
      println("⛔ ACCESO DENEGADO: Se ha rechazado la solicitud de simulación de '$uname' por exceder límite diario")
      return HTTP.Response(403, ["Content-Type" => "application/json"],
         JSON3.write(Dict("error" => "Has alcanzado tu límite diario de secuencias")))
   end
   pid = ACTIVE_SESSIONS[uname]
   # Configurar archivo de estado temporal
   STATUS_FILES[simID] = tempname()
   touch(STATUS_FILES[simID])

   scanner_json   = json(req)["scanner"]
   sequence_json  = json(req)["sequence"]
   SCANNERS[uname]                       = json_to_scanner(scanner_json)
   SEQUENCES[uname], ROT_MATRICES[uname] = json_to_sequence(sequence_json, SCANNERS[uname])
   
   ########### movidas de secuencias y gestion de users
   # Generar un ID único para la secuencia
   sequence_unique_id = "seq_$(now())_$(rand(1:10000))"
   
   # Guardar metadatos de la simulación
   SIM_METADATA[simID] = Dict(
      "uname" => uname,
      "sequence_id" => sequence_unique_id,
      "start_time" => now()
   )

   # Registrar el uso de secuencia
   register_sequence_usage(uname)
   save_sequence(uname, sequence_unique_id, SEQUENCES[uname])
   #Comprobamos los privilegios para el uso de gpu
   user_privs = get_user_privileges(uname)
   gpu_active = false
   if user_privs === nothing
      println("[!!!] No se pudo obtener los privilegios para $uname")
   else
      gpu_active = user_privs["gpu_access"]
   end
   ################ fin de movidas


   if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
      assign_process(uname) # We assign a new julia process to the user
   end
   # Simulation  (asynchronous. It should not block the HTTP 202 Response)
   RAW_RESULTS[uname]                    = @spawnat pid sim(PHANTOMS[uname], SEQUENCES[uname], SCANNERS[uname], STATUS_FILES[simID], gpu_active)

   # while 1==1
   #    io = open(statusFile,"r")
   #    if (!eof(io))
   #       global simProgress = read(io,Int32)
   #       print("leido\n")
   #    end
   #    close(io)
   #    print("Progreso: ", simProgress, '\n')
   #    sleep(0.2)
   # end

   # TODO: Update simulation-process correspondence table

   headers = ["Location" => string("/simulate/",simID)]
   global simID += 1
   # 202: Partial Content
   return HTTP.Response(202,headers)
end

@swagger """
/simulate/{simID}:
   get:
      tags:
      - simulation
      summary: Get the result of a simulation
      description: Get the result of a simulation. If the simulation has finished, it returns its result. If not, it returns 303 with location = /simulate/{simID}/status
      parameters:
         - in: path
           name: simID
           required: true
           description: The ID of the simulation
           schema:
              type: integer
              example: 1
         - in: query
           name: width
           description: Width of the image
           schema:
              type: integer
              example: 800
         - in: query 
           name: height
           description: Height of the image
           schema:
              type: integer
              example: 600
      responses:
         '200':
            description: Simulation result
            content:
              text/html:
                schema:
                  format: html
         '303':
            description: Simulation not finished yet
            headers:
              Location:
                description: URL with the simulation status
                schema:
                  type: string
                  format: uri
         '404':
            description: Simulation not found
         '500':
            description: Internal server error
"""
@get "/simulate/{simID}" function(req::HTTP.Request, simID, width::Int, height::Int)
    println("[Simulate/simID]")
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   _simID = parse(Int, simID)
   io = open(STATUS_FILES[_simID],"r")
   SIM_PROGRESSES[_simID] = -1 # Initialize simulation progress
   if (!eof(io))
      SIM_PROGRESSES[_simID] = read(io,Int32)
   end
   close(io)
   if -2 < SIM_PROGRESSES[_simID] < 100      # Simulation not started or in progress
      headers = ["Location" => string("/simulate/",_simID,"/status")]
      return HTTP.Response(303,headers)
   elseif SIM_PROGRESSES[_simID] == 100  # Simulation finished
      width  = width  - 15
      height = height - 20
      sig = fetch(RAW_RESULTS[uname])  
      p = plot_signal(sig; darkmode=true, width=width, height=height, slider=height>275)
      html_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(html_buffer, p.plot)

      ################ MOVIDAS DE GESTION ###############
      # Solo guardamos el resultado si no se ha guardado anteriormente
      if haskey(SIM_METADATA, _simID) && !haskey(SIM_METADATA[_simID], "saved")
         metadata = SIM_METADATA[_simID]
         sequence_id = metadata["sequence_id"]

         
         
         # Intentar guardar el resultado (verifica internamente los límites de espacio)
         save_result = save_simulation_result(uname, sequence_id, sig)
         
         # Marcar como guardado para evitar intentos repetidos
         SIM_METADATA[_simID]["saved"] = save_result
         if !save_result
            println("⚠️ No se pudo guardar el resultado por exceder cuota de almacenamiento")
         end
      end
      ###################### MOVIDAS DE GESTION ##################
      return HTTP.Response(200,body=take!(html_buffer))
   elseif SIM_PROGRESSES[_simID] == -2 # Simulation failed
      error_msg = fetch(SIM_RESULTS[_simID])
      return HTTP.Response(500,body=JSON3.write(error_msg))
   end
end

@swagger """
/simulate/{simID}/status:
   get:
      tags:
      - simulation
      summary: Get the status of a simulation
      description: |
         Get the status of a simulation:
         - If the simulation has not started yet, it returns -1
         - If the simulation has has failed, it returns -2
         - If the simulation is running, it returns a value between 0 and 100
         - If the simulation has finished but the reconstruction is in progress, it returns 100
         - If the reconstruction has finished, it returns 101
      parameters:
         - in: path
           name: simID
           required: true
           description: The ID of the simulation
           schema:
              type: integer
              example: 1
      responses:
         '200':
            description: Simulation status
            content:
              application/json:
                schema:
                  type: object
                  properties:
                     progress:
                        type: integer
                        description: Simulation progress
         '404':
            description: Simulation not found
         '500':
            description: Internal server error
"""
@get "/simulate/{simID}/status" function(req::HTTP.Request, simID)
   return HTTP.Response(200,body=JSON3.write(SIM_PROGRESSES[parse(Int, simID)]))
end

## RECONSTRUCTION
@swagger """
/recon/{simID}:
   post:
      tags:
      - reconstruction
      summary: Start reconstruction for a completed simulation
      description: Start reconstruction for a previously completed simulation using the existing simulation data
      parameters:
         - in: path
           name: simID
           required: true
           description: The ID of the completed simulation to reconstruct
           schema:
              type: integer
              example: 1
      responses:
         '202':
            description: Accepted operation
            headers:
              Location:
                description: URL with the reconstruction ID, to check the status of the reconstruction
                schema:
                  type: string
                  format: uri
         '400':
            description: Invalid input (no simulation data or simulation not complete)
         '500':
            description: Internal server error
"""
@post "/recon/{simID}" function(req::HTTP.Request, simID)
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   _simID = parse(Int, simID)

   if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
      assign_process(uname) # We assign a new julia process to the user
   end

   pid = ACTIVE_SESSIONS[uname]

   # Check if we have simulation data for this user
   if !haskey(RAW_RESULTS, uname)
      return HTTP.Response(400, body="No simulation data available for reconstruction")
   end

   # Check if simulation is complete by checking if we can fetch the result
   try
      fetch(RAW_RESULTS[uname])
   catch
      return HTTP.Response(400, body="Simulation not yet complete")
   end
   
   RECON_RESULTS[uname] = @spawnat pid recon(fetch(RAW_RESULTS[uname]), SEQUENCES[uname], ROT_MATRICES[uname], STATUS_FILES[_simID])
   
   headers = ["Location" => string("/recon/",_simID)]
   # 202: Accepted
   return HTTP.Response(202,headers)
end

@get "/recon/{simID}" function(req::HTTP.Request, simID, width::Int, height::Int)
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   _simID = parse(Int, simID)
   io = open(STATUS_FILES[_simID],"r")
   RECON_PROGRESSES[_simID] = -1 # Initialize reconstruction progress
   if (!eof(io))
      RECON_PROGRESSES[_simID] = read(io,Int32)
   end
   close(io)
   if RECON_PROGRESSES[_simID] == 100 # Reconstruction not finished
      headers = ["Location" => string("/recon/",_simID,"/status")]
      return HTTP.Response(303,headers)
   elseif RECON_PROGRESSES[_simID] == 101 # Reconstruction finished
      img    = fetch(RECON_RESULTS[uname])[1]
      kspace = fetch(RECON_RESULTS[uname])[2]
      width  = width  - 15
      height = height - 20
      p_img    = plot_image(abs.(img[:,:,1]);    darkmode=true, width=width, height=height)
      p_kspace = plot_image(abs.(kspace[:,:,1]); darkmode=true, width=width, height=height, zmax=percentile(vec(abs.(kspace[:,:,1])), 99))
      
      # Create separate HTML buffers
      img_buffer = IOBuffer()
      kspace_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(img_buffer, p_img.plot)
      KomaMRIPlots.PlotlyBase.to_html(kspace_buffer, p_kspace.plot)
      
      # Get the HTML content
      img_html = String(take!(img_buffer))
      kspace_html = String(take!(kspace_buffer))
      
      # Return as JSON
      result = Dict(
          "image_html" => img_html,
          "kspace_html" => kspace_html
      )
      
      return HTTP.Response(200, body=JSON3.write(result))
   else
      return HTTP.Response(404, body="Simulation not found")
   end
end

@get "/recon/{simID}/status" function(req::HTTP.Request, simID)
   return HTTP.Response(200,body=JSON3.write(RECON_PROGRESSES[parse(Int, simID)]))
end

# PLOT SEQUENCE
@swagger """
/plot_sequence:
   post:
      tags:
      - plot
      summary: Plot a sequence
      description: Plot a sequence and k-space for the user session
      responses: 
         '200':
            description: Plot of the sequence
            content:
              text/html:
                schema:
                  format: html
         '400':
            description: Invalid input
         '500':
            description: Internal server error
"""
@post "/plot_sequence" function(req::HTTP.Request)
   try
      scanner_data = json(req)["scanner"]
      seq_data     = json(req)["sequence"]
      width  = json(req)["width"]  - 15
      height = json(req)["height"] - 20
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
      uname = claims(jwt2)["username"]

      if !haskey(ACTIVE_SESSIONS, uname)
         assign_process(uname)
      end
      pid = ACTIVE_SESSIONS[uname]

      SCANNERS[uname]                       = json_to_scanner(scanner_data)
      seq_obj, rot = json_to_sequence(seq_data, SCANNERS[uname])
      SEQUENCES[uname]        = seq_obj
      ROT_MATRICES[uname]     = rot

      p_seq    = remotecall_fetch(plot_seq, pid, SEQUENCES[uname]; darkmode=true, width=width, height=height, slider=height>275)
      p_kspace = remotecall_fetch(plot_kspace, pid, SEQUENCES[uname]; darkmode=true, width=width, height=height)

      seq_buffer = IOBuffer()
      kspace_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(seq_buffer, p_seq.plot)
      KomaMRIPlots.PlotlyBase.to_html(kspace_buffer, p_kspace.plot)

      seq_html = String(take!(seq_buffer))
      kspace_html = String(take!(kspace_buffer))

      result = Dict(
          "seq_html" => seq_html,
          "kspace_html" => kspace_html
      )

      return HTTP.Response(200,body=JSON3.write(result))
   catch e
      return HTTP.Response(500,body=JSON3.write(string(e)))
   end
end

# SELECT AND PLOT PHANTOM
@swagger """
/plot_phantom:
   post:
      tags:
      - plot
      summary: Initialize and plot the selected phantom for the user
      responses: 
         '200':
            description: Interactive HTML plot of the selected phantom
            content:
              text/html:
                schema:
                  format: html
         '400':
            description: Invalid input
         '401':
            description: Unauthorized
         '500':
            description: Internal server error
"""
@post "/plot_phantom" function(req::HTTP.Request)
   try
      input_data = json(req)
      phantom_string = input_data["phantom"]
      map_str = input_data["map"]
      map = map_str == "PD" ? :ρ  : 
            map_str == "dw" ? :Δw : 
            map_str == "T1" ? :T1 : 
            map_str == "T2" ? :T2 : map_str
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
      uname = claims(jwt2)["username"]

      if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
         assign_process(uname) # Assign a new Julia process to the user
      end
      pid = ACTIVE_SESSIONS[uname]

      phantom_path = "phantoms/$phantom_string/$phantom_string.phantom"
      obj = read_phantom(phantom_path)
      obj.Δw .= 0
      PHANTOMS[uname] = obj

      width  = json(req)["width"]  - 15
      height = json(req)["height"] - 15
      time_samples = obj.name == "Aorta"         ? 100 : 
                     obj.name == "Flow Cylinder" ? 50  : 2;
      ss           = obj.name == "Aorta"         ? 100 : 
                     obj.name == "Flow Cylinder" ? 100 : 1;

      p = @spawnat pid plot_phantom_map(PHANTOMS[uname][1:ss:end], map; darkmode=true, width=width, height=height, time_samples=time_samples)
      html_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(html_buffer, fetch(p).plot)
      return HTTP.Response(200,body=take!(html_buffer))
   catch e
      return HTTP.Response(500,body=JSON3.write(e))
   end
end
@swagger """
/plot:
   post:
      tags:
      - plot
      summary: Plot a sequence
      description: Plot a sequence
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     scanner:
                        type: object
                     sequence:
                        type: object
                     width:
                        type: integer
                     height:
                        type: integer
               example:
                  scanner: {
                     "parameters": {
                        "b0": 1.5,
                        "b1": 10e-6,
                        "deltat": 2e-6,
                        "gmax": 60e-3,
                        "smax": 500
                     },
                  }
                  sequence: {
                     "blocks": [
                        {
                              "children": [],
                              "cod": 1,
                              "duration": 1e-3,
                              "gradients": [
                                 {
                                    "amplitude": 1e-3,
                                    "axis": "x",
                                    "delay": 0,
                                    "flatTop": 1e-3,
                                    "rise": 5e-4
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "y",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "z",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 }
                              ],
                              "name": "",
                              "ngroups": 0,
                              "rf": [
                                 {
                                    "deltaf": 0,
                                    "flipAngle": 10,
                                    "shape": 0
                                 }
                              ]
                        },
                        {
                           "adcDelay": 0,
                           "children": [],
                           "cod": 4,
                           "duration": 1e-3,
                           "gradients": [
                              {
                                 "amplitude": 1e-3,
                                 "axis": "x",
                                 "delay": 0,
                                 "flatTop": 1e-3,
                                 "rise": 5e-4
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "y",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "z",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              }
                           ],
                           "name": "",
                           "ngroups": 0,
                           "samples": 64
                        }
                     ],
                     "description": "Simple RF pulse and ADC sequence",
                  }
                  width: 800
                  height: 600
      responses: 
         '200':
            description: Plot of the sequence
            content:
              text/html:
                schema:
                  format: html
         '400':
            description: Invalid input
         '500':
            description: Internal server error
"""
@post "/plot" function(req::HTTP.Request)
   try
      json_data = normalize_keys(json(req))
      scanner_data = json_data["scanner"]
      seq_data     = json_data["sequence"]
      width  = json_data["width"]  - 15
      height = json_data["height"] - 20
      sys = json_to_scanner(scanner_data)
      seq = json_to_sequence(seq_data, sys)
      p = plot_seq(seq; darkmode=true, width=width, height=height, slider=height>275)
      html_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(html_buffer, p.plot)
      return HTTP.Response(200,body=take!(html_buffer))
   catch e
      return HTTP.Response(500,body=JSON3.write(e))
   end
end

# --------------------- ADMIN ENDPOINTS ---------------------

@get "/admin" function(req::HTTP.Request)
    println("⚠️ Recibida petición a /admin")
    
    is_admin_user, username = check_admin(req)
    
    println("⚠️ check_admin resultado: is_admin=$is_admin_user, username=$username")
    
    if username === nothing
        println("⚠️ Usuario no autenticado, redirigiendo a login")
        return HTTP.Response(303, ["Location" => "/login"])
    end
    
    if !is_admin_user
        println("⚠️ Usuario $username no es administrador, acceso denegado")
        return HTTP.Response(403, ["Content-Type" => "text/html"],
            """
            <html>
            <head><title>Acceso Denegado</title></head>
            <body>
                <h1>Acceso Denegado</h1>
                <p>No tienes permisos de administrador para acceder a esta página.</p>
                <p><a href="/app">Volver a la aplicación</a></p>
            </body>
            </html>
            """)
    end
    
    println("⚠️ Usuario $username es administrador, mostrando panel")
    
    # Verificar si el archivo existe
    admin_html_path = string(dynamic_files_path, "/admin.html")
    if isfile(admin_html_path)
        return HTTP.Response(200, ["Content-Type" => "text/html"], 
                            read(admin_html_path, String))
    else
        # Solución de respaldo - generar HTML directamente
        println("⚠️ Archivo admin.html no encontrado, generando respuesta HTML directa")
        admin_html = """
        <!DOCTYPE html>
        <html lang="es">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Panel de Administración - MRSeqStudio</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
                .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                h1 { color: #333; }
                .alert { background-color: #f8d7da; color: #721c24; padding: 10px; border-radius: 4px; margin-bottom: 15px; }
                .btn { display: inline-block; padding: 8px 16px; background-color: #4CAF50; color: white; text-decoration: none; border-radius: 4px; margin-right: 10px; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Panel de Administración</h1>
                <div class="alert">
                    Nota: Esta es una versión simplificada del panel. El archivo admin.html no se encontró en la compilación.
                </div>
                
                <div>
                    <a href="/app" class="btn">Volver a la App</a>
                    <a href="/logout" class="btn">Cerrar Sesión</a>
                </div>
                
                <div id="content" style="margin-top: 20px;">
                    <p>Cargando datos de usuarios...</p>
                </div>
            </div>
            
            <script>
                // Cargar datos de usuarios
                fetch('/api/admin/users')
                    .then(response => response.json())
                    .then(data => {
                        const content = document.getElementById('content');
                        content.innerHTML = '<h2>Usuarios en el sistema:</h2>';
                        
                        const list = document.createElement('ul');
                        data.forEach(user => {
                            const item = document.createElement('li');
                            item.textContent = user.username + ' (' + user.email + ') - Admin: ' + 
                                              (user.is_admin ? 'Sí' : 'No') + ', Premium: ' + 
                                              (user.is_premium ? 'Sí' : 'No');
                            list.appendChild(item);
                        });
                        
                        content.appendChild(list);
                    })
                    .catch(error => {
                        console.error('Error:', error);
                        document.getElementById('content').innerHTML = '<p>Error al cargar usuarios</p>';
                    });
            </script>
        </body>
        </html>
        """
        
        return HTTP.Response(200, ["Content-Type" => "text/html"], admin_html)
    end
end

@get "/api/admin/users" function(req::HTTP.Request)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_all_users()
end

@get "/api/admin/sequences" function(req::HTTP.Request)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_all_sequences()
end

@get "/api/admin/sequences/{userId}" function(req::HTTP.Request, userId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_user_sequences(parse(Int, userId))
end

@get "/api/admin/results/{resultId}" function(req::HTTP.Request, resultId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_result_details(parse(Int, resultId))
end

@delete "/api/admin/results/{resultId}" function(req::HTTP.Request, resultId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return delete_result(parse(Int, resultId), req)
end

@get "/api/admin/stats/sequences" function(req::HTTP.Request)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_sequence_usage_stats()
end

@get "/api/admin/users/{userId}/sequences" function(req::HTTP.Request, userId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_user_sequence_usage(parse(Int, userId))
end

@post "/api/admin/users" function(req::HTTP.Request)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    # Obtener JSON y normalizar a strings
    json_data = json(req)
    println("JSON recibido en /api/admin/users: ", json_data)
    
    # Convertir a Dict y normalizar claves a strings
    input_data = normalize_keys(json_data)
    println("Campos disponibles normalizados: ", keys(input_data))
    
    # Verificar campos obligatorios con strings
    required_fields = ["username", "password", "email"]
    for field in required_fields
        if !haskey(input_data, field)
            println("❌ Falta campo requerido: $field")
            return HTTP.Response(400, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Campo requerido faltante: $field")))
        end
    end
    
    # Crear usuario con los datos validados
    try
        return admin_create_user(input_data)
    catch e
        println("❌ Error al crear usuario: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error al crear usuario: $e")))
    end
end

@put "/api/admin/users/{userId}" function(req::HTTP.Request, userId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    input_data = normalize_keys(json(req))
    return update_user(parse(Int, userId), input_data)
end

@post "/api/admin/users/{userId}/reset-password" function(req::HTTP.Request, userId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    input_data = normalize_keys(json(req))
    if !haskey(input_data, "new_password")
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Falta la nueva contraseña")))
    end
    
    return reset_user_password(parse(Int, userId), input_data["new_password"])
end

@delete "/api/admin/users/{userId}" function(req::HTTP.Request, userId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return delete_user(parse(Int, userId))
end

@get "/api/admin/results" function(req::HTTP.Request)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_all_results()
end

@get "/api/admin/sequence-usage" function(req::HTTP.Request)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_all_sequence_usage()
end

@get "/api/admin/sequence-usage/{usageId}" function(req::HTTP.Request, usageId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    return get_sequence_usage_by_id(parse(Int, usageId))
end

@put "/api/admin/sequence-usage/{usageId}" function(req::HTTP.Request, usageId)
    is_admin_user, _ = check_admin(req)
    
    if !is_admin_user
        return HTTP.Response(403)
    end
    
    input_data = normalize_keys(json(req))
    
    if !haskey(input_data, "sequences_used")
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Falta el campo sequences_used")))
    end
    
    return update_sequence_usage(parse(Int, usageId), input_data["sequences_used"])
end

# Redirige /results a /results.html 
@get "/results" function(req::HTTP.Request)
   return HTTP.Response(301, ["Location" => "/results.html"])
end

# Endpoint para la API de resultados
@get "/api/results" function(req)
   username = get_user_from_jwt(req)
   results = get_user_results(username)
   return HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(results))
end

@get "/api/results/{id}/download" function(req, id)
    println("buscando id usuario")
    username = get_user_from_jwt(req)
    println("Descarga solicitada: usuario=$username, id=$id")
    return download_simulation_result(username, parse(Int, id))
end

@delete "/api/results/{id}" function(req, id)
    return delete_result(parse(Int, id), req)
end
# ---------------------------------------------------------------------------

# title and version are required
info = Dict("title" => "MRSeqStudio API", "version" => "1.0.0")
openApi = OpenAPI("3.0", info)
swagger_document = build(openApi)
  
# merge the SwaggerMarkdown schema with the internal schema
setschema(swagger_document)

serve(host="0.0.0.0",port=8000, middleware=[AuthMiddleware])






